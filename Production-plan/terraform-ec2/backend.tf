terraform {
  backend "s3" {
    bucket  = "n8n-taurak-tfstate"
    key     = "n8n/ec2/terraform.tfstate"
    region  = "eu-west-2"
    encrypt = true
  }
}
