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
