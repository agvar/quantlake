output "ecr_repository_url" {
  value = aws_ecr_repository.websocket_relay.repository_url
}

output "cluster_name"    { value = aws_ecs_cluster.main.name }
output "service_name"    { value = aws_ecs_service.relay.name }
output "task_family"     { value = aws_ecs_task_definition.relay.family }
output "log_group"       { value = aws_cloudwatch_log_group.task.name }
output "task_role_arn"   { value = aws_iam_role.task_role.arn }
output "task_exec_role_arn" { value = aws_iam_role.task_exec.arn }
