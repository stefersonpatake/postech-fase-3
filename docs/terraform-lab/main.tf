# ─── locals: valores calculados, reutilizados no código ─────
locals {
  prefixo = "${var.projeto}-${var.ambiente}"

  # Filtra só os serviços que usam banco (expressão "for" com condição).
  servicos_com_banco = { for nome, s in var.servicos : nome => s if s.usa_banco }
}

# ─── data source: LÊ algo que já existe, sem gerenciar ───────
# No projeto real: data "aws_iam_role" "lab" lê a LabRole, que não foi criada por nós.
# Aqui: lê um arquivo que já está na pasta e que o Terraform nunca altera nem apaga.
data "local_file" "role_existente" {
  filename = "${path.module}/existente/lab-role.txt"
}

# ─── resource com for_each: uma senha por serviço que usa banco ──
# No projeto real: random_password.db em terraform/infra/databases.tf.
resource "random_password" "banco" {
  for_each = local.servicos_com_banco

  length  = 16
  special = false
}

# ─── module: um bloco de código reutilizável, chamado uma vez por serviço ──
# No projeto real: module "rds" com for_each em terraform/infra/databases.tf.
module "servico" {
  source   = "./modules/servico"
  for_each = var.servicos

  nome      = each.key
  prefixo   = local.prefixo
  porta     = each.value.porta
  usa_banco = each.value.usa_banco

  # Referência a outro recurso: o Terraform entende que precisa ler o data source
  # antes de criar o módulo. Ninguém escreveu essa ordem: ela vem das referências.
  role = trimspace(data.local_file.role_existente.content)
}
