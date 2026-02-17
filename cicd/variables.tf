variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "project_name" {
  type    = string
  default = "mongotf"
}

variable "codecommit_repository_name" {
  type        = string
  default     = "mongotf"
  description = "CodeCommit repo name - must match exactly (case-sensitive). Use MongoTF if your repo is named MongoTF."
}

variable "approve_apply" {
  description = "If true, CodeBuild will auto-apply. If false, only plan runs."
  type        = bool
  default     = false
}

variable "mongodb_password_parameter" {
  description = "SSM Parameter Store path for TF_VAR_mongodb_root_password (create with: aws ssm put-parameter --name /mongotf/tfvar/mongodb_root_password --value 'YourPassword' --type SecureString)"
  type        = string
  default     = "/mongotf/tfvar/mongodb_root_password"
}

variable "rotate_mongodb_password" {
  description = "If true, after Terraform apply the pipeline runs SSM Run Command on the EC2 instance to set the MongoDB root password to the value in mongodb_password_parameter (so instance and SSM stay in sync)."
  type        = bool
  default     = false
}
