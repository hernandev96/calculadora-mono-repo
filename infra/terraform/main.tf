# Infrastructura para desplegar calculadora en aws
#
# Se configura el proveedor de aws y tls para la infraestructura.
# Infraestrutura a crear
# VPC con CIDR /16 (ej: 10.0.0.0/16)
# 2+ subnets públicas y 2+ subnets privadas
# Internet Gateway, NAT Gateway(s), route tables
# Security groups para nodos, ALB y comunicación interna
# Dos repositorios ECR (frontend y backend)
# Clúster EKS (versión 1.29+)
# Managed node group (t3.medium como mínimo para dev, t3.large para staging/prod)
# S3 bucket + DynamoDB table para Terraform remote state y locking

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1.2"
}

# Configuración del proveedor de aws.
provider "aws" {
  region = var.region
}

# Example usage of the VPC module
# Adjust values in environment-specific tfvars (public/private subnet counts, AZs, name, CIDR)
module "vpc" {
  source = "./modules/VPC"

  # Prefix used in resource names
  name = "calculadora"

  # VPC CIDR (default in module is 10.0.0.0/16)
  vpc_cidr = "10.0.0.0/16"

  # number of availability zones / subnets to create
  az_count = 2
  public_subnet_count = 2
  private_subnet_count = 2
}

# Example to show how to reference module outputs
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnets" {
  value = module.vpc.public_subnet_ids
}
