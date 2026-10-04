# ─── RDS PostgreSQL (3 instâncias) ──────────────────────────

resource "aws_db_subnet_group" "this" {
  name       = var.project
  subnet_ids = module.network.private_subnet_ids
}

# Senhas geradas pelo Terraform: nunca aparecem em arquivo ou no git.
# Sem caracteres especiais para não exigir escape na DATABASE_URL (formato chave=valor).
resource "random_password" "db" {
  for_each = var.databases

  length  = 32
  special = false
}

module "rds" {
  source   = "../modules/rds"
  for_each = var.databases

  identifier     = "${var.project}-${each.key}"
  db_name        = each.value.db_name
  username       = each.value.username
  password       = random_password.db[each.key].result
  instance_class = var.db_instance_class

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
}

# ─── ElastiCache Redis ──────────────────────────────────────

module "redis" {
  source = "../modules/elasticache"

  name               = "${var.project}-redis"
  node_type          = var.redis_node_type
  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [aws_security_group.redis.id]
}

# ─── DynamoDB ───────────────────────────────────────────────

module "dynamodb" {
  source = "../modules/dynamodb"

  table_name = var.dynamodb_table_name
  hash_key   = "event_id"
}
