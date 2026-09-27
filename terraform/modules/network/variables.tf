variable "name" {
  description = "Prefixo dos nomes dos recursos"
  type        = string
}

variable "cidr_block" {
  description = "CIDR da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Zonas de disponibilidade (uma subnet pública e uma privada por AZ)"
  type        = list(string)
}

variable "cluster_name" {
  description = "Nome do cluster EKS, usado nas tags de descoberta de subnets do ALB Controller"
  type        = string
}
