# Acesso aos bancos apenas a partir do security group do cluster EKS
# (anexado pelo EKS ao control plane e aos nós do managed node group).

resource "aws_security_group" "rds" {
  name        = "${var.project}-rds"
  description = "PostgreSQL acessivel apenas pelos nos do EKS"
  vpc_id      = module.network.vpc_id

  tags = { Name = "${var.project}-rds" }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_eks" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = module.eks.cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL a partir do EKS"
}

resource "aws_security_group" "redis" {
  name        = "${var.project}-redis"
  description = "Redis acessivel apenas pelos nos do EKS"
  vpc_id      = module.network.vpc_id

  tags = { Name = "${var.project}-redis" }
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_eks" {
  security_group_id            = aws_security_group.redis.id
  referenced_security_group_id = module.eks.cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  description                  = "Redis a partir do EKS"
}
