# Creacion de ECR pàra Frontend y Backend
# Se crea el repositorio ECR para alojar las imágenes de la calculadora
resource "aws_ecr_repository" "ecr" {
  name                 = var.ecr_name
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}
