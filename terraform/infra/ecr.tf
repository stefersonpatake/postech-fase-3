module "ecr" {
  source = "../modules/ecr"

  namespace    = var.project
  repositories = var.services
}
