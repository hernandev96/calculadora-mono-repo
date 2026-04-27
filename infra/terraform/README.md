# Terraform infra

Este directorio contiene la configuración de Terraform y ejemplos para invocar el módulo VPC.

Uso recomendado:
- Copiar uno de los archivos terraform.*.example.tfvars a terraform.<env>.tfvars y ajustarlo por entorno.
- Ejecutar: terraform init && terraform plan -var-file="terraform.<env>.tfvars"

Ajustar public_subnet_count, private_subnet_count y az_count según la región/entorno.

El módulo VPC está en ./modules/VPC y expone outputs para id de VPC, subnets, route tables y security groups.
