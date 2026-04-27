// VPC module: creates VPC, public/private subnets, IGW, NAT Gateways, route tables and SGs
# se obtienen las zonas de disponibilidad disponibles
data "aws_availability_zones" "available" {}
# se crea la VPC con los parámetros especificados
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name}-vpc"
  }
}
# se crea el Internet Gateway para la VPC
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-igw"
  }
}
# se crean las subredes públicas y privadas
resource "aws_subnet" "public" {
  count                   = var.public_subnet_count
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name}-public-${count.index}"
    Tier = "public"
  }
}
# se crean las direcciones IP públicas para los NAT Gateways
resource "aws_eip" "nat" {
  count = var.public_subnet_count


  tags = {
    Name = "${var.name}-nat-eip-${count.index}"
  }
}
# se crean los NAT Gateways para la VPC
resource "aws_nat_gateway" "this" {
  count         = var.public_subnet_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.name}-nat-${count.index}"
  }
}
# se crean las subredes privadas
resource "aws_subnet" "private" {
  count             = var.private_subnet_count
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, var.public_subnet_count + count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.name}-private-${count.index}"
    Tier = "private"
  }
}
# se crean las tablas de rutas públicas y privadas
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-public-rt"
  }
}
# se crean las rutas para acceder a Internet a través del NAT Gateway
resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}
# se asocian las tablas de rutas públicas con las subredes públicas
resource "aws_route_table_association" "public" {
  count          = var.public_subnet_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
# se crean las tablas de rutas privadas
resource "aws_route_table" "private" {
  count  = var.private_subnet_count
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-private-rt-${count.index}"
  }
}
# se crean las rutas para acceder a Internet a través del NAT Gateway
resource "aws_route" "private_nat" {
  count                  = var.private_subnet_count
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}
# se asocian las tablas de rutas privadas con las subredes privadas
resource "aws_route_table_association" "private" {
  count          = var.private_subnet_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Security groups
# se crean los grupos de seguridad para los nodos del cluster
resource "aws_security_group" "nodes" {
  name        = "${var.name}-nodes-sg"
  description = "Security group for cluster nodes"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Allow all traffic within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-nodes" }
}
# se crean los grupos de seguridad para el ALB
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-alb" }
}
# se crean los grupos de seguridad para los servicios internos
resource "aws_security_group" "internal" {
  name        = "${var.name}-internal-sg"
  description = "Security group for internal services"
  vpc_id      = aws_vpc.this.id

  # allow all traffic from nodes and alb and VPC
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.nodes.id, aws_security_group.alb.id]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-internal" }
}

# -----------------------------
# Application Load Balancer (ALB) en subnets públicas
# -----------------------------

# se crea el ALB en las subredes públicas
resource "aws_lb" "alb" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = {
    Name = "${var.name}-alb"
  }
}

# se crea el target group para el ALB
resource "aws_lb_target_group" "app_tg" {
  name     = "${var.name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  target_type = "instance"

  tags = {
    Name = "${var.name}-tg"
  }
}

# se crea el listener para el ALB
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}
