terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~> 5.0"
        }
    }
    backend "s3" {
        bucket = "vfc-bucket-gitops"
        key = "StateFiles/state.tfstate"
        region = "us-west-1"
    }   
}