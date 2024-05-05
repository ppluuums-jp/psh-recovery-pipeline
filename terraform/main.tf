resource "google_project_service" "service" {
  for_each = toset([
    "iam.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "eventarc.googleapis.com",
    "workflow.googleapis.com",
    "servicehealth.googleapis.com"
  ])

  service            = each.key
  project            = var.project_id
  disable_on_destroy = false
}

module "cloud_run" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/cloud-run-v2?ref=v30.0.0"
  project_id = var.project_id
  prefix     = var.prefix
  region     = var.region
  name       = "job"
  create_job = true
  containers = {
    job = {
      image = "us-docker.pkg.dev/cloudrun/container/job:latest" # Sample image
    }
  }
  service_account = module.service_account.email
}

resource "google_pubsub_topic" "event_arc" {
  name    = "${var.prefix}-event-arc"
  project = var.project_id
}

module "service_account" {
  source        = "terraform-google-modules/service-accounts/google"
  version       = "~> 4.1.1"
  project_id    = var.project_id
  prefix        = var.prefix
  names         = ["sa"]
  project_roles = ["${var.project_id}=>roles/eventarc.eventReceiver", "${var.project_id}=>roles/workflows.invoker", "${var.project_id}=>roles/run.developer"]
}

module "cloud_workflow" {
  source                = "GoogleCloudPlatform/cloud-workflows/google"
  version               = "0.1.1"
  project_id            = var.project_id
  workflow_name         = "${var.prefix}-wf"
  region                = var.region
  service_account_email = module.service_account.email
  workflow_trigger = {
    event_arc = {
      name                  = "${var.prefix}-trigger-pubsub-workflow-tf"
      service_account_email = module.service_account.email
      matching_criteria = [{
        attribute = "type"
        value     = "google.cloud.pubsub.topic.v1.messagePublished"
      }]
      pubsub_topic_id = google_pubsub_topic.event_arc.id
    }
  }
  workflow_source = file("config/workflows.yaml")
}

resource "google_monitoring_notification_channel" "pubsub" {
  project      = var.project_id
  display_name = "${var.prefix}-notification-channel"
  type         = "pubsub"
  labels = {
    topic = "projects/${var.project_id}/topics/${google_pubsub_topic.event_arc.name}"
  }
}

resource "google_pubsub_topic_iam_member" "member" {
  project = var.project_id
  topic   = google_pubsub_topic.event_arc.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-monitoring-notification.iam.gserviceaccount.com"
}

resource "google_monitoring_alert_policy" "alert_policy_all" {
  project      = var.project_id
  display_name = "${var.prefix}-alert-policy"
  combiner     = "OR"
  enabled      = "true"
  conditions {
    display_name = "${var.prefix}-condition"
    condition_matched_log {
      filter = yamldecode(file("config/alert_policy_filter.yaml"))["psh-recovery"][0]
      label_extractors = {
        state             = "EXTRACT(jsonPayload.state)"
        description       = "EXTRACT(jsonPayload.description)"
        impactedProducts  = "EXTRACT(jsonPayload.impactedProducts)"
        startTime         = "EXTRACT(jsonPayload.startTime)"
        title             = "EXTRACT(jsonPayload.title)"
        impactedLocations = "EXTRACT(jsonPayload.impactedLocations)"
      }
    }
  }
  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
  }
  notification_channels = [google_monitoring_notification_channel.pubsub.id]
}