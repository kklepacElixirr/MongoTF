# Bootstrap Terraform - creates S3, DynamoDB, Pipeline
#
# First run: comment out the backend "s3" block below, then: terraform init && terraform apply.
# Then uncomment the block and migrate state to S3 so the pipeline can auto-apply cicd (see CICD.md).
terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    key = "cicd/terraform.tfstate"
    # bucket, dynamodb_table, region via -backend-config
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
