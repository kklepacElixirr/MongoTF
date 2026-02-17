# CodeCommit repository for source control
# Set create_codecommit_repository = false if you manage the repo separately

resource "aws_codecommit_repository" "mongotf" {
  count = var.create_codecommit_repository ? 1 : 0

  repository_name = var.codecommit_repository_name
  description     = "MongoDB infrastructure - Terraform"

  tags = {
    Name        = var.codecommit_repository_name
    Environment = var.environment
  }
}
