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

variable "vpc_cidr" {
  description = "CIDR da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "AZs usadas (us-east-1e não é suportada pelo EKS)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "services" {
  description = "Microsserviços do ToggleMaster"
  type        = set(string)
  default     = ["auth-service", "flag-service", "targeting-service", "evaluation-service", "analytics-service"]
}

variable "kubernetes_version" {
  description = "Versão do Kubernetes do EKS"
  type        = string
  default     = "1.36"
}

variable "node_instance_types" {
  description = "Tipos de instância dos nós"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Quantidade de nós (ArgoCD + ESO + ALB Controller + 5 serviços)"
  type        = number
  default     = 3
}

variable "databases" {
  description = "Instâncias RDS PostgreSQL: uma por serviço que persiste dados relacionais"
  type = map(object({
    db_name  = string
    username = string
  }))
  default = {
    auth      = { db_name = "auth_db", username = "auth_user" }
    flag      = { db_name = "flagapi", username = "flagapi_user" }
    targeting = { db_name = "targeting_db", username = "targeting_user" }
  }
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "redis_node_type" {
  type    = string
  default = "cache.t3.micro"
}

variable "dynamodb_table_name" {
  type    = string
  default = "ToggleMasterAnalytics"
}
