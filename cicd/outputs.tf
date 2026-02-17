output "terraform_state_bucket" {
  value = aws_s3_bucket.terraform_state.bucket
}

output "terraform_state_key" {
  value = "${var.project_name}/terraform.tfstate"
}

output "terraform_lock_table" {
  value = aws_dynamodb_table.terraform_locks.name
}

output "codepipeline_name" {
  value = aws_codepipeline.terraform.name
}
