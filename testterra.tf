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



# For AR-253 and AR-154 Start
resource "aws_kms_key" "encryptionKey" {
  description             = "test encryption key"
  deletion_window_in_days = 10
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

# For AR-253 and AR-154 End

# For AR-257, AR-258 and AR-259 Start
resource "aws_db_instance" "dbInstance1" {
  allocated_storage       = 20
  storage_type            = "gp2"
  engine                  = "mysql"
  engine_version          = "5.7"
  instance_class          = "db.t2.small"
  name                    = "encryptedDb"
  username                = "test"
  password                = "test12345678"
  parameter_group_name    = "default.mysql5.7"
  storage_encrypted       = true
  backup_retention_period = 0
  skip_final_snapshot     = true
}

resource "aws_db_instance" "dbInstance2" {
  allocated_storage       = 20
  storage_type            = "gp2"
  engine                  = "mysql"
  engine_version          = "5.7"
  instance_class          = "db.t2.micro"
  name                    = "nonencryptedDb"
  username                = "test"
  password                = "test12345678"
  parameter_group_name    = "default.mysql5.7"
  storage_encrypted       = false
  backup_retention_period = 1
  skip_final_snapshot     = true
}


# For AR-257, AR-258 and AR-259 End

# For AR-266 Start
resource "aws_ebs_volume" "encrypted_ebs_volume" {
  availability_zone = "us-west-2a"
  size              = 40
  encrypted         = true
  kms_key_id        = aws_kms_key.encryptionKey.arn
  tags = {
    Name = "encrypted_ebs_volume"
  }
}

resource "aws_ebs_volume" "nonencrypted_ebs_volume" {
  availability_zone = "us-west-2a"
  size              = 40
  encrypted         = false
  tags = {
    Name = "nonencrypted_ebs_volume"
  }
}
# For AR-266 End

# Rule AR-524 Start

resource "aws_iam_policy" "testFailPolicyAutomation" {
  name        = "testFailPolicyAutomation"
  path        = "/"
  description = "This policy is to fail a rule AR-524"
  policy      = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "*",
      "Resource": "*"
    }
  ]
}
POLICY
}


resource "aws_iam_policy" "testPassPolicyAutomation" {
  name        = "testPassPolicyAutomation"
  path        = "/"
  description = "This policy is to pass a rule AR-524"
  policy      = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
     "Action": [
                "s3:GetBucketPublicAccessBlock"
      ],
      "Resource": "*"
    }
  ]
}
POLICY
}


# Rule AR-524 End



#For AR-1003 Start
resource "aws_instance" "i-ec2-publicInstance" {
  ami           = data.aws_ami.ubuntu.id
  ebs_optimized = false
  instance_type = "c5.large"

  monitoring                  = false
  vpc_security_group_ids      = [aws_security_group.sg-testAutomationSGFail.id]
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.main.id
  source_dest_check           = true

  root_block_device {
    volume_type           = "gp2"
    volume_size           = 8
    delete_on_termination = true
  }
  tags = {
    Name = "publicec2"
  }
}

resource "aws_instance" "i-ec2-privateInstance" {
  ami           = data.aws_ami.ubuntu.id
  ebs_optimized = false
  instance_type = "c5.large"

  monitoring                  = false
  vpc_security_group_ids      = [aws_security_group.sg-testAutomationSGFail.id]
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.main.id
  source_dest_check           = true

  root_block_device {
    volume_type           = "gp2"
    volume_size           = 8
    delete_on_termination = true
  }
  tags = {
    Name = "privateec2"
  }
}

