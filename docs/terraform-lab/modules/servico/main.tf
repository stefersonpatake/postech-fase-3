# O módulo "servico" cria um arquivo de configuração por serviço.
# No projeto real, um módulo cria recursos de nuvem (ex.: modules/rds cria a instância).

resource "local_file" "config" {
  filename = "${path.root}/saida/${var.prefixo}-${var.nome}.conf"

  content = <<-EOT
    # Gerado pelo Terraform - não editar à mão
    servico   = ${var.nome}-service
    porta     = ${var.porta}
    usa_banco = ${var.usa_banco}
    role      = ${var.role}
  EOT
}
