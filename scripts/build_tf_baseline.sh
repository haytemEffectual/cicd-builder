#!/bin/bash
# minimal Terraform folder layout
echo "#### .....creating modules and workflow dirs, and main.tf, providers.tf, versions.tf"
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
  backend "s3" {}
}
TF

cat > providers.tf <<'TF'
variable "aws_region" {
  type    = string
  default = "us-west-2"
}

provider "aws" {
  region = var.aws_region
}
TF

cat > main.tf <<'TF'
# Add Terraform main resources here
TF