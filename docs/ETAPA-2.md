# Etapa 2 — Rede (VPC) e repositórios ECR

Objetivo: provisionar via Terraform a rede base (VPC, subnets públicas e privadas, Internet Gateway,
NAT, route tables) e os 5 repositórios ECR dos microsserviços.

## O que foi feito

### 1. Módulo `terraform/modules/network`

| Recurso | Configuração | Por quê |
|---|---|---|
| `aws_vpc` | `10.0.0.0/16`, DNS support + hostnames | EKS e RDS exigem resolução DNS interna |
| `aws_subnet.public` ×2 | `10.0.0.0/20`, `10.0.16.0/20` (us-east-1a/b), IP público automático | ALB internet-facing e NAT |
| `aws_subnet.private` ×2 | `10.0.128.0/20`, `10.0.144.0/20` | Nós do EKS, RDS e Redis sem exposição direta |
| `aws_internet_gateway` | — | Saída/entrada das subnets públicas |
| `aws_eip` + `aws_nat_gateway` | **1 NAT** na subnet pública da 1a | Saída das subnets privadas (pull de imagens, APIs AWS). Um único NAT reduz custo (~US$ 32/mês); em produção seria 1 por AZ |
| `aws_route_table.public` | `0.0.0.0/0 → IGW` | |
| `aws_route_table.private` | `0.0.0.0/0 → NAT` | |

Tags de descoberta de subnet para o **AWS Load Balancer Controller** (Etapa 5):

- públicas: `kubernetes.io/role/elb = 1`
- privadas: `kubernetes.io/role/internal-elb = 1`
- ambas: `kubernetes.io/cluster/togglemaster-eks = shared`

AZs `us-east-1a` e `us-east-1b` (a `us-east-1e` não é suportada pelo EKS). As subnets usam
`cidrsubnet(var.cidr_block, 4, n)`, então adicionar AZs é só aumentar a lista `azs`.

### 2. Módulo `terraform/modules/ecr`

| Configuração | Por quê |
|---|---|
| `togglemaster/<serviço>` via `for_each` | Um repositório por microsserviço |
| `image_tag_mutability = IMMUTABLE` | A tag `v1.0.0-<sha>` nunca é sobrescrita: o que o GitOps implanta é exatamente o que o CI escaneou |
| `scan_on_push = true` | Scan básico do ECR como camada extra ao Trivy |
| Lifecycle policy (15 imagens) | Controla custo de armazenamento |
| `force_delete = true` | `terraform destroy` funciona com imagens no repositório |

### 3. Camada `terraform/infra`

```
infra/
├── backend.tf     # (Etapa 1)
├── versions.tf    # (Etapa 1)
├── data.tf        # LabRole, caller identity
├── variables.tf   # + vpc_cidr, azs, services
├── locals.tf      # cluster_name = togglemaster-eks
├── network.tf     # module "network"
├── ecr.tf         # module "ecr"
└── outputs.tf     # + vpc_id, subnet ids, ecr_registry, ecr_repository_urls
```

Execução: `terraform plan` → **24 to add** → `terraform apply` → **24 added**.

## Como testar

```bash
cd terraform/infra
terraform init
terraform plan            # após o apply: "No changes"
terraform apply
terraform output

# Idempotência (0 = sem mudanças; também garante que nenhum SCP quebra o refresh)
terraform plan -detailed-exitcode; echo $?

VPC=$(terraform output -raw vpc_id)

# Subnets: 2 públicas (MapPublicIp=True) e 2 privadas, em 2 AZs
aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC \
  --query 'Subnets[].[Tags[?Key==`Name`]|[0].Value,CidrBlock,AvailabilityZone,MapPublicIpOnLaunch]' --output table

# Rotas: pública → igw-..., privada → nat-...
aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VPC \
  --query 'RouteTables[].[Tags[?Key==`Name`]|[0].Value,Routes[].[DestinationCidrBlock,GatewayId||NatGatewayId]]' --output json

# NAT disponível
aws ec2 describe-nat-gateways --filter Name=vpc-id,Values=$VPC --query 'NatGateways[].State'

# ECR: 5 repositórios IMMUTABLE com scan on push
aws ecr describe-repositories \
  --query 'repositories[].[repositoryName,imageTagMutability,imageScanningConfiguration.scanOnPush]' --output table

# Login no registry
aws ecr get-login-password | docker login --username AWS --password-stdin $(terraform output -raw ecr_registry)
```

## Resultado da validação (2026-09-27)

| Verificação | Resultado |
|---|---|
| `terraform apply` | ✅ 24 recursos criados |
| `plan -detailed-exitcode` pós-apply | ✅ exit 0 (sem drift, sem bloqueio de SCP) |
| Subnets | ✅ 2 públicas (`10.0.0.0/20`, `10.0.16.0/20`) + 2 privadas (`10.0.128.0/20`, `10.0.144.0/20`) em 1a/1b |
| Rotas | ✅ `togglemaster-public-rt → igw`, `togglemaster-private-rt → nat` (a tabela sem nome é a main route table padrão da VPC, sem associações) |
| NAT | ✅ `available` |
| ECR | ✅ 5 repositórios `togglemaster/*`, `IMMUTABLE`, scan on push |
| `docker login` no ECR | ✅ `Login Succeeded` |

## Custos desta etapa

Recurso cobrado por hora: **NAT Gateway** (~US$ 0,045/h + dados) e o **EIP** associado. ECR cobra
apenas por armazenamento. Para pausar custos: `terraform destroy` (a rede é recriada em ~3 min).
