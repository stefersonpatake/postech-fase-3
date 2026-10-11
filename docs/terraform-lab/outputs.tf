# Outputs: as "saídas". Aparecem ao final do apply e podem ser lidas por scripts
# (terraform output -raw nome) ou por outra camada (terraform_remote_state).

output "arquivos" {
  description = "Arquivo gerado para cada serviço"
  value       = { for nome, m in module.servico : nome => m.arquivo }
}

output "prefixo" {
  value = local.prefixo
}

# sensitive = true: o valor não é mostrado no terminal nem no plan.
# Atenção: ele continua gravado em texto no state. Por isso o state real fica em
# um bucket privado e criptografado.
output "senhas" {
  description = "Senhas geradas (uma por serviço com banco)"
  value       = { for nome, p in random_password.banco : nome => p.result }
  sensitive   = true
}
