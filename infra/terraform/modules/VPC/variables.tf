variable "name" {
  description = "Prefix name for resources"
  type        = string
  default     = "calculadora"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to use"
  type        = number
  default     = 2
}

variable "public_subnet_count" {
  description = "Number of public subnets to create (recommended >=2)"
  type        = number
  default     = 2
}

variable "private_subnet_count" {
  description = "Number of private subnets to create (recommended >=2)"
  type        = number
  default     = 2
}
