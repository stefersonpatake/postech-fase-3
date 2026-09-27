# Etapa 0 — Pré-requisitos

Objetivo: preparar máquina local, contas e estrutura do repositório para as etapas seguintes.

## O que foi feito

### 1. Ferramentas instaladas (Homebrew)

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform gh trivy argocd
```

| Ferramenta | Versão | Uso |
|---|---|---|
| terraform | 1.16.4 | IaC (backend S3 com `use_lockfile` exige ≥ 1.10) |
| gh | 2.101.0 | Gerenciar GitHub Secrets/Actions pela CLI |
| trivy | 0.74.0 | Testar localmente os scans SCA e de imagem |
| argocd | 3.5.3 | CLI do ArgoCD (login, listar apps, sync) |
| kubectl / helm / aws | já existentes | Cluster, charts e AWS |

> `kustomize` não precisa ser instalado: está embutido no `kubectl` (`kubectl kustomize` / `kubectl apply -k`).

### 2. Estrutura de pastas

```
terraform/{bootstrap,infra,platform,modules}/
gitops/{argocd,apps}/
.github/workflows/
scripts/
docs/
```

Pastas vazias contêm `.gitkeep` para serem versionadas.

### 3. `.gitignore` para Terraform

Adicionados `.terraform/`, `*.tfstate*`, `*.tfvars` (exceto `*.tfvars.example`), `*.tfplan` e `crash.log`.
O `.terraform.lock.hcl` **deve** ser versionado (fixa versões dos providers).

### 4. Script `scripts/sync-gh-secrets.sh`

Como o Academy não permite OIDC entre GitHub e AWS, o CI usa as credenciais temporárias
do Lab como GitHub Secrets. O script:

1. Valida o perfil local com `aws sts get-caller-identity`.
2. Grava os secrets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`.
3. Grava as variables `AWS_REGION` e `AWS_ACCOUNT_ID`.

Rodar **a cada nova sessão do Learner Lab**.

## Ações manuais (fora do código)

- [x] **Renovar credenciais do Academy**: Learner Lab → *Start Lab* → *AWS Details* → copiar para `~/.aws/credentials`.
- [x] **Login no GitHub CLI**: `gh auth login` (GitHub.com → HTTPS → navegador).
- [x] **SonarCloud** (org `stefersonpatake`, projeto `postech-fase-3`):
  1. Entrar em https://sonarcloud.io com a conta GitHub.
  2. *Import an organization* → escolher `stefersonpatake` → plano Free.
  3. *Analyze new project* → `postech-fase-3`.
  4. *Administration → Analysis Method* → **desligar Automatic Analysis** (a análise será feita pelo GitHub Actions).
  5. Acessar https://sonarcloud.io/account/security (no layout novo do SonarQube Cloud
     não há avatar na barra superior; use o link direto) → gerar token e salvar como secret:
     `gh secret set SONAR_TOKEN --repo stefersonpatake/postech-fase-3`
  6. Anotar a **organization key** e a **project key** (usadas na Etapa 7).
- [x] **Remover recursos manuais da Fase 2** — não necessário: a conta do Lab atual (`583383233548`) é nova e está vazia (sem EKS, RDS, ECR ou buckets).

## Como testar

```bash
# Ferramentas
terraform version
gh --version && trivy --version && argocd version --client

# Credenciais AWS válidas (deve mostrar Account e Arn com voclabs)
aws sts get-caller-identity

# LabRole existe (será usada pelo EKS)
aws iam get-role --role-name LabRole --query Role.Arn

# Secrets Manager está liberado no Academy (lista vazia ou existente = OK; AccessDenied = problema)
aws secretsmanager list-secrets --max-results 1

# GitHub CLI autenticado
gh auth status

# Sync de credenciais para o GitHub
./scripts/sync-gh-secrets.sh
gh secret list --repo stefersonpatake/postech-fase-3
# Esperado: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN (e SONAR_TOKEN)
```

## Resultado da validação (2026-09-27)

| Verificação | Resultado |
|---|---|
| `aws sts get-caller-identity` | ✅ `assumed-role/voclabs`, conta `583383233548` |
| LabRole | ✅ `arn:aws:iam::583383233548:role/LabRole` |
| Secrets Manager | ✅ criar e excluir secret de teste (`tm-etapa0-test`) funcionou |
| `gh auth status` | ✅ logado como `stefersonpatake` |
| `sync-gh-secrets.sh` | ✅ 3 secrets AWS + variables `AWS_REGION`, `AWS_ACCOUNT_ID` |
| `SONAR_TOKEN` | ✅ secret criado |

## Critério de conclusão

Todos os comandos acima executam sem erro e os 4 secrets aparecem no repositório.
