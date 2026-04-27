# Infrastructura para desplegar calculadora en aws
#
# Se configura el proveedor de aws
# Infraestrutura a crear
# VPC con CIDR /16 (ej: 10.0.0.0/16)
# 2+ subnets públicas y 2+ subnets privadas
# Internet Gateway, NAT Gateway(s), route tables
# Security groups para nodos, ALB y comunicación interna
# Dos repositorios ECR (frontend y backend)
# Clúster EKS (versión 1.29+)
# Managed node group (t3.medium como mínimo para dev, t3.large para staging/prod)
# S3 bucket + DynamoDB table para Terraform remote state y locking

# Se configura Terraform para usar el proveedor de aws
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }

  }
  required_version = ">= 1.2"
}

# Configuración del proveedor de aws con la region a usar.
provider "aws" {
  region = var.region
}

# se crea la VPC para la calculadora
module "vpc" {
  source = "./modules/VPC"

  name = "calculadora"

  vpc_cidr = "10.0.0.0/16"

  az_count             = 2
  public_subnet_count  = 2
  private_subnet_count = 2
}

# se crea el repositorio ECR para el frontend
module "ecr_frontend" {
  source   = "./modules/ECR"
  ecr_name = "calculadora-frontend"
}

# se crea el repositorio ECR para el backend
module "ecr_backend" {
  source   = "./modules/ECR"
  ecr_name = "calculadora-backend"
}

# -----------------------------
# Recursos para Terraform remote state (S3 + DynamoDB)
# Se utilizan para almacenar el estado de Terraform y evitar conflictos en la infraestructura.
# -----------------------------

# Información de la cuenta para nombres únicos
data "aws_caller_identity" "current" {}

# se crea el bucket S3 para almacenar el estado de Terraform
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
# se configura el bloqueo de acceso público para el bucket S3
resource "aws_s3_bucket_public_access_block" "tfstate_block" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# se crea la tabla DynamoDB para almacenar los bloqueos de Terraform
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
# IAM Roles y policies para EKS
# se crean los roles y policies necesarios para EKS
# -----------------------------

# IAM role para el control plane de EKS
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
# se adjunta la política AmazonEKSClusterPolicy al rol de EKS
resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
# se adjunta la política AmazonEKSServicePolicy al rol de EKS
resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSServicePolicy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
}

# (Opcional pero recomendado) VPC resource controller para EKS
resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSVPCResourceController" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

# IAM role para los nodos gestionados (node group)
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
# se adjunta la política AmazonEKSWorkerNodePolicy al rol de EKS
resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKSWorkerNodePolicy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
# se adjunta la política AmazonEKS_CNI_Policy al rol de EKS
resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKS_CNI_Policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
# se adjunta la política AmazonEC2ContainerRegistryReadOnly al rol de EKS
resource "aws_iam_role_policy_attachment" "eks_node_AmazonEC2ContainerRegistryReadOnly" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# -----------------------------
# EKS Cluster y Managed Node Group
# se crea el clúster EKS y el Managed Node Group
# -----------------------------

# Clúster EKS
# se crea el clúster EKS con la configuración especificada
resource "aws_eks_cluster" "calculadora" {
  name     = "calculadora-eks-${data.aws_caller_identity.current.account_id}"
  version  = "1.35.4"
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

  # asegurar que las attachments del role existen antes de crear el cluster
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSServicePolicy
  ]
}

# Managed Node Group
# se crea el Managed Node Group con la configuración especificada
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

  # Para entornos de desarrollo usamos t3.medium (ajustable por entorno)
  instance_types = ["t3.medium"]
  ami_type       = "AL2_x86_64"
  # Tamaño del disco por nodos (en GiB)
  disk_size = 20

  # Sin acceso SSH por clave (usar Session Manager / SSM si se necesita)
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
# Outputs
# Para mostrar información de la infraestructura
# -----------------------------
# ID de la VPC
output "vpc_id" {
  value = module.vpc.vpc_id
}
# IDs de las subredes públicas
output "public_subnets" {
  value = module.vpc.public_subnet_ids
}
# IDs de las subredes privadas
output "private_subnets" {
  value = module.vpc.private_subnet_ids
}
# nombre del cluster EKS
output "eks_cluster_name" {
  value = aws_eks_cluster.calculadora.name
}
# endpoint del cluster EKS
output "eks_cluster_endpoint" {
  value = aws_eks_cluster.calculadora.endpoint
}

# ARN del cluster EKS
output "eks_cluster_arn" {
  value = aws_eks_cluster.calculadora.arn
}
# nombre del grupo de nodos EKS
output "eks_node_group_name" {
  value = aws_eks_node_group.calculadora_nodes.node_group_name
}
# nombre del bucket de estado de Terraform
output "terraform_state_bucket" {
  value = aws_s3_bucket.tfstate.id
}
# nombre de la tabla de bloqueos de Terraform
output "terraform_locks_table" {
  value = aws_dynamodb_table.terraform_locks.name
}
