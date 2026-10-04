variable "region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Prefixo usado nos nomes dos recursos"
  type        = string
  default     = "togglemaster"
}

variable "state_bucket" {
  description = "Bucket do state remoto (para ler os outputs da camada infra)"
  type        = string
  default     = "togglemaster-tfstate-583383233548"
}

# Versões dos charts fixadas: upgrades são uma mudança explícita no código.
variable "alb_controller_chart_version" {
  type    = string
  default = "3.5.0"
}

variable "external_secrets_chart_version" {
  type    = string
  default = "2.11.0"
}

variable "argocd_chart_version" {
  type    = string
  default = "10.9.6"
}

variable "gitops_repo_url" {
  description = "Repositório Git monitorado pelo ArgoCD"
  type        = string
  default     = "https://github.com/stefersonpatake/postech-fase-3.git"
}

variable "gitops_revision" {
  description = "Branch monitorado pelo ArgoCD"
  type        = string
  default     = "main"
}

variable "gitops_apps_path" {
  description = "Pasta do repositório com um diretório Kustomize por microsserviço"
  type        = string
  default     = "gitops/apps"
}
