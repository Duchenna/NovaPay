terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { 
      source = "hashicorp/aws"
      version = "~> 5.60" 
    }
  }
}
provider "aws" { region = var.region }
variable "region" { default = "eu-west-1" }
variable "image_tag" { default = "latest" }

data "aws_caller_identity" "current" {}