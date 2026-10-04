# As variáveis de um módulo são os seus parâmetros: quem chama o módulo
# (o bloco module "servico" em ../../main.tf) precisa informar cada uma.

variable "nome" {
  type = string
}

variable "prefixo" {
  type = string
}

variable "porta" {
  type = number
}

variable "usa_banco" {
  type = bool
}

variable "role" {
  type = string
}