resource "aws_security_group" "sg-testAutomationSGFail" {
  name        = "testAutomationSGFail"
  description = "Rule AR-1003"
  vpc_id      = aws_vpc.vpc-testAutomation.id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_security_group" "sg-testAutomationSGPass" {
  name        = "testAutomationSGPass"
  description = "Rule AR-1003"
  vpc_id      = aws_vpc.vpc-testAutomation.id

  ingress {
    from_port   = 3378
    to_port     = 3379
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_subnet" "main" {
  vpc_id     = aws_vpc.vpc-testAutomation.id
  cidr_block = "172.31.32.0/20"

  tags = {
    Name = "Main"
  }
}

resource "aws_vpc" "vpc-testAutomation" {
  cidr_block           = "172.31.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  instance_tenancy     = "default"

  tags = {
  }
}
#For AR-1003 Start

#AR-262 Start

resource "aws_redshift_cluster" "test-automation-non-encrpyted-redshift" {
  cluster_identifier  = "test-automation-non-encrpyted-redshift"
  database_name       = "nonencrpytedredshift"
  master_username     = "foo"
  master_password     = "Mustbe8characters"
  node_type           = "dc1.large"
  cluster_type        = "single-node"
  skip_final_snapshot = true
}


resource "aws_redshift_cluster" "test-automation-encrpyted-redshift" {
  cluster_identifier  = "test-automation-encrpyted-redshift"
  database_name       = "encrpytedredshift"
  master_username     = "foo"
  master_password     = "Mustbe8characters"
  node_type           = "dc1.large"
  cluster_type        = "single-node"
  encrypted           = true
  skip_final_snapshot = true
}

#AR-262 End



resource "aws_sns_topic" "reTestTopic" {
  name            = "reTestTopic"
  display_name    = ""
  policy          = <<POLICY
{
  "Version": "2008-10-17",
  "Id": "__default_policy_ID",
  "Statement": [
    {
      "Sid": "__default_statement_ID",
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": [
        "SNS:GetTopicAttributes",
        "SNS:SetTopicAttributes",
        "SNS:AddPermission",
        "SNS:RemovePermission",
        "SNS:DeleteTopic",
        "SNS:Subscribe",
        "SNS:ListSubscriptionsByTopic",
        "SNS:Publish",
        "SNS:Receive"
      ],
      "Resource": "arn:aws:sns:ap-northeast-1:${data.aws_caller_identity.current.account_id}:reTestTopic",
      "Condition": {
        "StringEquals": {
          "AWS:SourceOwner": "${data.aws_caller_identity.current.account_id}"
        }
      }
    },
    {
      "Sid": "__console_pub_0",
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": "SNS:Publish",
      "Resource": "arn:aws:sns:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:test"
    },
    {
      "Sid": "__console_sub_0",
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": [
        "SNS:Subscribe",
        "SNS:Receive"
      ],
      "Resource": "arn:aws:sns:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:test"
    }
  ]
}
POLICY
}

resource "aws_sns_topic" "testTopic" {
  name            = "testTopic"
  display_name    = ""
  policy          = <<POLICY
{
  "Version": "2008-10-17",
  "Id": "__default_policy_ID",
  "Statement": [
    {
      "Sid": "__default_statement_ID",
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": [
        "SNS:GetTopicAttributes",
        "SNS:SetTopicAttributes",
        "SNS:AddPermission",
        "SNS:RemovePermission",
        "SNS:DeleteTopic",
        "SNS:Subscribe",
        "SNS:ListSubscriptionsByTopic",
        "SNS:Publish",
        "SNS:Receive"
      ],
      "Resource": "arn:aws:sns:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:testTopic",
      "Condition": {
        "StringEquals": {
          "AWS:SourceOwner": "${data.aws_caller_identity.current.account_id}"
        }
      }
    }
  ]
}
POLICY
}

resource "aws_ses_domain_identity" "example" {
  domain = "sophos.automation.com"
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "Some comment"
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

resource "aws_cloudfront_distribution" "distribution1" {
  origin {
    domain_name = "${aws_s3_bucket.sophos-test-bucket-1.bucket_regional_domain_name}"
    origin_id   = "${local.s3_origin_id}"
  }
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "DE"]
    }
  }

  tags = {
    Name = "distribution1"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "aws_cloudfront_distribution" "distribution2" {
  origin {
    domain_name = "${aws_s3_bucket.sophos-test-bucket-2.bucket_regional_domain_name}"
    origin_id   = "${local.s3_origin_id}"
    s3_origin_config {
      origin_access_identity = "${aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path}"
    }
  }


  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "DE"]
    }
  }

  tags = {
    Name = "distribution1"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
