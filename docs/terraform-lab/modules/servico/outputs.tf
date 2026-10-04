# O que o módulo devolve para quem o chamou (module.servico["auth"].arquivo).
output "arquivo" {
  value = local_file.config.filename
}
