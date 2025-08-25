variable "name" {}
variable "image" {}
variable "container_port" {}
variable "desired_count" { default = 1 }
variable "vpc_id" {}
variable "subnets" { type = list(string) }
variable "env_vars" { type = map(string) }
variable "alb_listener_arn" {}
variable "path_pattern" { default = "/*" }
variable "alb_sg_id" {
  description = "Security group ID of the ALB to allow ingress from"
  type        = string
}
variable "add_proxy_rule" { default = false }
variable "proxy_path_pattern" { default = "/proxy/*" }
variable "enable_s3_access" {
  type = bool
  default = false
}
variable "raw_bucket"       {
  type = string
  default = null
}
variable "clean_bucket"     { 
  type = string
  default = null
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  depends_on = [aws_cloudwatch_log_group.ecs_logs]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn = aws_iam_role.exec.arn
  task_role_arn      = aws_iam_role.task[0].arn

  container_definitions = jsonencode([{
    name      = var.name
    image     = var.image
    essential = true
    portMappings = [{
      containerPort = var.container_port
      hostPort      = var.container_port
    }]
    environment = [
      for k, v in var.env_vars : { name = k, value = v }
    ]
    logConfiguration = {
        logDriver = "awslogs",
        options = {
            awslogs-group         = "/ecs/${var.name}",
            awslogs-region        = "us-east-1",
            awslogs-stream-prefix = "ecs"
        }
    }
  }])
}

resource "aws_iam_role" "exec" {
  name               = "${var.name}-ecsTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_ssm" {
  role       = aws_iam_role.exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


resource "aws_iam_role_policy_attachment" "ecs_task_exec" {
  role       = aws_iam_role.exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_security_group" "sg" {
  name   = "${var.name}-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [var.alb_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


variable "assign_public_ip" {
  type    = bool
  default = false
}


resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  enable_execute_command = true

  network_configuration {
    subnets         = var.subnets
    security_groups = [aws_security_group.sg.id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.name
    container_port   = var.container_port
  }
}

resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"
}

resource "aws_lb_target_group" "this" {
  name        = "${var.name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = var.path_pattern == "/api/*" ? "/api/health" : "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 10
    matcher             = "200"
  }

}

resource "aws_lb_listener_rule" "this" {
  listener_arn = var.alb_listener_arn
  priority = (
    var.path_pattern == "/api/*"   ? 100  :
    var.path_pattern == "/proxy/*" ? 110  :
    /* default for wildcard and anything else */ 9999
    )

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  condition {
    path_pattern {
      values = [var.path_pattern]
    }
  }
}

resource "aws_lb_listener_rule" "ui_proxy" {
  count        = var.add_proxy_rule ? 1 : 0
  listener_arn = var.alb_listener_arn
  priority     = 110   # must be >100 (so /api/* wins) and <9999 (so it beats /*)

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  condition {
    path_pattern {
      values = [var.proxy_path_pattern] # "/proxy/*"
    }
  }
}



resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${var.name}"
  retention_in_days = 7
}

# Task role for the application container
resource "aws_iam_role" "task" {
  count              = 1 # always create the role; it's fine to have it even if no S3 policy
  name               = "${var.name}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

# Attach S3 perms only when requested (API service needs it, UI doesn't)
resource "aws_iam_role_policy" "task_s3" {
  count = var.enable_s3_access ? 1 : 0
  name  = "${var.name}-task-s3"
  role  = aws_iam_role.task[0].id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["s3:PutObject","s3:GetObject","s3:AbortMultipartUpload","s3:ListBucketMultipartUploads"],
        Resource = [
          "arn:aws:s3:::${var.raw_bucket}/*",
          "arn:aws:s3:::${var.clean_bucket}/*"
        ]
      },
      {
        Effect   = "Allow",
        Action   = ["s3:ListBucket"],
        Resource = [
          "arn:aws:s3:::${var.raw_bucket}",
          "arn:aws:s3:::${var.clean_bucket}"
        ]
      }
    ]
  })
}


