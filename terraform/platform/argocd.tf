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

# Liga o ArgoCD ao repositório: um ApplicationSet gera uma Application por pasta
# em gitops/apps/. Em chart local porque depende dos CRDs do ArgoCD.
resource "helm_release" "argocd_apps" {
  name      = "argocd-apps"
  chart     = "${path.module}/charts/argocd-apps"
  namespace = "argocd"

  values = [yamlencode({
    repoURL  = var.gitops_repo_url
    revision = var.gitops_revision
    appsPath = var.gitops_apps_path
  })]

  # Sem o ESO e o ClusterSecretStore os ExternalSecrets das aplicações não sincronizam.
  depends_on = [helm_release.argocd, helm_release.platform_config]
}
