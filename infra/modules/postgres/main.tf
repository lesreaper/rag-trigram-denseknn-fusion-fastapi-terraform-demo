variable "project" {}
variable "db_password" { sensitive = true }
variable "vpc_id" {}
variable "private_subnets" {
  type = list(string)
}
variable "common_tags" { type = map(string) }

module "aurora" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "8.3.0"

  name                 = "${var.project}-pg"
  engine               = "aurora-postgresql"
  engine_version       = "14"
  storage_encrypted    = true
  master_username      = "postgres"
  master_password      = var.db_password
  vpc_id               = var.vpc_id
  subnets              = var.private_subnets

  # Create a subnet group for the cluster
  create_db_subnet_group = true
  db_subnet_group_name   = "${var.project}-pg"

  # ✅ You MUST declare at least one instance
  instances = {
    writer = {
      instance_class       = "db.serverless"   # Serverless v2
      publicly_accessible  = false
    }
  }

  # Serverless v2 scaling
  serverlessv2_scaling_configuration = {
    min_capacity = 0.5
    max_capacity = 2
  }

  # Optional: faster changes in a demo
  apply_immediately       = true
  deletion_protection     = false

  tags = var.common_tags
}


output "endpoint" {
  value = module.aurora.cluster_endpoint
}

output "reader_endpoint" {
  value = module.aurora.cluster_reader_endpoint
}

output "security_group_id" {
  value = module.aurora.security_group_id
}
