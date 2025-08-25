output "target_group_arn" {
  description = "The ARN of the ALB target group for this ECS service"
  value       = aws_lb_target_group.this.arn
}

output "service_name" {
  description = "The ECS service name"
  value       = aws_ecs_service.this.name
}

output "cluster_name" {
  description = "The ECS cluster name"
  value       = aws_ecs_cluster.this.name
}

output "security_group_id" {
  value = aws_security_group.sg.id
}