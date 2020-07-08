variable "image_id" {
  type = string
  default = "SWASTIK"
}
variable "min_size" {
  description = "The minimum number of EC2 Instances in the ASG"
  type        = number
  default = 1000
}
variable "oke_network_vcn" {
	type = bool
	default = false 
}
variable "subnet_cidr" {
  description = "CIDR for subnet"
  default = "172.16.10.0/24"
}
variable "subnet_name" {
  description = "name for subnet"
  default = "tf-0.12-rvt-example-subnet"
}
variable "interface_ips" {
  type = list
  description = "IP for network interface"
  default = ["172.16.10.100"]
}
variable "availability_zone_names" {
  type    = list(string)
  default = ["us-west-1a"]
}
variable "list_numbers" {
  type    = list(number)
  default = [1,2,3]
}
variable "object" {
  type    = object({
    number = number
    string = string
  })

  default = {
    number = 1
    string = "aaa"
  }
}
variable "docker_ports" {
  type = list(object({
    internal = number
    external = number
    protocol = string
  }))
  default = [
    {
      internal = 8300
      external = 8300
      protocol = "tcp"
    }
  ]
}
variable "ipset" {
  type = list(object({
    value = string
    type  = string
  }))
 
  default = [
    { value = "1.1.1.1/32", type="IPV4" },
    { value = "2.2.2.2/32", type="IPV4" },
  ]
}
variable "map_string" {
  type    = map(string)
  default = { key1 = "a", key2 = "b", key3 = "b"}
}
variable "zones" {
    type = "map"
    default = {
        "amsterdam" = "nl-ams1"
        "london"    = "uk-lon1"
        "frankfurt" = "de-fra1"
        "helsinki1" = "fi-hel1"
        "helsinki2" = "fi-hel2"
        "chicago"   = "us-chi1"
        "sanjose"   = "us-sjo1"
        "singapore" = "sg-sin1"
    }
}
variable "set_password" {
    type = bool
    default = false
}