variable "name" {
  type = string
}

variable "visibility_timeout_seconds" {
  type    = number
  default = 30
}

variable "message_retention_seconds" {
  description = "Tempo que uma mensagem não consumida fica na fila (padrão 4 dias)"
  type        = number
  default     = 345600
}
