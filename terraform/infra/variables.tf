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
