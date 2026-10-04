variable "name" {
  description = "Nome do secret no Secrets Manager (ex.: togglemaster/auth-service)"
  type        = string
}

variable "description" {
  type    = string
  default = null
}

variable "values" {
  description = "Pares chave/valor gravados como JSON; cada chave vira uma variável de ambiente no pod via ESO"
  type        = map(string)
  sensitive   = true
}

variable "ignore_value_changes" {
  description = "true quando o valor é preenchido fora do Terraform (ex.: chave gerada em runtime)"
  type        = bool
  default     = false
}
