# ToggleMaster — PosTech DevOps, Tech Challenge Fase 3

Infraestrutura como código, pipelines DevSecOps e GitOps para os 5 microsserviços do ToggleMaster
(plataforma de *feature flags*): `auth`, `flag`, `targeting`, `evaluation` e `analytics`.

> "Se não está no código, não existe."

## O que este repositório entrega

| Requisito do desafio | Onde está |
|---|---|
| **IaC (Terraform)**: VPC, EKS, 3 RDS, ElastiCache, DynamoDB, SQS, 5 ECR; state remoto em S3 com `use_lockfile` | [`terraform/`](terraform/) |
| **CI & DevSecOps**: build, testes, lint, SCA, SAST, scan de imagem, push no ECR; bloqueio em vulnerabilidade crítica | [`.github/workflows/`](.github/workflows/) |
| **GitOps**: manifestos Kubernetes separados, ArgoCD com sync automático, CI atualizando a tag da imagem | [`gitops/`](gitops/), [`terraform/platform/`](terraform/platform/) |
| Documentação passo a passo de cada etapa | [`docs/`](docs/) |

## Arquitetura

```
                 Desenvolvedor
                      │ Pull Request / merge na main
                      ▼
        ┌──────────── GitHub ────────────┐
        │  código dos serviços           │
        │  .github/workflows (CI)        │──► Build & Test ─► Lint ─► Security (Trivy, gosec/bandit)
        │  gitops/apps/<serviço>/ ◄──────┼─── commit da nova tag ◄── Docker build + Trivy image ─► ECR
        └───────────────┬────────────────┘
                        │ ArgoCD monitora gitops/ (ApplicationSet)
                        ▼
  ┌──────────────────────── AWS (Terraform) ────────────────────────┐
  │  VPC: 2 subnets públicas (ALB, NAT) + 2 privadas                │
  │                                                                 │
  │  Internet ─► ALB ─► EKS (3 nós, subnets privadas)               │
  │                      ├─ auth-service ───────► RDS PostgreSQL    │
  │                      ├─ flag-service ───────► RDS PostgreSQL    │
  │                      ├─ targeting-service ──► RDS PostgreSQL    │
  │                      ├─ evaluation-service ─► ElastiCache Redis │
  │                      │                    └─► SQS ─┐            │
  │                      └─ analytics-service ◄────────┘─► DynamoDB │
  │                                                                 │
  │  Plataforma no cluster: ArgoCD · External Secrets · ALB Controller │
  │  Secrets Manager ─► External Secrets ─► Secret do Kubernetes    │
  └─────────────────────────────────────────────────────────────────┘
```

## Estrutura

```
.
├── auth-service/  evaluation-service/                    # Go
├── flag-service/  targeting-service/  analytics-service/ # Python (Flask)
├── terraform/
│   ├── bootstrap/     # bootstrap.sh: bucket S3 do state
│   ├── modules/       # network, eks, rds, elasticache, dynamodb, sqs, ecr, secrets
│   ├── infra/         # camada 1: rede, cluster, dados, mensageria, repositórios, segredos
│   └── platform/      # camada 2: ALB Controller, External Secrets, ArgoCD (Helm)
├── gitops/apps/<serviço>/   # manifestos Kustomize; a tag da imagem fica em kustomization.yaml
├── .github/workflows/       # _ci-go.yml, _ci-python.yml, <serviço>.yml, sonarcloud.yml
├── scripts/                 # subir/derrubar ambiente, bootstrap e testes
└── docs/                    # plano, passo a passo por etapa, roteiro da demo, relatório
```

## Pipeline de cada microsserviço

```
Build & Unit Test ─┐
                   ├─► Security Scan ─► Docker Build, Scan & Push ─► GitOps (tag)
Lint ──────────────┘
```

| Estágio | Go | Python |
|---|---|---|
| Build & Unit Test | `go build`, `go test` | `pytest` |
| Lint | `golangci-lint` | `flake8` |
| SCA | Trivy `fs` | Trivy `fs` |
| SAST | `gosec` + SonarCloud | `bandit` + SonarCloud |
| Container scan | Trivy `image` | Trivy `image` |
| Publicação | ECR, tag `v1.0.0-<sha7>` | idem |
| GitOps | commit da tag em `gitops/apps/<serviço>/kustomization.yaml` | idem |

