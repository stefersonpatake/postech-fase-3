# External Secrets Operator: sincroniza segredos do AWS Secrets Manager para
# Secrets do Kubernetes.
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_chart_version
  namespace        = "external-secrets"
  create_namespace = true

  values = [yamlencode({
    installCRDs = true
  })]

  # O webhook do ALB Controller intercepta a criação de todo Service do cluster.
  # Instalar em paralelo falha com "no endpoints available for service
  # aws-load-balancer-webhook-service"; por isso este release espera o controller.
  depends_on = [helm_release.alb_controller]
}

# Objetos que dependem dos CRDs instalados acima (ClusterSecretStore). Ficam em um
# chart local porque kubernetes_manifest exige o CRD já existente na hora do plan.
resource "helm_release" "platform_config" {
  name      = "platform-config"
  chart     = "${path.module}/charts/platform-config"
  namespace = "external-secrets"

  values = [yamlencode({
    region = var.region
  })]

  depends_on = [helm_release.external_secrets]
}
