# ArgoCD: motor de GitOps. As Applications (app-of-apps) são definidas no
# repositório, em gitops/argocd/ (Etapa 6).
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true
  timeout          = 600

  values = [yamlencode({
    configs = {
      params = {
        # TLS termina fora do pod (port-forward/ALB); simplifica o acesso à UI.
        "server.insecure" = true
      }
      cm = {
        # Intervalo de verificação do repositório Git (padrão 180s).
        "timeout.reconciliation" = "60s"
      }
    }
    # Sem Dex: login apenas com o usuário admin local.
    dex = { enabled = false }
  })]
  # O webhook do ALB Controller intercepta a criação de todo Service do cluster.
  # Instalar em paralelo falha com "no endpoints available for service
  # aws-load-balancer-webhook-service"; por isso este release espera o controller.
  depends_on = [helm_release.alb_controller]
}
