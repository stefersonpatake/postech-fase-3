module "network" {
  source = "../modules/network"

  name         = var.project
  cidr_block   = var.vpc_cidr
  azs          = var.azs
  cluster_name = local.cluster_name
}
