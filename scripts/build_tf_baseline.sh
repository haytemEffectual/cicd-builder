#!/bin/bash
# minimal Terraform folder layout
echo ">>>>>> .....creating modules and workflow dirs, and main.tf, providers.tf, versions.tf"
mkdir -p modules/ .github/workflows # build basic structure -- modules and workflows dirs
touch modules/.keep .github/workflows/.keep # keep files to retain empty dirs in git
cat > versions.tf <<'TF'
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
  backend "s3" {
    # Backend configuration will be provided via terraform init flags or backend config file via GH Actions workflows
  }
}
TF

cat > providers.tf <<'TF'
provider "aws" {
  region = var.aws_region
}
TF

cat > variables.tf <<'VAR'
variable "aws_region" {
  type    = string
  default = "us-west-2"
}

# TODO: uncomment and set VPC_CIDR if the VPC is needed to be created via TF
# variable "vpc_cidr" {
#   type = string
# }
VAR

cat > main.tf <<'TF'
# Add Terraform main resources here
# As an Example,below is a VPC Configuration
# 
# TODO: uncomment the below VPC resource if the VPC is needed to be created via TF
# resource "aws_vpc" "main" {
#   cidr_block           = var.vpc_cidr
#   enable_dns_hostnames = true
#   enable_dns_support   = true

#   tags = {
#     Name = "test-vpc"
#   }
# }
TF

find . -type f -name ".keep" -delete
echo ">>>>>> ..... Terraform basic folder structure created."
read -p "Press [Enter] key to continue..."