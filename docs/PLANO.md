# Plano de Execução — Tech Challenge Fase 3

Objetivo: automatizar toda a infraestrutura e o ciclo de vida dos 5 microsserviços do
ToggleMaster (auth, flag, targeting, evaluation, analytics) com IaC, CI/CD, DevSecOps e GitOps.

> "Se não está no código, não existe."

## Decisões de arquitetura

| Tema | Decisão | Motivo |
|---|---|---|
| Conta AWS | AWS Academy (Opção A) | Terraform **não cria IAM**; usa a `LabRole` via `data "aws_iam_role"` |
| Estado Terraform | Backend S3 com `use_lockfile = true`; bucket criado por `terraform/bootstrap/bootstrap.sh` (AWS CLI) | Requisito do desafio; lock nativo sem DynamoDB. SCP do Academy impede gerenciar `aws_s3_bucket` via Terraform (ver ETAPA-1) |
| Camadas Terraform | `bootstrap/` → `infra/` → `platform/` | States separados: o provider helm/kubernetes depende do cluster já existir |
| Módulos | Módulos próprios (`network`, `eks`, `rds`, `elasticache`, `dynamodb`, `sqs`, `ecr`, `secrets`) | Módulos da comunidade criam IAM por padrão e falham no Academy |
| Segredos | `random_password` → AWS Secrets Manager → External Secrets Operator (ESO) | Nenhuma credencial em arquivo/git |
| Acesso AWS dos pods (ESO, ALB Controller, serviços) | Role do nó (LabRole) via IMDS, hop limit 2 no launch template | Academy não permite IRSA nem Pod Identity; as credenciais do nó se renovam sozinhas, eliminando o CronJob `credentials-refresher` da Fase 2 (ver ETAPA-3) |
| GitOps | Pasta `gitops/` no monorepo, Kustomize, ArgoCD `ApplicationSet` (uma Application por pasta em `gitops/apps/`) | Menos credenciais; CI commita com `GITHUB_TOKEN` |
| Instalação ArgoCD/ESO/ALB | Terraform + provider helm (`terraform/platform`), versões de chart fixadas; ArgoCD acessado por port-forward | Tudo como código |
| CI | Workflows reutilizáveis (Go e Python) + 5 callers com filtro de `paths` | Sem duplicação; cada serviço roda isolado |
| SAST | gosec (Go) / bandit (Python) bloqueando em severidade HIGH + SonarCloud em workflow próprio (repositório inteiro) | Bloqueio controlado no pipeline; painel e quality gate para a demo |
| SCA / Container | Trivy `fs` e Trivy `image`, `--severity CRITICAL --exit-code 1` (imagem com `--ignore-unfixed`) | Regra de bloqueio do desafio |
| Tag de imagem | `v1.0.0-<sha7>` | Formato pedido no desafio |
| Credenciais no CI | GitHub Secrets `AWS_ACCESS_KEY_ID/SECRET/SESSION_TOKEN` | Academy não permite OIDC; atualizados por `scripts/sync-gh-secrets.sh` |
| Ambiente | Novo, do zero (prefixo `togglemaster`) | Demonstra recriação do ambiente em minutos; recursos manuais da Fase 2 serão removidos |

## Estrutura alvo do repositório

```
.
├── auth-service/ flag-service/ targeting-service/ evaluation-service/ analytics-service/
├── terraform/
│   ├── bootstrap/          # bootstrap.sh: bucket S3 do state (AWS CLI)
│   ├── infra/              # VPC, EKS, RDS, Redis, DynamoDB, SQS, ECR, Secrets Manager
│   ├── platform/           # ALB Controller, ESO, ArgoCD + ApplicationSet
│   └── modules/
├── gitops/
│   └── apps/<serviço>/     # manifests + kustomization.yaml (tag da imagem)
├── .github/workflows/      # _ci-go.yml, _ci-python.yml, <serviço>.yml
├── scripts/                # utilitários (sync de credenciais, etc.)
└── docs/                   # este plano + passo a passo de cada etapa
```

## Etapas

Cada etapa tem um documento próprio `docs/ETAPA-N.md` com o que foi feito e como testar.

| # | Etapa | Entregas | Como validar | Status |
|---|---|---|---|---|
| 0 | Pré-requisitos | Ferramentas instaladas, SonarCloud, estrutura de pastas, script de sync de secrets | `terraform version`, `gh auth status`, `aws sts get-caller-identity` | Concluída |
| 1 | Backend remoto | `terraform/bootstrap/bootstrap.sh` cria bucket S3 (versionado, criptografado); backend em `infra/` | `aws s3 ls`; state das demais camadas no S3; teste de lock | Concluída |
| 2 | Rede + ECR | Módulos `network` (VPC, subnets públicas/privadas, IGW, NAT, route tables) e `ecr` (5 repos) | `terraform plan/apply`, `aws ec2 describe-vpcs`, `aws ecr describe-repositories` | Concluída |
| 3 | EKS | Módulo `eks` (cluster + node group com LabRole, access entry, addons) | `kubectl get nodes`; pod de teste com identidade LabRole | Concluída |
| 4 | Dados + mensageria | 3 RDS PostgreSQL, ElastiCache Redis, DynamoDB `ToggleMasterAnalytics`, SQS, secrets no Secrets Manager | `aws rds describe-db-instances`, `scripts/test-data-connectivity.sh` | Concluída |
| 5 | Plataforma | ALB Controller, ESO + `ClusterSecretStore`, ArgoCD | Pods em `argocd` e `external-secrets`; UI do ArgoCD | Concluída |
| 6 | GitOps | `k8s/` → `gitops/apps/*` em Kustomize, `ExternalSecret`, `ApplicationSet` com auto-sync/prune/self-heal, scripts de bootstrap | 5 apps *Synced/Healthy*; `scripts/test-services.sh` | Concluída |
| 7 | CI DevSecOps | Workflows reutilizáveis + 5 por serviço, testes unitários, lint, gosec/bandit, Trivy fs/image, SonarCloud, push ECR | PR com checks verdes; imagem com tag nova no ECR | Concluída |
| 8 | Atualização de tag | Job `gitops` altera `newTag` em `gitops/apps/<serviço>/kustomization.yaml` e commita na `main`; `workflow_dispatch` | Commit do bot → ArgoCD sincroniza → pod com nova tag | Concluída |
| 9 | Demo e entrega | `README.md`, `docs/ROTEIRO-DEMO.md`, `docs/CUSTOS.md`, `docs/RELATORIO.md` | Ensaio do roteiro; gravação do vídeo; print da calculadora | Documentos e print de custos prontos; vídeo pendente |

## Pontos de atenção

- **Credenciais do Academy expiram a cada sessão.** Devem ser renovadas em 2 lugares:
  local (`~/.aws/credentials`) e GitHub Secrets (`scripts/sync-gh-secrets.sh`). O cluster não precisa:
  os pods usam a role do nó.
- **Applies longos** (EKS, RDS): rodar até o fim em terminal próprio; se interrompidos, reconciliar com `terraform import`.
- **Capacidade do cluster:** ArgoCD + ESO + ALB Controller + 5 serviços → 3 nós `t3.medium`.
- **Loop de CI:** o bot só commita em `gitops/`, que não está nos `paths` dos workflows dos serviços.
- **Custos:** derrubar o ambiente ao fim de cada sessão de trabalho com `./scripts/infra-down.sh` (destrói `platform` → `infra`, preserva o bucket de state) e recriar com `./scripts/infra-up.sh`.
