variable "project_id" {
  type        = string
  default     = ""
  description = "Google Cloud Project ID"
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "Google Cloud Region"
}

variable "prefix" {
  type        = string
  default     = "psh-recovery"
  description = "Prefix for resources"
}
