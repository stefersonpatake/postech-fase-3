resource "aws_elasticache_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
}

# Replication group com 1 nó: é o recurso que permite criptografia em trânsito (TLS).
resource "aws_elasticache_replication_group" "this" {
  replication_group_id = var.name
  description          = "Cache do evaluation-service"

  engine         = "redis"
  engine_version = var.engine_version
  node_type      = var.node_type
  port           = 6379

  num_cache_clusters         = 1
  automatic_failover_enabled = false

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = var.security_group_ids

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  apply_immediately = true
}
