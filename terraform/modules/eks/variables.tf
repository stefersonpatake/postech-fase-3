variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "kubernetes_version" {
  description = "Versão do Kubernetes"
  type        = string
}

variable "cluster_role_arn" {
  description = "Role do control plane (LabRole no AWS Academy)"
  type        = string
}

variable "node_role_arn" {
  description = "Role dos nós (LabRole no AWS Academy)"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets onde o control plane cria suas ENIs (públicas + privadas)"
  type        = list(string)
}

variable "node_subnet_ids" {
  description = "Subnets dos nós (privadas)"
  type        = list(string)
}

variable "node_instance_types" {
  description = "Tipos de instância do node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 3
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}
