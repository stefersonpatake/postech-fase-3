# AWS Load Balancer Controller: cria ALBs a partir dos recursos Ingress.
# Credenciais AWS: role do nó (LabRole) via IMDS — sem IRSA no Academy.
resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.alb_controller_chart_version
  namespace  = "kube-system"

  values = [yamlencode({
    clusterName = data.aws_eks_cluster.this.name
    region      = var.region
    vpcId       = data.terraform_remote_state.infra.outputs.vpc_id
    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
    }
  })]
}