**Regra de bloqueio:** vulnerabilidade CRITICAL (Trivy) ou de severidade HIGH (gosec/bandit)
interrompe o pipeline; a imagem não é publicada. O pipeline roda em todo Pull Request e em push na
`main`; a publicação e o GitOps só acontecem na `main`.

## Como subir o ambiente

Pré-requisitos: `terraform` ≥ 1.10, `aws`, `kubectl`, `helm`, `gh`, credenciais do AWS Academy em
`~/.aws/credentials` (detalhes em [docs/ETAPA-0.md](docs/ETAPA-0.md)).

```bash
./scripts/infra-up.sh                      # bucket de state + terraform/infra + terraform/platform (~20 min)
./scripts/sync-gh-secrets.sh               # credenciais do Academy para o GitHub Actions
for s in auth flag targeting evaluation analytics; do gh workflow run $s-service.yml; done
                                           # CI publica as imagens e atualiza gitops/; ArgoCD faz o deploy
./scripts/bootstrap-service-api-key.sh     # emite a chave de serviço do evaluation-service
./scripts/test-services.sh                 # teste ponta a ponta pelo ALB
```

ArgoCD (UI):

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 8080:80     # http://localhost:8080 — usuário admin
```

Derrubar tudo (o bucket de state é preservado):

```bash
./scripts/infra-down.sh
```

Desenvolvimento local, sem AWS: `docker compose up --build`.

## Decisões principais

| Tema | Decisão |
|---|---|
| Conta AWS | AWS Academy: nenhum recurso de IAM é criado; EKS e nós usam a `LabRole` via data source |
| State | S3 com `use_lockfile`; um state por camada (`infra`, `platform`) |
| Acesso AWS dos pods | Role do nó via IMDS (Academy não permite IRSA/Pod Identity): sem credenciais estáticas no cluster |
| Segredos | Senhas geradas pelo Terraform → Secrets Manager → External Secrets Operator. Nada sensível no Git |
| GitOps | Pasta `gitops/` no monorepo, Kustomize, ArgoCD `ApplicationSet` (uma Application por pasta) com auto-sync, prune e self-heal |
| Entrada | Um único ALB para os 5 serviços, com roteamento e reescrita por caminho |

O raciocínio completo, os problemas encontrados e como testar cada parte estão em:

| Documento | Conteúdo |
|---|---|
| [docs/PLANO.md](docs/PLANO.md) | Plano, decisões de arquitetura e status das etapas |
| [docs/ETAPA-0.md](docs/ETAPA-0.md) | Pré-requisitos |
| [docs/ETAPA-1.md](docs/ETAPA-1.md) | Backend remoto do Terraform (e recuperação de lock) |
| [docs/ETAPA-2.md](docs/ETAPA-2.md) | Rede e ECR; scripts de subir/derrubar |
| [docs/ETAPA-3.md](docs/ETAPA-3.md) | EKS com LabRole |
| [docs/ETAPA-4.md](docs/ETAPA-4.md) | RDS, Redis, DynamoDB, SQS e segredos |
| [docs/ETAPA-5.md](docs/ETAPA-5.md) | ALB Controller, External Secrets e ArgoCD |
| [docs/ETAPA-6.md](docs/ETAPA-6.md) | Manifestos GitOps e ApplicationSet |
| [docs/ETAPA-7.md](docs/ETAPA-7.md) | Pipelines de CI DevSecOps |
| [docs/ETAPA-8.md](docs/ETAPA-8.md) | CI atualizando a tag no GitOps |
| [docs/TERRAFORM-GUIA.md](docs/TERRAFORM-GUIA.md) | Guia didático de Terraform a partir deste projeto, com laboratório prático em [docs/terraform-lab/](docs/terraform-lab/README.md) |
| [docs/ROTEIRO-DEMO.md](docs/ROTEIRO-DEMO.md) | Roteiro do vídeo de demonstração |
| [docs/CUSTOS.md](docs/CUSTOS.md) | Estimativa de custos |
| [docs/RELATORIO.md](docs/RELATORIO.md) | Relatório de entrega |
