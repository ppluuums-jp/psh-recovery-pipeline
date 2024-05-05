import re


def update_versions_file():
    new_version_constraint = ">= 3.53.0"
    pattern = r'(^\s*version\s*=\s*["\'])([^"\']+)(["\'])'
    file_path = ".terraform/modules/cloud_run/modules/cloud-run-v2/versions.tf"

    with open(file_path, "r") as file:
        file_content = file.read()

    updated_content = re.sub(
        pattern,
        rf"\g<1>{new_version_constraint}\g<3>",
        file_content,
        flags=re.MULTILINE,
    )

    with open(file_path, "w") as file:
        file.write(updated_content)


if __name__ == "__main__":
    update_versions_file()
    print("Version constraint updated successfully.")
