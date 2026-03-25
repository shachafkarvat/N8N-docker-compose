terraform {
  backend "s3" {
    bucket         = "n8n_taurak_state"
    key            = "n8n/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "n8n_taurak_state_lock"
    encrypt        = true
  }
}
