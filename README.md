# ToggleMaster — PosTech DevOps, Tech Challenge Fase 3

A DevOps Solutions Inc., aprovou a arquitetura de microsserviços da fase 2.

### Relatos
- Desenvolvedores rodando `kubectl apply` em suas máquinas locais, gerando conflitos de versão;
- Credenciais em arquivos de texto sem segurança;
- Vulnerabilidades de bibliotecas em produção;
- Ambiente de homologação levou dias para ser recriado à mão na AWS.

### O que este desafio entrega

| Requisito | Onde está |
|---|---|
| **IaC (Terraform)**: VPC, EKS, 3 RDS, ElastiCache, DynamoDB, SQS, 5 ECR; 2 buckets S3 com `use_lockfile=true` e criptografados | [`terraform/`](terraform/) |
| **CI & DevSecOps (GitHub)**: build, testes, lint, SCA, SAST, scan de imagem, push no ECR; bloqueio em vulnerabilidade crítica | [`.github/workflows/`](.github/workflows/) |
| **GitOps**: manifestos Kubernetes separados, ArgoCD com sync automático, CI atualizando a tag da imagem | [`gitops/`](gitops/), [`terraform/platform/`](terraform/platform/) |

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
  ┌──────────────────────── AWS (Terraform) ───────────────────────────┐
  │  VPC: 2 subnets públicas (ALB, NAT) + 2 privadas                   │
  │                                                                    │
  │  Internet ─► ALB ─► EKS (3 nós, subnets privadas)                  │
  │                      ├─ auth-service ───────► RDS PostgreSQL       │
  │                      ├─ flag-service ───────► RDS PostgreSQL       │
  │                      ├─ targeting-service ──► RDS PostgreSQL       │
  │                      ├─ evaluation-service ─► ElastiCache Redis    │
  │                      │                    └─► SQS ─┐               │
  │                      └─ analytics-service ◄────────┘─► DynamoDB    │
  │                                                                    │
  │  Plataforma no cluster: ArgoCD · External Secrets · ALB Controller │
  │  Secrets Manager ─► External Secrets ─► Secret do Kubernetes       │
  └────────────────────────────────────────────────────────────────────┘
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



## Estrutura

```
Fase3/
├── auth-service/  evaluation-service/                    # Go
├── flag-service/  targeting-service/  analytics-service/ # Python (Flask)
├── terraform/
│   ├── bootstrap/     # bootstrap.sh: bucket S3 do state
│   ├── modules/       # network, eks, rds, elasticache, dynamodb, sqs, ecr, secrets
│   ├── infra/         # camada 1: rede, cluster, dados, mensageria, repositórios, segredos
│   └── platform/      # camada 2: ALB Controller, External Secrets, ArgoCD (Helm)
├── gitops/apps/<serviço>/   # manifestos Kustomize; a tag da imagem fica em kustomization.yaml
├── .github/workflows/       # _ci-go.yml, _ci-python.yml, <serviço>.yml, sonarcloud.yml
└── scripts/                 # subir/derrubar ambiente, bootstrap e testes
```


## Como subir o ambiente

Pré-requisitos: 
* `terraform` ≥ 1.10
* `aws`
* `kubectl`
* `helm`
* `gh`
* Credenciais do AWS Academy em `~/.aws/credentials`.

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
