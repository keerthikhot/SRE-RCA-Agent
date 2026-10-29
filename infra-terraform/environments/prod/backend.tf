###############################################################################
# environments/prod/backend.tf
#
# IMPORTANT: Fill in bucket and dynamodb_table from the bootstrap outputs:
#   cd terraform/bootstrap
#   terraform output state_bucket_name
#   terraform output state_lock_table
###############################################################################

terraform {
  backend "s3" {
    bucket         = "ai-sre-agent-tfstate-58117740"
    key            = "prod/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "ai-sre-agent-tflock"
    encrypt        = true
  }
}
