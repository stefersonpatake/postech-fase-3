output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "lab_role_arn" {
  value = data.aws_iam_role.lab.arn
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "ecr_registry" {
  value = module.ecr.registry
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  value = module.eks.cluster_security_group_id
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "rds_endpoints" {
  value = { for k, m in module.rds : k => m.address }
}

output "redis_endpoint" {
  value = module.redis.primary_endpoint
}

output "dynamodb_table" {
  value = module.dynamodb.table_name
}

output "sqs_queue_url" {
  value = module.sqs.url
}

output "secret_names" {
  description = "Secrets no Secrets Manager consumidos pelo External Secrets Operator"
  value = [
    module.secret_auth.name,
    module.secret_flag.name,
    module.secret_targeting.name,
    module.secret_evaluation.name,
    module.secret_evaluation_api_key.name,
  ]
}
