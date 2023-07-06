provider "aws" {
  version = "~> 2.0"
  region  = "us-west-2"
}


data "aws_caller_identity" "current" {}
data "aws_region" "current" {}


data "aws_ami" "ubuntu" {
  most_recent = true


  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-trusty-14.04-amd64-server-*"]

  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}


resource "aws_s3_bucket" "testautomation-encryptedbucket" {
  bucket        = "testautomation-encryptedbucket"
  force_destroy = true
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = "aws_kms_key.encryptionKey.arn"
        sse_algorithm     = "aws:kms"
      }
    }
  }
}


resource "aws_s3_bucket" "testautomation-nonencryptedbucket" {
  bucket        = "testautomation-nonencryptedbucket"
  force_destroy = true
  logging {
    target_bucket = aws_s3_bucket.log_bucket.id
    target_prefix = "log/"

  }
}

resource "aws_s3_bucket" "log_bucket" {
  bucket        = "testautomation-log-bucket"
  acl           = "log-delivery-write"
  force_destroy = true
}


resource "aws_s3_bucket" "sophos-test-bucket-1" {
  bucket = "sophos-test-bucket-1-testautomation"
  acl    = "private"
}

resource "aws_s3_bucket" "sophos-test-bucket-2" {
  bucket = "sophos-test-bucket-2-testautomation"
  acl    = "private"
}
locals {
  s3_origin_id = "myS3Origin"
}