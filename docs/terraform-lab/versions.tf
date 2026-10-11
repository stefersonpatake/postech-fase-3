# Bloco "terraform": versão mínima da ferramenta e quais providers (plugins) o projeto usa.
# No projeto real (terraform/infra/versions.tf) o provider é o "aws".
# Aqui usamos dois providers que não precisam de nuvem nem de credenciais:
#   - local:  cria arquivos na sua máquina
#   - random: gera valores aleatórios (o projeto real usa para as senhas do RDS)
terraform {
  required_version = ">= 1.10"

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Sem bloco "backend": o state fica em um arquivo local (terraform.tfstate).
  # No projeto real ele fica em um bucket S3 (terraform/infra/backend.tf).
}
