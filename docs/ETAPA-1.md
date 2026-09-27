# Etapa 1 — Backend remoto do Terraform

Objetivo: o `terraform.tfstate` não pode ficar local. Todas as camadas (`infra/`, `platform/`)
usam um bucket S3 como backend, com lock nativo via `use_lockfile`.

## O que foi feito

### 1. Bucket de state — `terraform/bootstrap/bootstrap.sh`

Script idempotente (AWS CLI) que cria/ajusta o bucket `togglemaster-tfstate-<account_id>`:

| Configuração | Por quê |
|---|---|
| Nome com `account_id` | Nomes de bucket são globais; evita colisão entre contas do Lab |
| Versionamento | Recuperar versões anteriores do state em caso de corrupção |
| Criptografia SSE-S3 (AES256) | State contém dados sensíveis (ex.: senhas geradas do RDS) |
| Bloqueio de acesso público | State nunca pode ser público |
| Tags `Project`/`ManagedBy` | Rastreabilidade |

#### Decisão: por que script e não Terraform?

A primeira versão foi feita em Terraform (`aws_s3_bucket` + versioning/encryption/public-access-block).
O `apply` criou o bucket, mas falhou em seguida:

```
Error: reading S3 Bucket (...) object lock configuration: ... AccessDenied:
not authorized to perform: s3:GetBucketObjectLockConfiguration ...
with an explicit deny in a service control policy
```

O **SCP do AWS Academy** nega `s3:GetBucketObjectLockConfiguration`, e o provider AWS lê essa
configuração em todo refresh de `aws_s3_bucket`. Ou seja, **nenhum bucket S3 pode ser gerenciado
pelo Terraform nesta conta**. Como o bucket de state já é, por natureza, um pré-requisito do
Terraform ("ovo e galinha"), ele passou a ser criado pelo script. O recurso foi removido do state
(`terraform state rm`) e o bucket existente foi reaproveitado pelo script.

### 2. Backend S3 na camada `infra/` — `terraform/infra/backend.tf`

```hcl
terraform {
  backend "s3" {
    bucket       = "togglemaster-tfstate-583383233548"
    key          = "infra/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true   # lock via objeto .tflock no próprio S3 (sem DynamoDB)
  }
}
```

Junto foram criados os arquivos base da camada: `versions.tf` (Terraform ≥ 1.10, AWS provider ~> 6.0,
`default_tags`), `variables.tf` (`region`, `project`), `data.tf` (data source da **LabRole** e
`aws_caller_identity`) e `outputs.tf`.

> Se o Lab mudar de conta, atualizar o `bucket` em `backend.tf` com o nome impresso pelo `bootstrap.sh`
> e rodar `terraform init -reconfigure`.

## Como testar

```bash
# 1. Criar/garantir o bucket (pode rodar quantas vezes quiser)
./terraform/bootstrap/bootstrap.sh

# 2. Conferir configurações do bucket
B=togglemaster-tfstate-$(aws sts get-caller-identity --query Account --output text)
aws s3api get-bucket-versioning        --bucket $B   # Status: Enabled
aws s3api get-bucket-encryption        --bucket $B   # AES256
aws s3api get-public-access-block      --bucket $B   # tudo true

# 3. Inicializar a camada infra com backend remoto
cd terraform/infra
terraform init
terraform apply        # 0 recursos; só outputs (account_id, lab_role_arn)

# 4. State está no S3 e NÃO existe localmente
aws s3 ls s3://$B --recursive       # infra/terraform.tfstate
ls terraform.tfstate 2>/dev/null || echo "sem state local ✅"

# 5. Lock: rodar duas operações simultâneas
terraform apply -auto-approve & sleep 2; terraform plan -lock-timeout=0s
# Esperado na segunda: "Error acquiring the state lock" (412 PreconditionFailed no .tflock)
```

## Resultado da validação (2026-09-27)

| Verificação | Resultado |
|---|---|
| `bootstrap.sh` | ✅ bucket `togglemaster-tfstate-583383233548` versionado, criptografado, privado |
| `terraform init` (infra) | ✅ `Successfully configured the backend "s3"` |
| `terraform apply` (infra) | ✅ outputs `account_id` e `lab_role_arn` (LabRole encontrada) |
| State remoto | ✅ `infra/terraform.tfstate` no bucket; nenhum state local |
| Lock | ✅ segunda operação concorrente bloqueada com `Error acquiring the state lock` |

## Lições para as próximas etapas

- Evitar `aws_s3_bucket` em qualquer camada (SCP do Academy).
- Outros recursos com leituras "extras" no refresh podem sofrer o mesmo; validar cada módulo com `plan` + `apply` cedo.
