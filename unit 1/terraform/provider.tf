# provider.tf
# ---------------------------------------------------------------------------
# Configures the AWS provider.
#
# Credentials are intentionally NOT set here. Terraform automatically uses the
# standard AWS credential chain (environment variables, shared credentials
# file, or an IAM role). This keeps secrets out of the codebase and out of Git,
# which is a customer responsibility under the Shared Responsibility Model.
#
# `default_tags` applies a consistent set of tags to every taggable resource,
# supporting cost allocation, ownership, and auditability.
# ---------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Course      = "Cloud-Security-PBL-Unit-1"
      Owner       = var.owner
    }
  }
}
