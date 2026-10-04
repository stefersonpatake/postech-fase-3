resource "aws_secretsmanager_secret" "this" {
  name        = var.name
  description = var.description

  # Sem janela de recuperação: permite destroy + apply em seguida com o mesmo nome.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "managed" {
  count = var.ignore_value_changes ? 0 : 1

  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = jsonencode(var.values)
}

# Valor inicial apenas; depois é atualizado fora do Terraform e não é sobrescrito.
resource "aws_secretsmanager_secret_version" "external" {
  count = var.ignore_value_changes ? 1 : 0

  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = jsonencode(var.values)

  lifecycle {
    ignore_changes = [secret_string]
  }
}
