variable "namespace" {
  description = "Prefixo dos repositórios (ex.: togglemaster → togglemaster/auth-service)"
  type        = string
}

variable "repositories" {
  description = "Nomes dos repositórios, um por microsserviço"
  type        = set(string)
}

variable "max_images" {
  description = "Quantidade de imagens mantidas por repositório (as mais antigas são expiradas)"
  type        = number
  default     = 15
}
