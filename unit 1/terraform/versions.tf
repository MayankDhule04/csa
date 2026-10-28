# versions.tf
# ---------------------------------------------------------------------------
# Pins the Terraform core version and required providers.
# Pinning versions makes the project reproducible: anyone who clones the repo
# gets the same provider behaviour, which is important for an academic/graded
# Infrastructure-as-Code project.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
