output "vpc_id" {
  value = module.network.vpc_id
}

output "raw_bucket_name" {
  value = module.s3_buckets.raw_bucket
}

output "clean_bucket_name" {
  value = module.s3_buckets.clean_bucket
}

output "aurora_endpoint" {
  value = module.postgres.endpoint
}

output "alb_dns" {
  value = aws_lb.main.dns_name
}

output "api_target_group_arn" {
  value = module.ecs_api.target_group_arn
}

output "ui_target_group_arn" {
  value = module.ecs_ui.target_group_arn
}

output "ecs_api_service_name" {
  value = module.ecs_api.service_name
}

output "ecs_ui_service_name" {
  value = module.ecs_ui.service_name
}

output "ecs_api_cluster_name" {
  value = module.ecs_api.cluster_name
}

output "ecs_ui_cluster_name" {
  value = module.ecs_ui.cluster_name
}

# ECS task debug commands
output "api_task_debug" {
  value = join(" ", [
    "aws ecs describe-tasks",
    "--cluster", "$(terraform output -raw ecs_api_cluster_name)",
    "--tasks", "$(aws ecs list-tasks --cluster $(terraform output -raw ecs_api_cluster_name) --service-name $(terraform output -raw ecs_api_service_name) --desired-status STOPPED --query 'taskArns[0]' --output text)",
    "--query", "'tasks[0].{lastStatus:lastStatus,stoppedReason:stoppedReason,containers:containers[*].{name:name,lastStatus:lastStatus,reason:reason,exitCode:exitCode}}'"
  ])
}

output "ui_task_debug" {
  value = join(" ", [
    "aws ecs describe-tasks",
    "--cluster", "$(terraform output -raw ecs_ui_cluster_name)",
    "--tasks", "$(aws ecs list-tasks --cluster $(terraform output -raw ecs_ui_cluster_name) --service-name $(terraform output -raw ecs_ui_service_name) --desired-status STOPPED --query 'taskArns[0]' --output text)",
    "--query", "'tasks[0].{lastStatus:lastStatus,stoppedReason:stoppedReason,containers:containers[*].{name:name,lastStatus:lastStatus,reason:reason,exitCode:exitCode}}'"
  ])
}