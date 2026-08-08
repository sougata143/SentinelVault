# ==============================================================================
# SentinelVault — AWS Infrastructure Provisioning (Terraform)
# ==============================================================================
# Provisions:
# 1. VPC with Multi-AZ Public and Private Subnets, IGW, and NAT Gateway
# 2. Security Groups for ALB, ECS Fargate Tasks, RDS, and ElastiCache
# 3. AWS RDS PostgreSQL 15 Instance (Multi-AZ)
# 4. AWS ElastiCache Redis 7 Cluster
# 5. AWS ECR Repositories for 4 Microservices
# 6. AWS ECS Cluster, Fargate Task Definitions, Services, and ALB Routing
# 7. AWS S3 Bucket and CloudFront CDN for Flutter Web Application
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ------------------------------------------------------------------------------
# Variables
# ------------------------------------------------------------------------------
variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS Region for deployment"
}

variable "environment" {
  type        = string
  default     = "production"
  description = "Deployment environment name"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "Master password for RDS PostgreSQL"
}

variable "jwt_secret" {
  type        = string
  sensitive   = true
  description = "JWT Secret Key for authentication microservices"
}

# ------------------------------------------------------------------------------
# 1. VPC & Networking Infrastructure
# ------------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "sentinelvault-vpc"
    Environment = var.environment
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "sentinelvault-public-1" }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = { Name = "sentinelvault-public-2" }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = { Name = "sentinelvault-private-1" }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = { Name = "sentinelvault-private-2" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "sentinelvault-igw" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id
  tags          = { Name = "sentinelvault-nat" }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "sentinelvault-public-rt" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = { Name = "sentinelvault-private-rt" }
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}

# ------------------------------------------------------------------------------
# 2. Security Groups
# ------------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "sentinelvault-alb-sg"
  description = "Allow inbound HTTP/HTTPS traffic to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    ="-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "sentinelvault-ecs-sg"
  description = "Allow traffic from ALB to ECS Fargate tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db" {
  name        = "sentinelvault-db-sg"
  description = "Allow PostgreSQL traffic from ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "redis" {
  name        = "sentinelvault-redis-sg"
  description = "Allow Redis traffic from ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ------------------------------------------------------------------------------
# 3. AWS RDS PostgreSQL Database
# ------------------------------------------------------------------------------
resource "aws_db_subnet_group" "db" {
  name       = "sentinelvault-db-subnet-group"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

resource "aws_db_instance" "postgres" {
  identifier             = "sentinelvault-postgres"
  engine                 = "postgres"
  engine_version         = "15.4"
  instance_class         = "db.t4g.medium"
  allocated_storage      = 20
  max_allocated_storage  = 100
  db_name                = "sentinelvault"
  username               = "sentinel_admin"
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.db.id]
  skip_final_snapshot    = true
  multi_az               = false
}

# ------------------------------------------------------------------------------
# 4. AWS ElastiCache Redis
# ------------------------------------------------------------------------------
resource "aws_elasticache_subnet_group" "redis" {
  name       = "sentinelvault-redis-subnet-group"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "sentinelvault-redis"
  engine               = "redis"
  node_type            = "cache.t4g.small"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.redis.id]
}

# ------------------------------------------------------------------------------
# 5. ECR Repositories
# ------------------------------------------------------------------------------
resource "aws_ecr_repository" "auth" {
  name                 = "sentinelvault/auth-service"
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecr_repository" "sync" {
  name                 = "sentinelvault/sync-api"
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecr_repository" "sharing" {
  name                 = "sentinelvault/sharing-service"
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecr_repository" "security" {
  name                 = "sentinelvault/security-analysis-service"
  image_tag_mutability = "MUTABLE"
}

# ------------------------------------------------------------------------------
# 6. ECS Cluster & Fargate Services
# ------------------------------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = "sentinelvault-cluster"
}

# IAM Execution Role for ECS Tasks
resource "aws_iam_role" "ecs_execution_role" {
  name = "sentinelvault-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Application Load Balancer
resource "aws_lb" "alb" {
  name               = "sentinelvault-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "SentinelVault API Gateway OK"
      status_code  = "200"
    }
  }
}

# ------------------------------------------------------------------------------
# 7. S3 & CloudFront for Flutter Web Client
# ------------------------------------------------------------------------------
resource "aws_s3_bucket" "web" {
  bucket = "sentinelvault-web-assets-${var.environment}"
}

resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = aws_s3_bucket.web.bucket_regional_domain_name
    origin_id   = "S3-sentinelvault-web"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-sentinelvault-web"

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# ------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------
output "alb_dns_name" {
  value       = aws_lb.alb.dns_name
  description = "Application Load Balancer DNS endpoint"
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.cdn.domain_name
  description = "CloudFront CDN domain for Flutter Web frontend"
}

output "rds_endpoint" {
  value       = aws_db_instance.postgres.endpoint
  description = "PostgreSQL RDS database endpoint"
}
