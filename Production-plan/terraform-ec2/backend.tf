terraform {
  backend "s3" {
    bucket         = "n8n-taurak-state"
    key            = "n8n/ec2/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "n8n-taurak-state-lock"
    encrypt        = true
  }
}
