terraform {
  backend "s3" {
    bucket         = "n8n-taurak-state"
    key            = "n8n/ecs/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "n8n-taurak-state-lock"
    encrypt        = true
  }
}
