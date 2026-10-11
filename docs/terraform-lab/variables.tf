# Variáveis: as "entradas" do código. Têm tipo, descrição e, opcionalmente, valor padrão.
# Podem ser sobrescritas na linha de comando:  terraform apply -var ambiente=prod

variable "projeto" {
  description = "Prefixo usado nos nomes"
  type        = string
  default     = "togglemaster"
}

variable "ambiente" {
  description = "Nome do ambiente"
  type        = string
  default     = "lab"
}

# Um mapa de objetos: cada chave é um serviço. É o mesmo padrão da variável
# "databases" do projeto real (terraform/infra/variables.tf).
variable "servicos" {
  description = "Serviços a criar; a chave é o nome do serviço"
  type = map(object({
    porta     = number
    usa_banco = bool
  }))
  default = {
    auth = { porta = 8001, usa_banco = true }
    flag = { porta = 8002, usa_banco = true }
  }
}
