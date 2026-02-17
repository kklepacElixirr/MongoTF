# Bootstrap Terraform - uses local state
# Run this once to create S3, DynamoDB, Pipeline
# After apply: migrate main project state to S3 (see CICD.md)
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
