# Etapa 4 — Bancos de dados, mensageria e segredos

Objetivo: provisionar via Terraform as 3 instâncias RDS PostgreSQL, o ElastiCache Redis, a tabela
DynamoDB `ToggleMasterAnalytics` e a fila SQS, e resolver o problema de "credenciais em arquivos de
texto": as senhas são geradas pelo Terraform e guardadas no AWS Secrets Manager.

## O que foi feito

### 1. Módulos novos em `terraform/modules/`

| Módulo | Recurso | Configuração | Por quê |
|---|---|---|---|
| `rds` | `aws_db_instance` | PostgreSQL 17, `db.t3.micro`, 20 GB gp3 criptografado, privado, sem Multi-AZ, sem backup/snapshot final | Um banco por serviço (auth, flag, targeting). Sem backup para criar/destruir rápido no lab; em produção: retenção ≥ 7 dias, `deletion_protection`, Multi-AZ |
| `elasticache` | `aws_elasticache_replication_group` + subnet group | Redis 7.1, 1 nó `cache.t3.micro`, criptografia em repouso e **em trânsito (TLS)** | Cache do evaluation-service; replication group é o recurso que permite TLS |
| `dynamodb` | `aws_dynamodb_table` | `ToggleMasterAnalytics`, chave `event_id` (S), `PAY_PER_REQUEST`, SSE | Mesmo schema usado pelo analytics-service; paga só pelo uso |
| `sqs` | `aws_sqs_queue` | `togglemaster-events`, long polling 20s, SSE gerenciado | evaluation-service publica, analytics-service consome |
| `secrets` | `aws_secretsmanager_secret` + version | JSON chave/valor; `recovery_window_in_days = 0`; opção `ignore_value_changes` | Um secret por serviço; cada chave vira variável de ambiente no pod via ESO |

### 2. Camada `terraform/infra` (arquivos novos)

| Arquivo | Conteúdo |
|---|---|
| `security.tf` | Security groups `togglemaster-rds` (5432) e `togglemaster-redis` (6379), liberados **apenas** para o security group do cluster EKS |
| `databases.tf` | DB subnet group (subnets privadas), `random_password` por banco, `module.rds` com `for_each`, `module.redis`, `module.dynamodb` |
| `messaging.tf` | `module.sqs` |
| `secrets.tf` | Montagem dos valores e os 5 secrets |

As 3 instâncias RDS vêm de uma única variável, então adicionar um banco é adicionar uma linha:

```hcl
variable "databases" {
  default = {
    auth      = { db_name = "auth_db",      username = "auth_user" }
    flag      = { db_name = "flagapi",      username = "flagapi_user" }
    targeting = { db_name = "targeting_db", username = "targeting_user" }
  }
}
```

### 3. Segredos

| Secret | Chaves | Origem dos valores |
|---|---|---|
| `togglemaster/auth-service` | `DATABASE_URL`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASS`, `MASTER_KEY` | Outputs do RDS + `random_password` |
| `togglemaster/flag-service` | `DATABASE_URL`, `DB_*` | idem |
| `togglemaster/targeting-service` | `DATABASE_URL`, `DB_*` | idem |
| `togglemaster/evaluation-service` | `REDIS_URL` (`rediss://...:6379`) | Output do ElastiCache |
| `togglemaster/evaluation-service-api-key` | `SERVICE_API_KEY` | Valor provisório `PENDENTE` (ver abaixo) |

Decisões:

- **Senhas geradas por `random_password`** (32 caracteres, sem especiais para não exigir escape na
  `DATABASE_URL` no formato `host=... password=...`). Ninguém digita nem vê a senha.
- **Mesmos nomes de variáveis** que os serviços e seus `entrypoint.sh` já usam → nenhum código de
  aplicação precisou mudar.
- **`SERVICE_API_KEY`**: é emitida pelo auth-service em runtime (`POST /admin/keys`), então o
  Terraform não tem como conhecê-la. Ele cria o secret com valor provisório e `ignore_changes`;
  o valor real será gravado por script na Etapa 6 e não é sobrescrito em applies futuros.
- **analytics-service não tem secret**: só usa SQS/DynamoDB, com as credenciais da role do nó (Etapa 3).
  URL da fila e nome da tabela não são segredo e irão em ConfigMap (Etapa 6).
- O `JWT_SECRET` que existia no Secret da Fase 2 foi removido: nenhum serviço o lê.
- **Ressalva:** as senhas ficam também no state do Terraform. Por isso o bucket de state é privado,
  criptografado e versionado (Etapa 1).

### 4. Script `scripts/test-data-connectivity.sh`

Sobe pods temporários no cluster e valida, de dentro da rede, o acesso a cada recurso
(sem imprimir senhas): `psql` nos 3 RDS com as credenciais lidas do Secrets Manager, `redis-cli --tls`
no Redis, e envio/recebimento no SQS + gravação/leitura no DynamoDB usando a identidade do pod.

## Como testar

```bash
cd terraform/infra
terraform plan -detailed-exitcode; echo $?      # 0 = sem mudanças
terraform output

# RDS: 3 instâncias available, PostgreSQL 17, privadas e criptografadas
aws rds describe-db-instances \
  --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceStatus,EngineVersion,PubliclyAccessible,StorageEncrypted]' --output table

# Redis: available, TLS e criptografia em repouso
aws elasticache describe-replication-groups \
  --query 'ReplicationGroups[].[ReplicationGroupId,Status,TransitEncryptionEnabled,AtRestEncryptionEnabled]' --output table

# DynamoDB e SQS
aws dynamodb describe-table --table-name ToggleMasterAnalytics --query 'Table.[TableStatus,KeySchema]'
aws sqs list-queues

# Secrets: nomes e chaves (sem mostrar valores)
aws secretsmanager list-secrets --query 'SecretList[].Name'
aws secretsmanager get-secret-value --secret-id togglemaster/auth-service --query SecretString --output text \
  | python3 -c 'import sys,json; print(list(json.load(sys.stdin)))'

# Conectividade a partir do cluster (o teste mais importante)
cd ../.. && ./scripts/test-data-connectivity.sh
```

## Resultado da validação (2026-10-03)

| Verificação | Resultado |
|---|---|
| `terraform apply` | ✅ 26 recursos criados |
| `plan -detailed-exitcode` | ✅ exit 0 |
| RDS | ✅ `togglemaster-auth`, `-flag`, `-targeting`: `available`, PostgreSQL 17.9, privadas, criptografadas |
| Redis | ✅ `togglemaster-redis` `available`, TLS + at-rest |
| DynamoDB | ✅ `ToggleMasterAnalytics` `ACTIVE`, chave `event_id`, on-demand |
| SQS | ✅ `togglemaster-events` |
| Secrets Manager | ✅ 5 secrets com as chaves esperadas |
| Pod → RDS (×3) | ✅ conecta com usuário/banco corretos, `ssl=true` |
| Pod → Redis | ✅ `PONG` via TLS |
| Pod → SQS / DynamoDB | ✅ envia/recebe/apaga mensagem; grava/lê/apaga item, como `assumed-role/LabRole` |

## Custos desta etapa

3 × RDS `db.t3.micro` (~US$ 0,054/h no total + 60 GB gp3) e Redis `cache.t3.micro` (~US$ 0,017/h).
DynamoDB e SQS: por uso (praticamente zero). Secrets Manager: US$ 0,40/secret/mês.
