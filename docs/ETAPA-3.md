# Etapa 3 — Cluster EKS e Node Group

Objetivo: provisionar via Terraform o cluster Kubernetes (EKS) e seus nós, usando a **LabRole**
existente do AWS Academy (sem criar nenhum recurso de IAM).

## O que foi feito

### 1. Módulo `terraform/modules/eks`

| Recurso | Configuração | Por quê |
|---|---|---|
| `aws_eks_cluster` | Kubernetes **1.36**, `role_arn = LabRole` | Academy: role do control plane não pode ser criada |
| | Endpoint público **e** privado | `kubectl`/Terraform de fora; nós falam com a API por dentro da VPC |
| | `authentication_mode = API_AND_CONFIG_MAP` + `bootstrap_cluster_creator_admin_permissions = true` | Acesso via *access entries*; quem cria o cluster (role `voclabs`) vira cluster-admin, sem editar `aws-auth` na mão |
| `aws_launch_template` | IMDSv2 obrigatório, **hop limit = 2** | Permite que os pods usem as credenciais da role do nó (ver decisão abaixo) |
| `aws_eks_node_group` | 3 × `t3.medium` (min 2, máx 4), AL2023, On-Demand, subnets **privadas**, `node_role_arn = LabRole` | Capacidade para ArgoCD + ESO + ALB Controller + 5 serviços (17 pods por `t3.medium`) |
| `aws_eks_addon` | `vpc-cni`, `kube-proxy` (antes dos nós) e `coredns` (depois dos nós) | Addons gerenciados pela AWS; a ordem evita nós `NotReady` e CoreDNS preso em `DEGRADED` |

A LabRole entra no módulo por variável, vinda do data source da camada `infra`:

```hcl
# terraform/infra/data.tf
data "aws_iam_role" "lab" { name = "LabRole" }

# terraform/infra/eks.tf
module "eks" {
  source           = "../modules/eks"
  cluster_role_arn = data.aws_iam_role.lab.arn
  node_role_arn    = data.aws_iam_role.lab.arn
  subnet_ids       = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  node_subnet_ids  = module.network.private_subnet_ids
  ...
}
```

Novos outputs da camada: `cluster_name`, `cluster_endpoint`, `cluster_security_group_id`
(usado na Etapa 4 para liberar RDS/Redis aos nós) e `kubeconfig_command`.

### 2. Decisão: credenciais AWS dos pods via role do nó (IMDS)

Na Fase 2 os pods recebiam credenciais do Academy por Secret, renovadas por um CronJob
(`credentials-refresher`), pois as credenciais do Lab expiram a cada sessão.

Verificações feitas nesta etapa:

- A trust policy da LabRole **não** inclui `pods.eks.amazonaws.com` → EKS Pod Identity não é possível.
- Criar OIDC provider/roles (IRSA) é IAM → proibido no Academy.
- A LabRole confia em `ec2.amazonaws.com` → os nós a assumem pelo instance profile.

Com `http_put_response_hop_limit = 2` no launch template, os pods alcançam o IMDS do nó e recebem
credenciais temporárias da LabRole, **renovadas automaticamente pela AWS**. Consequências:

- ESO, AWS Load Balancer Controller e os serviços que usam SQS/DynamoDB não precisam de credencial estática.
- O CronJob `credentials-refresher` e o `refresh-academy-credentials.sh` da Fase 2 deixam de ser necessários.
- Limitação conhecida: todos os pods compartilham a mesma role (sem menor privilégio por serviço).
  Em conta pessoal a solução correta seria IRSA ou Pod Identity com uma role por serviço.

### 3. Incidente durante o apply (e como foi resolvido)

O primeiro `terraform apply` foi interrompido por um limite de tempo da ferramenta de execução
enquanto o cluster ainda estava `CREATING`. Resultado: cluster existindo na AWS, mas fora do state.

Recuperação, sem recriar nada:

```bash
aws eks wait cluster-active --name togglemaster-eks
terraform import module.eks.aws_eks_cluster.this togglemaster-eks
terraform plan     # 4 to add (addons + node group), 0 to change no cluster
terraform apply
```

Lição: applies longos (EKS ~10 min, RDS na Etapa 4) devem rodar até o fim em um terminal próprio
ou com `nohup`; se interrompidos, `terraform import` reconcilia o state.

## Como testar

```bash
cd terraform/infra
terraform plan -detailed-exitcode; echo $?      # 0 = sem mudanças

# kubeconfig
$(terraform output -raw kubeconfig_command)

# 3 nós Ready, versão v1.36.x, IPs das subnets privadas (10.0.128.0/20, 10.0.144.0/20)
kubectl get nodes -o wide

# Addons: aws-node (vpc-cni), kube-proxy e coredns Running
kubectl get pods -n kube-system
aws eks list-addons --cluster-name togglemaster-eks

# Cluster e node group usando a LabRole
aws eks describe-cluster --name togglemaster-eks --query 'cluster.[status,version,roleArn]'
aws eks describe-nodegroup --cluster-name togglemaster-eks --nodegroup-name default \
  --query 'nodegroup.[status,nodeRole,instanceTypes,scalingConfig]'

# Access entries (voclabs = admin, LabRole = nós)
aws eks list-access-entries --cluster-name togglemaster-eks

# Pods herdam a LabRole pelo IMDS (sem credenciais configuradas)
kubectl run imds-test --image=public.ecr.aws/aws-cli/aws-cli:latest --restart=Never \
  --command -- aws sts get-caller-identity --query Arn --output text
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/imds-test --timeout=120s
kubectl logs imds-test      # arn:aws:sts::<conta>:assumed-role/LabRole/i-...
kubectl delete pod imds-test
```

## Resultado da validação (2026-10-03)

| Verificação | Resultado |
|---|---|
| `terraform apply` | ✅ 6 recursos (cluster importado após a interrupção + 5 criados) |
| `plan -detailed-exitcode` | ✅ exit 0 |
| Cluster | ✅ `ACTIVE`, v1.36, `API_AND_CONFIG_MAP` |
| Nós | ✅ 3 `Ready` (`10.0.140.238`, `10.0.144.46`, `10.0.150.177`) em subnets privadas |
| Addons | ✅ `aws-node` 3/3, `kube-proxy` 3/3, `coredns` 2/2 Running |
| Access entries | ✅ `voclabs`, `LabRole`, service role do EKS |
| Pod → IMDS | ✅ `arn:aws:sts::583383233548:assumed-role/LabRole/i-03a189f089642f401` |

## Custos desta etapa

Control plane EKS (~US$ 0,10/h) + 3 × `t3.medium` (~US$ 0,125/h no total) + volumes EBS dos nós.
Derrubar ao fim da sessão com `./scripts/infra-down.sh`.
