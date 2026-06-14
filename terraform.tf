terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.50.0"
    }
  }

  backend "s3" {
    bucket         = "demo-state-943818144398-us-west-2"
    key            = "terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    use_lockfile = true 
  }
}