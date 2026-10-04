output "argocd_namespace" {
  value = helm_release.argocd.namespace
}

output "argocd_admin_password_command" {
  description = "Senha inicial do usuário admin do ArgoCD"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "argocd_port_forward_command" {
  description = "Acesso à UI em http://localhost:8080"
  value       = "kubectl -n argocd port-forward svc/argocd-server 8080:80"
}

output "chart_versions" {
  value = {
    aws-load-balancer-controller = helm_release.alb_controller.version
    external-secrets             = helm_release.external_secrets.version
    argo-cd                      = helm_release.argocd.version
  }
}
