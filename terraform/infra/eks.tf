module "eks" {
  source = "../modules/eks"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version

  # AWS Academy: control plane e nós usam a LabRole existente.
  cluster_role_arn = data.aws_iam_role.lab.arn
  node_role_arn    = data.aws_iam_role.lab.arn

  subnet_ids      = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  node_subnet_ids = module.network.private_subnet_ids

  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
}
