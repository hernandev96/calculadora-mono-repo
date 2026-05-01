# Terraform — Infraestructura (AWS)

Este directorio contiene la configuración de Terraform para aprovisionar la infraestructura necesaria para la aplicación "calculadora" en AWS.

Resumen rápido
- VPC con 2 subnets públicas + 2 privadas, IGW, NAT Gateways y tablas de ruteo.
- Security Groups para nodos, ALB y comunicación interna.
- ECR: repositorios para frontend y backend.
- EKS: clúster EKS (v1.35.x) y Managed Node Group.
- ALB: Application Load Balancer creado dentro del módulo VPC (listener + target group).
- S3 + DynamoDB: bucket y tabla para estado remoto y locking (creados por Terraform).
- IAM: roles y attachments necesarios para EKS y nodos.

Estructura relevante
- `main.tf` — Configuración principal del entorno y recursos globales.
- `variables.tf` — Variables globales (ej. `region`).
- `modules/VPC` — Módulo VPC (subredes, SGs, ALB).
- `modules/ECR` — Módulo ECR (repositorios).
- `outputs.tf` (en módulos) — Exports útiles (subnets, IDs, ALB DNS, etc).

Requisitos
- Terraform >= 1.2
- AWS provider (versión fijada en la configuración ~> 5.92)
- Credenciales AWS configuradas en el entorno (p. ej. `aws configure` o variables de entorno).
- Permisos suficientes para crear recursos: VPC, EC2, ELBv2, EKS, IAM, S3, DynamoDB, ECR.

Variables importantes
- `region` (definida en `variables.tf` por defecto `us-east-1`).
- Para parámetros de nodos (tipo de instancia, tamaño del grupo) se recomienda parametrizar con archivos `*.tfvars` por entorno.

Flujo recomendado para Backend remoto (S3 + DynamoDB)
> Nota: Terraform no puede usar como backend un bucket S3 creado por la misma ejecución en un único paso. Sigue estos pasos:

1) Primera ejecución para crear bucket S3 y tabla DynamoDB (usa backend local temporalmente):
```calculadora-mono-repo/infra/terraform/README.md#L60-65
cd infra/terraform
terraform init
terraform apply -var="region=us-east-1"
```

2) Añadir el bloque `backend "s3"` al bloque `terraform` (en `main.tf` o crear `backend.tf`) y reconfigurar:
```calculadora-mono-repo/infra/terraform/README.md#L66-76
# ejemplo a añadir (reemplaza nombres)
terraform {
  backend "s3" {
    bucket         = "calculadora-terraform-state-<ACCOUNT>-<REGION>"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "calculadora-terraform-locks-<REGION>-<ACCOUNT>"
    encrypt        = true
  }
}
```

Luego:
```calculadora-mono-repo/infra/terraform/README.md#L77-79
terraform init -reconfigure
```

Despliegue paso a paso
1. Posiciónate en el directorio:
```calculadora-mono-repo/infra/terraform/README.md#L82-84
cd infra/terraform
```

2. Inicializar Terraform:
```calculadora-mono-repo/infra/terraform/README.md#L85-87
terraform init
```

3. Revisar el plan (pasa variables si aplica):
```calculadora-mono-repo/infra/terraform/README.md#L88-90
terraform plan -out=tfplan -var="region=us-east-1"
```

4. Aplicar los cambios:
```calculadora-mono-repo/infra/terraform/README.md#L91-95
terraform apply "tfplan"
# o aplicar directamente (no recomendado en equipos sin revisión)
terraform apply -var="region=us-east-1"
```

5. Destruir recursos (cuando sea necesario):
```calculadora-mono-repo/infra/terraform/README.md#L96-98
terraform destroy -var="region=us-east-1"
```

Outputs útiles que se exportan
- `module.vpc.vpc_id`
- `module.vpc.public_subnet_ids`
- `module.vpc.private_subnet_ids`
- `module.vpc.alb_dns_name` (DNS del ALB)
- `module.vpc.alb_arn`
- `aws_eks_cluster.calculadora.endpoint`
- `aws_eks_node_group.calculadora_nodes.node_group_name`
- `aws_s3_bucket.tfstate.id` (bucket de estado)
- `aws_dynamodb_table.terraform_locks.name` (tabla para locking)

ALB y su integración con EKS
- El ALB se crea dentro del módulo VPC y su target group actual está configurado con `target_type = "instance"`. Esto funciona apuntando a instancias EC2.
- Para enrutar tráfico directamente a pods en EKS (recomendado), instala el AWS Load Balancer Controller en el cluster EKS. El controller creará y gestionará los ALB/target groups necesarios a partir de Ingress/Service anotados.
- Alternativa menos recomendada: cambiar `target_type` a `ip` y gestionar registros de IP manualmente.

Ejemplo mínimo de archivo `dev.tfvars`
```calculadora-mono-repo/infra/terraform/README.md#L123-129
region = "us-east-1"

# Parámetros que puedes añadir y parametrizar:
# instance_type = "t3.medium"
# node_group_desired_size = 2
```

Buenas prácticas y recomendaciones
- Usa archivos `*.tfvars` por entorno (dev/staging/prod) y no subir credenciales a Git.
- Mantén el backend S3 + DynamoDB para trabajo en equipo y CI/CD.
- Parametriza `instance_types`, `desired_size` y `disk_size` por entorno.
- Usa roles IAM de menor privilegio para pipelines CI/CD.

Consideraciones de costos
- NAT Gateways, EKS (nodos), ALB y EIPs generan coste. Revisa la factura y destruye recursos de prueba cuando no se usen.

Posibles problemas y soluciones
- Permisos insuficientes: revisa el usuario/rol que ejecuta Terraform.
- Nombres de bucket S3 duplicados: el nombre propuesto incluye account_id y región para evitar choques; si falla, cambia el nombre manualmente.
- Límites de EKS (ENIs/IPv4/instancias): comprueba quotas en la consola de AWS si falla la creación de nodos.
- Error al crear ALB: asegúrate de que las subnets públicas y security groups existen y permiten tráfico 80/443.



Contacto
- Infraestructura: @MMCJUAREZ, @hernandev96

---
