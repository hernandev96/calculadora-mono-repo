variable "name" {
  description = "Prefijo para los recursos"
  type        = string
  default     = "calculadora"
}

variable "vpc_cidr" {
  description = "CIDR block de la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Número de zonas de disponibilidad a usar"
  type        = number
  default     = 2
}

variable "public_subnet_count" {
  description = "Número de subredes públicas a crear "
  type        = number
  default     = 2
}

variable "private_subnet_count" {
  description = "Número de subredes privadas a crear"
  type        = number
  default     = 2
}
