locals {
  network_config = {
    vpc_name = var.vpc_name
    vpc_cidr = var.vpc_cidr
    subnet_name = var.subnet_name
    subnet_cidr = var.subnet_cidr
  }
}
resource "aws_instance" "example" {
  instance_type = "t2.micro"
  ami           = var.image_id
}
resource "numbers" "example" {
  number           = var.list_numbers
  number_element   = var.list_numbers[1]
}
resource "aws_security_group" "example1" {
  name        = "friendly_subnets"
  description = "Allows access from friendly subnets"
  min_size = var.min_size
}
resource "aws_security_group" "example2" {
  flag = var.oke_network_vcn
}
resource "aws_network_interface" "rvt" {
  subnet_id = module.network.subnet_id
  private_ips = var.interface_ips[0]
  tags = {
    Name = "tf-0.12-rvt-example-interface"
  }
}
resource "aws_network_interface1" "rvt" {
  availability_zone_names = var.availability_zone_names
}
resource "aws_object" "object" {
  object = var.object.number
  object2 = var.object.string
  object3 = var.object
}
resource "aws_list" "list_object" {
  object = var.docker_ports
  number = var.docker_ports[0].internal
  string = var.docker_ports[0].protocol
  object3 = var.ipset[1]
}
resource "aws_map" "map_string" {
  string = var.map_string.key1
  zones = var.zones.amsterdam
}
resource "aws_boolean" "boolean" {
	boolean = var.set_password
}