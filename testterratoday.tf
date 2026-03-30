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


  resource "aws_ebs_volume" "encrypted_ebs_volume" {
  availability_zone = "us-west-2a"
  size              = 5000
  type = "st1"         
  tags = {
    Name = "encrypted_ebs_volume"
  }
}

resource "aws_elb" "rishielb" {
  name               = "rishi-elb"
  availability_zones= ["us-west-2a"]

 listener {
    instance_port     = 8000
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  tags = {
    Name = "rishi-terraform-elb"
  }
} 


resource "aws_lb" "alb_rishi" {
  name               = "test-alb-tf"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.main1.id,aws_subnet.main2.id]

  }

  resource "aws_lb" "nlb_rishi" {
  name               = "test-nlb-tf1"
  internal           = false
  load_balancer_type = "network"
  subnets            = [aws_subnet.main1.id]



   
  }

resource "aws_subnet" "main1" {
  vpc_id     = aws_vpc.vpc-testAutomation.id
  cidr_block = "172.31.32.0/20"
  availability_zone = "us-west-2a"

  tags = {
    Name = "Main"
  }
}

  resource "aws_subnet" "main2" {
  vpc_id     = aws_vpc.vpc-testAutomation.id
  cidr_block = "172.31.1.0/24"
  availability_zone = "us-west-2b"


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

resource "aws_internet_gateway" "rishi-gw" {
  vpc_id = aws_vpc.vpc-testAutomation.id

  tags = {
    Name = "main"
  }
}


resource "aws_instance" "rishi-inst" {
  ami           = data.aws_ami.ubuntu.id
  ebs_optimized = false
  instance_type = "m5ad.4xlarge"
  
  tags = {
    Name = "publicec2"
  }
}

resource "aws_db_instance" "rishi-default" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.m5.12xlarge"
  name                 = "mydb"
  identifier           = "ris-auto"
  username             = "testrishi"
  password             = "Password123"
  parameter_group_name = "default.mysql5.7"
  storage_encrypted       = false
  backup_retention_period = 1
  skip_final_snapshot     = true
}

resource "aws_eip" "lb" {
  vpc      = true
}