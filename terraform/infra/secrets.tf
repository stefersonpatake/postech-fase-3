# Segredos por serviço no AWS Secrets Manager. O External Secrets Operator (Etapa 5/6)
# sincroniza cada um para um Secret do Kubernetes, e o pod lê via envFrom.
# Cada chave do JSON vira uma variável de ambiente.

resource "random_password" "auth_master_key" {
  length  = 40
  special = false
}

locals {
  # Mesmas variáveis que os serviços e seus entrypoint.sh já esperam.
  db_secret_values = {
    for k, db in var.databases : k => {
      DB_HOST = module.rds[k].address
      DB_PORT = tostring(module.rds[k].port)
      DB_NAME = db.db_name
      DB_USER = db.username
      DB_PASS = random_password.db[k].result
      DATABASE_URL = join(" ", [
        "host=${module.rds[k].address}",
        "port=${module.rds[k].port}",
        "dbname=${db.db_name}",
        "user=${db.username}",
        "password=${random_password.db[k].result}",
      ])
    }
  }
}

module "secret_auth" {
  source = "../modules/secrets"

  name        = "${var.project}/auth-service"
  description = "Banco e MASTER_KEY do auth-service"
  values = merge(local.db_secret_values["auth"], {
    MASTER_KEY = random_password.auth_master_key.result
  })
}

module "secret_flag" {
  source = "../modules/secrets"

  name        = "${var.project}/flag-service"
  description = "Banco do flag-service"
  values      = local.db_secret_values["flag"]
}

module "secret_targeting" {
  source = "../modules/secrets"

  name        = "${var.project}/targeting-service"
  description = "Banco do targeting-service"
  values      = local.db_secret_values["targeting"]
}

module "secret_evaluation" {
  source = "../modules/secrets"

  name        = "${var.project}/evaluation-service"
  description = "Redis do evaluation-service"
  values = {
    REDIS_URL = module.redis.url
  }
}

# A SERVICE_API_KEY é gerada pelo auth-service em runtime (POST /admin/keys).
# O Terraform só cria o secret com um valor provisório; o valor real é gravado
# depois por script (Etapa 6) e não é sobrescrito em applies futuros.
module "secret_evaluation_api_key" {
  source = "../modules/secrets"

  name                 = "${var.project}/evaluation-service-api-key"
  description          = "SERVICE_API_KEY do evaluation-service, emitida pelo auth-service"
  ignore_value_changes = true
  values = {
    SERVICE_API_KEY = "PENDENTE"
  }
}
