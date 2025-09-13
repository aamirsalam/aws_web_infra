terraform {
  backend "s3" {
    bucket         = "tfstate-aamir-demo"
    key            = "aws_web_infra/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform_locks"
    encrypt        = true
  }
}