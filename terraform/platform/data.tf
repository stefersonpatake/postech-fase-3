# Outputs da camada infra (cluster, VPC), lidos direto do state remoto.
data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "infra/terraform.tfstate"
    region = var.region
  }
}

data "aws_eks_cluster" "this" {
  name = data.terraform_remote_state.infra.outputs.cluster_name
}
