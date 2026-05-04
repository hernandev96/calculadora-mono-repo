###############################################################################
# infra/terraform/main.tf
#
# Archivo principal de Terraform para aprovisionar la infraestructura AWS
# utilizada por la aplicación "calculadora".
#
# Este archivo:
# - Declara providers y requisitos.
# - Define módulos y recursos globales (ECR, S3/DynamoDB para backend, roles IAM,
#   EKS cluster y node groups).
# - Expone outputs útiles.
#
# ADVERTENCIA SOBRE BACKEND S3:
# Terraform no puede inicializar un backend S3 que apunte a un bucket que se
# crea en la misma ejecución en un único paso. El flujo recomendado:
#  1) Ejecutar terraform con backend local (sin backend S3) para crear el bucket
#     y la tabla DynamoDB (pasos: `terraform init` + `terraform apply`).
#  2) Descomentar (o añadir) el bloque `backend "s3"` de más abajo (líneas marcadas)
#     y ejecutar `terraform init -reconfigure` para migrar el estado al S3/DynamoDB.
#
# Se puede crear el bucket S3 y la tabla DynamoDB manualmente antes
# y dejar el backend "s3" activo desde el inicio.
###############################################################################

# -- Requisitos de Terraform y providers ------------------------------------
terraform {
  required_providers {
    # AWS provider usado para crear recursos en Amazon Web Services.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
  }

  # Requerimos una versión mínima de Terraform
  required_version = ">= 1.2"

  # -------------------------------------------------------------------------
  # Backend S3 (ejemplo) - COMENTADO POR DEFECTO
  #
  # - Si ya has creado manualmente el bucket S3 y la tabla DynamoDB:
  #     descomenta este bloque, ajusta valores y ejecuta:
  #       terraform init -reconfigure
  #
  # - Si vas a dejar que Terraform cree el bucket y tabla, sigue el flujo:
  #     1) Mantén este bloque comentado.
  #     2) terraform init && terraform apply  (crea el bucket & tabla).
  #     3) Descomenta y reconfigure: terraform init -reconfigure
  #
  # NOTA: Nunca apuntes el backend al mismo bucket que se crea en la misma
  # ejecución sin seguir el proceso en dos pasos descrito.
  # -------------------------------------------------------------------------
  #
  # backend "s3" {
  #   bucket         = "calculadora-terraform-state-<ACCOUNT_ID>-<REGION>"
  #   key            = "infrastructure/terraform.tfstate"
  #   region         = "<REGION>"
  #   dynamodb_table = "calculadora-terraform-locks-<REGION>-<ACCOUNT_ID>"
  #   encrypt        = true
  # }
}

# -- Configuración del proveedor AWS ----------------------------------------
provider "aws" {
  region = var.region
}

# -- Módulo VPC --------------------------------------------------------------
# El módulo VPC crea:
# - VPC, subnets públicas y privadas
# - Internet Gateway, NAT Gateways y tablas de ruteo
# - Security Groups: nodes, alb e internal
# - Además el módulo ahora crea el ALB (aws_lb, target group y listener)
module "vpc" {
  source = "./modules/VPC"

  name = "calculadora"

  vpc_cidr = "10.0.0.0/16"

  az_count             = 2
  public_subnet_count  = 2
  private_subnet_count = 2
}

# -- Módulos ECR (frontend y backend) --------------------------------------
module "ecr_frontend" {
  source   = "./modules/ECR"
  ecr_name = "calculadora-frontend"
}

module "ecr_backend" {
  source   = "./modules/ECR"
  ecr_name = "calculadora-backend"
}

# -----------------------------
# Recursos para Terraform remote state (S3 + DynamoDB)
# -----------------------------

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "tfstate" {
  bucket = "calculadora-terraform-state-${data.aws_caller_identity.current.account_id}-${var.region}"
  acl    = "private"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Name = "calculadora-terraform-state"
    Env  = "infra"
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate_block" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "calculadora-terraform-locks-${var.region}-${data.aws_caller_identity.current.account_id}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "calculadora-terraform-locks"
    Env  = "infra"
  }
}

# -----------------------------
# IAM Roles y attachments para EKS
# -----------------------------

resource "aws_iam_role" "eks_cluster_role" {
  name = "calculadora-eks-cluster-role-${data.aws_caller_identity.current.account_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "calculadora-eks-cluster-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSServicePolicy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSVPCResourceController" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

resource "aws_iam_role" "eks_node_role" {
  name = "calculadora-eks-node-role-${data.aws_caller_identity.current.account_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "calculadora-eks-node-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKSWorkerNodePolicy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKS_CNI_Policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEC2ContainerRegistryReadOnly" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# -----------------------------
# EKS Cluster y Managed Node Group
# -----------------------------

resource "aws_eks_cluster" "calculadora" {
  name     = "calculadora-eks-${data.aws_caller_identity.current.account_id}"
  version  = "1.35"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids              = concat(module.vpc.private_subnet_ids, module.vpc.public_subnet_ids)
    security_group_ids      = [module.vpc.security_group_internal_id]
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }

  tags = {
    Name = "calculadora-eks"
    Env  = "infra"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSServicePolicy
  ]
}

resource "aws_eks_node_group" "calculadora_nodes" {
  cluster_name    = aws_eks_cluster.calculadora.name
  node_group_name = "calculadora-managed-ng"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = module.vpc.private_subnet_ids

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.medium"]
  ami_type       = "AL2023_x86_64_STANDARD"
  disk_size      = 20

  remote_access {
    # key_name = null
  }

  tags = {
    Name = "calculadora-managed-nodes"
    Env  = "infra"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks_node_AmazonEC2ContainerRegistryReadOnly,
    aws_eks_cluster.calculadora
  ]
}

# -----------------------------
# Outputs (información útil tras el apply)
# -----------------------------

output "vpc_id" {
  description = "ID de la VPC creada"
  value       = module.vpc.vpc_id
}

output "public_subnets" {
  description = "IDs de subnets públicas"
  value       = module.vpc.public_subnet_ids
}

output "private_subnets" {
  description = "IDs de subnets privadas"
  value       = module.vpc.private_subnet_ids
}

output "eks_cluster_name" {
  description = "Nombre del cluster EKS"
  value       = aws_eks_cluster.calculadora.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint del cluster EKS"
  value       = aws_eks_cluster.calculadora.endpoint
}

output "eks_cluster_arn" {
  description = "ARN del cluster EKS"
  value       = aws_eks_cluster.calculadora.arn
}

output "eks_node_group_name" {
  description = "Nombre del Node Group gestionado"
  value       = aws_eks_node_group.calculadora_nodes.node_group_name
}

output "terraform_state_bucket" {
  description = "Nombre del bucket S3 usado para Terraform state"
  value       = aws_s3_bucket.tfstate.id
}

output "terraform_locks_table" {
  description = "Nombre de la tabla DynamoDB usada para locking"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "alb_dns_name" {
  description = "DNS name del Application Load Balancer (ALB) creado en el módulo VPC"
  value       = try(module.vpc.alb_dns_name, "")
}

output "alb_arn" {
  description = "ARN del ALB (si disponible)"
  value       = try(module.vpc.alb_arn, "")
}
