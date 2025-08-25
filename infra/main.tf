
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket       = "kizen-rag-tf-state"
    key          = "terraform.tfstate"
    region       = "us-east-1"
    profile      = "rx-user"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = "rx-user"
}

locals {
  project = var.project
  common_tags = {
    Project = var.project
    Owner   = var.owner
  }
}

# ───────── Modules ─────────
module "network" {
  source      = "./modules/network"
  project     = local.project
  vpc_cidr    = var.vpc_cidr
  common_tags = local.common_tags
}

# ───────── S3 Buckets ─────────
module "s3_buckets" {
  source              = "./modules/s3_buckets"
  project             = local.project
  raw_bucket_suffix   = "raw"
  clean_bucket_suffix = "clean"
  common_tags         = local.common_tags
}

# ───────── Aurora ─────────
module "postgres" {
  source          = "./modules/postgres"
  project         = local.project
  db_password     = var.db_password
  vpc_id          = module.network.vpc_id
  private_subnets = module.network.private_subnets
  common_tags     = local.common_tags
}

# ───────── ALB Security Group ─────────
resource "aws_security_group" "alb_sg" {
  name   = "${local.project}-alb-sg"
  vpc_id = module.network.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ───────── ALB ─────────
resource "aws_lb" "main" {
  name               = "${local.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = module.network.public_subnets
  idle_timeout       = 300
}

# ───────── Listener ─────────
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }
}


# ───────── API Service ─────────
module "ecs_api" {
  source           = "./modules/ecs_fargate"
  name             = "${local.project}-api"
  image            = var.api_image
  container_port   = 8000
  desired_count    = 1
  vpc_id           = module.network.vpc_id
  subnets          = module.network.private_subnets
  alb_listener_arn = aws_lb_listener.http.arn
  path_pattern     = "/api/*"
  alb_sg_id        = aws_security_group.alb_sg.id
  assign_public_ip = true

  enable_s3_access  = true
  raw_bucket        = var.app_env_vars["RAW_BUCKET"]
  clean_bucket      = var.app_env_vars["CLEAN_BUCKET"]

  env_vars = merge(
    var.app_env_vars,
    {
      POSTGRES_HOST     = module.postgres.endpoint
      POSTGRES_USER     = "postgres"
      POSTGRES_PASSWORD = var.db_password
      POSTGRES_DB       = "postgres"
      POSTGRES_PORT     = "5432"
      DATABASE_URL      = "postgresql://postgres:${var.db_password}@${module.postgres.endpoint}:5432/postgres"
    }
  )
}


# ───────── UI Service ─────────
module "ecs_ui" {
  source             = "./modules/ecs_fargate"
  name               = "${local.project}-ui"
  image              = var.ui_image
  container_port     = 3000
  desired_count      = 1
  vpc_id             = module.network.vpc_id
  subnets            = module.network.private_subnets
  alb_listener_arn   = aws_lb_listener.http.arn
  path_pattern       = "/*"
  env_vars           = var.app_env_vars
  alb_sg_id          = aws_security_group.alb_sg.id
  add_proxy_rule     = true
  proxy_path_pattern = "/proxy/*"
}

resource "aws_security_group_rule" "api_to_db_5432" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.postgres.security_group_id # RDS SG
  source_security_group_id = module.ecs_api.security_group_id  # API task SG
  description              = "Allow API tasks to connect to Aurora on 5432"
}

