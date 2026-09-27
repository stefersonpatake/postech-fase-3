output "repository_urls" {
  description = "Mapa serviço → URL do repositório"
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "registry" {
  description = "Endereço do registry (<account>.dkr.ecr.<region>.amazonaws.com)"
  value       = split("/", values(aws_ecr_repository.this)[0].repository_url)[0]
}
