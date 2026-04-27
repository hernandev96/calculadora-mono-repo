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

  }
  required_version = ">= 1.2"
}

# Configuración del proveedor de aws.
provider "aws" {
  region = var.region
}

module "vpc" {
  source = "./modules/VPC"

  name = "calculadora"

  vpc_cidr = "10.0.0.0/16"

  az_count             = 2
  public_subnet_count  = 2
  private_subnet_count = 2
}

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

# Información de la cuenta para nombres únicos
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
# IAM Roles y policies para EKS
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

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

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

# Clúster EKS
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
# -----------------------------

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnets" {
  value = module.vpc.public_subnet_ids
}


output "private_subnets" {
  value = module.vpc.private_subnet_ids
}

output "eks_cluster_name" {
  value = aws_eks_cluster.calculadora.name
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.calculadora.endpoint
}

output "eks_cluster_arn" {
  value = aws_eks_cluster.calculadora.arn
}

output "eks_node_group_name" {
  value = aws_eks_node_group.calculadora_nodes.node_group_name
}

output "terraform_state_bucket" {
  value = aws_s3_bucket.tfstate.id
}

output "terraform_locks_table" {
  value = aws_dynamodb_table.terraform_locks.name
}
