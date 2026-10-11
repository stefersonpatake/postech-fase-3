# Guia de Terraform — o essencial, a partir deste projeto

Para quem nunca usou Terraform. Explica os conceitos com o código que está em [`terraform/`](../terraform/)
e termina com um laboratório prático que roda só na sua máquina: [`terraform-lab/`](terraform-lab/README.md).

Sugestão de leitura: seções 1 a 3 → laboratório → seções 4 a 8.

## 1. A ideia em uma frase

Você **descreve em arquivos o que deve existir**; o Terraform compara com o que existe e faz
somente o necessário para chegar lá.

| Abordagem manual (Fase 2) | Terraform |
|---|---|
| "Clique em criar VPC, depois criar subnet..." | "Deve existir uma VPC com estas 4 subnets" |
| A ordem dos passos é sua responsabilidade | A ordem é calculada pela ferramenta |
| Rodar duas vezes cria duplicado ou dá erro | Rodar duas vezes não muda nada |
| O que existe está na cabeça de quem criou | O que existe está no código e no state |

Três peças participam de toda execução:

```
   CÓDIGO (.tf)              STATE                    REALIDADE
 "o que eu quero"   "o que eu lembro de ter criado"   "o que existe na AWS"
        │                      │                           │
        └──────────── terraform plan compara ──────────────┘
                               │
                      lista de diferenças
                               │
                        terraform apply
```

## 2. Os quatro comandos

| Comando | O que faz | Altera algo? |
|---|---|---|
| `terraform init` | Baixa providers e módulos; conecta ao backend do state | Não |
| `terraform plan` | Mostra o que seria criado, alterado ou destruído | Não |
| `terraform apply` | Executa o plano (pede confirmação) | **Sim** |
| `terraform destroy` | Destrói tudo o que está no state | **Sim** |

Comandos de apoio: `fmt` (formata), `validate` (checa sintaxe), `output` (mostra saídas),
`state list` (lista o que é gerenciado), `console` (testa expressões).

Como ler a última linha de um plano: `Plan: 3 to add, 1 to change, 0 to destroy`.
Símbolos: `+` criar, `~` alterar, `-` destruir, `-/+` destruir e recriar.

## 3. Vocabulário, com exemplos reais

A linguagem (HCL) tem poucos tipos de bloco. Todos aparecem no projeto.

### provider — o plugin que fala com uma API

```hcl
# terraform/infra/versions.tf
provider "aws" {
  region = var.region
  default_tags { tags = { Project = var.project, ManagedBy = "terraform" } }
}
```

O Terraform em si não sabe nada de AWS. O provider `aws` traduz blocos em chamadas de API.
O projeto usa `aws`, `random` (senhas) e `helm` (instalar charts no cluster).

### resource — algo que o Terraform cria e gerencia

```hcl
# terraform/modules/network/main.tf
resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true
}
```

Formato: `resource "<tipo>" "<nome>"`. O tipo vem do provider; o nome é seu, para referenciar depois:
`aws_vpc.this.id`.

### data — algo que já existe e o Terraform só lê

```hcl
# terraform/infra/data.tf
data "aws_iam_role" "lab" {
  name = "LabRole"
}
```

É assim que o projeto cumpre a regra do Academy: a LabRole não é criada, apenas consultada, e seu
ARN é usado em `data.aws_iam_role.lab.arn`. Um `destroy` nunca apaga o que veio de `data`.

### variable — entrada

```hcl
# terraform/infra/variables.tf
variable "node_desired_size" {
  description = "Quantidade de nós"
  type        = number
  default     = 3
}
```

Uso: `var.node_desired_size`. Para trocar sem editar o código: `terraform apply -var node_desired_size=2`.

### locals — valor calculado

```hcl
# terraform/infra/locals.tf
locals {
  cluster_name = "${var.project}-eks"     # togglemaster-eks
}
```

### output — saída

```hcl
# terraform/infra/outputs.tf
output "cluster_name" {
  value = module.eks.cluster_name
}
```

Aparece ao fim do `apply`, pode ser lido por scripts (`terraform output -raw cluster_name`) e por
outra camada Terraform.

### module — um conjunto de recursos reutilizável

Um módulo é uma pasta com `.tf`. Suas `variable` são os parâmetros; seus `output`, o retorno.

```hcl
# terraform/infra/network.tf  — quem usa
module "network" {
  source       = "../modules/network"
  name         = var.project
  cidr_block   = var.vpc_cidr
  azs          = var.azs
  cluster_name = local.cluster_name
}
```

```hcl
# terraform/infra/eks.tf — outro módulo consome o resultado do primeiro
module "eks" {
  source          = "../modules/eks"
  node_subnet_ids = module.network.private_subnet_ids
  ...
}
```

## 4. Como o projeto está organizado

```
terraform/
├── bootstrap/bootstrap.sh   # cria o bucket do state (fora do Terraform)
├── modules/                 # peças reutilizáveis, sem valores fixos
│   ├── network/   VPC, subnets, IGW, NAT, route tables
│   ├── eks/       cluster, node group, addons
│   ├── rds/       1 instância PostgreSQL
│   ├── elasticache/ dynamodb/ sqs/ ecr/ secrets/
├── infra/                   # camada 1: monta os módulos com os valores do projeto
└── platform/                # camada 2: instala ArgoCD, ESO e ALB Controller no cluster
```

Dentro de uma camada, **os nomes dos arquivos não importam**: o Terraform lê todos os `.tf` da
pasta como se fossem um só. A divisão é para leitura humana:

| Arquivo em `infra/` | Conteúdo |
|---|---|
| `versions.tf` | versões e providers |
| `backend.tf` | onde fica o state |
| `variables.tf` / `locals.tf` / `outputs.tf` | entradas, cálculos, saídas |
| `data.tf` | LabRole |
| `network.tf`, `eks.tf`, `databases.tf`, `messaging.tf`, `ecr.tf`, `security.tf`, `secrets.tf` | um assunto por arquivo |

Como os valores fluem entre os módulos (cada seta é uma referência no código):

```
module.network ──vpc_id, subnets──► module.eks ──security group do cluster──► aws_security_group.rds
       │                                                                              │
       └───────────────subnets privadas──────────► module.rds ◄────────────────────────┘
                                                       │
random_password.db ──senha──► module.rds               │ endereço do banco
        │                                              ▼
        └──────────────senha──────────► module.secret_auth (Secrets Manager)
```

## 5. Dependências: por que não existe "ordem dos passos"

Quando um bloco usa o valor de outro, o Terraform entende que precisa criar o outro antes:

```hcl
subnet_ids = module.network.private_subnet_ids   # → a rede vem antes do banco
```

Recursos sem relação são criados em paralelo (as 3 instâncias RDS sobem juntas).

Quando a dependência é real mas não aparece em nenhuma referência, declara-se explicitamente:

```hcl
# terraform/modules/eks/main.tf
resource "aws_eks_addon" "coredns" {
  ...
  depends_on = [aws_eks_node_group.default]   # CoreDNS só fica saudável com nós disponíveis
}
```

Sem isso o projeto teve um erro real: os charts Helm instalados em paralelo falhavam porque o
webhook do ALB Controller ainda não estava pronto ([ETAPA-5.md](ETAPA-5.md)).

## 6. Repetição: `count` e `for_each`

```hcl
# count: N cópias numeradas — terraform/modules/network/main.tf
resource "aws_subnet" "private" {
  count             = length(var.azs)                           # 2 zonas → 2 subnets
  availability_zone = var.azs[count.index]
  cidr_block        = cidrsubnet(var.cidr_block, 4, count.index + 8)
}
```

```hcl
# for_each: uma cópia por chave de um mapa — terraform/infra/databases.tf
module "rds" {
  source   = "../modules/rds"
  for_each = var.databases                  # auth, flag, targeting → 3 instâncias

  identifier = "${var.project}-${each.key}"
  db_name    = each.value.db_name
  password   = random_password.db[each.key].result
}
```

Um bloco, três bancos. Um quarto banco é uma linha a mais na variável `databases`.
Prefira `for_each` quando os itens têm nome: remover um item do meio não renumera os outros.

## 7. State: o ponto que mais causa problemas

O state é o arquivo onde o Terraform registra **o que ele criou** e os IDs na AWS. Sem ele, o
Terraform não saberia que a VPC `vpc-0071...` é "a `aws_vpc.this` do módulo network".

Regras práticas:

1. **Nunca fica local nem no Git** em projeto real: contém senhas em texto e precisa ser compartilhado.
2. **Fica em um backend remoto com trava (lock)**, para duas pessoas não aplicarem ao mesmo tempo.

```hcl
# terraform/infra/backend.tf
terraform {
  backend "s3" {
    bucket       = "togglemaster-tfstate-583383233548"
    key          = "infra/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true      # cria um arquivo .tflock no bucket durante a operação
  }
}
```

3. **Uma camada pode ler os outputs de outra** pelo state:

```hcl
# terraform/platform/data.tf
data "terraform_remote_state" "infra" {
  backend = "s3"
  config  = { bucket = var.state_bucket, key = "infra/terraform.tfstate", region = var.region }
}
# uso: data.terraform_remote_state.infra.outputs.cluster_name
```

Por que duas camadas? `platform` instala charts **dentro** do cluster, então o provider `helm`
precisa do endereço do cluster já no `plan`. Separando, o cluster já existe quando `platform` roda.

### Quando o state e a realidade divergem — os três casos vividos no projeto

| Situação | Sintoma | Solução |
|---|---|---|
| Recurso existe na AWS, mas não no state (apply do EKS interrompido) | `plan` quer criar o que já existe | `terraform import <endereço> <id>` — [ETAPA-3.md](ETAPA-3.md) |
| Recurso está no state, mas não existe mais (destroy interrompido) | `plan` mostra "has been deleted" e recria | Nenhuma ação especial: `terraform apply` |
| Operação morreu segurando a trava | `Error acquiring the state lock` | `terraform force-unlock <ID>`, após confirmar que nada está rodando — [ETAPA-1.md](ETAPA-1.md) |

Se aparecer um arquivo `errored.tfstate` na pasta: o Terraform não conseguiu gravar o state remoto
ao final de uma operação e salvou uma cópia local para não perder a informação. Se um `plan`
posterior estiver coerente com a realidade, o arquivo já não é necessário.

## 8. Boas práticas que o projeto segue

| Prática | Onde |
|---|---|
| Versões fixadas (Terraform, providers, charts) | `versions.tf`, `.terraform.lock.hcl` (versionado), `platform/variables.tf` |
| Módulos sem valores fixos; valores na camada | `modules/*` recebem tudo por variável |
| Segredos gerados, nunca digitados | `random_password` → Secrets Manager |
| Tags padrão em todos os recursos | `default_tags` no provider |
| `plan` sempre antes de `apply`; `plan` vazio depois | Seção "Como testar" de cada `ETAPA-N.md` |
| `.terraform/`, `*.tfstate`, `*.tfvars` fora do Git | `.gitignore` |
| `lifecycle { ignore_changes }` para valor alterado fora do Terraform | `modules/secrets` (`SERVICE_API_KEY`) |

## 9. Prática

### Laboratório local (recomendado para começar)

[`docs/terraform-lab/`](terraform-lab/README.md): 10 exercícios e 4 desafios, sem AWS. Cobre init,
plan, apply, idempotência, state, variáveis, `for_each`, módulo, data source, drift e destroy.

### Explorar o projeto real sem alterar nada

Com o ambiente no ar e credenciais válidas (todos os comandos abaixo são somente leitura):

```bash
cd terraform/infra
terraform init
terraform state list                         # os ~57 recursos gerenciados
terraform state list | grep module.rds       # as 3 instâncias vindas de um for_each
terraform state show module.network.aws_vpc.this
terraform output                             # endpoints, URLs do ECR, nome do cluster
terraform plan                               # deve dizer "No changes"
terraform graph | head -40                   # dependências calculadas

terraform console
> var.databases
> local.cluster_name
> cidrsubnet("10.0.0.0/16", 4, 8)            # como nasce 10.0.128.0/20
> [for k, m in module.rds : m.address]
```

Exercício de leitura: rode `terraform plan -var node_desired_size=2` e identifique no plano qual
recurso muda, e se é alteração no lugar (`~`) ou recriação (`-/+`). Não aplique.

Com o ambiente derrubado, `./scripts/infra-up.sh --dry-run` mostra o plano completo de criação
(o que seria feito, do zero), também sem alterar nada.

## 10. Resumo de bolso

```
init      → prepara a pasta (providers, módulos, backend)
plan      → mostra a diferença entre código e realidade        ← leia sempre
apply     → executa a diferença
destroy   → remove o que está no state

resource  → cria e gerencia            data      → só lê o que já existe
variable  → entrada                    output    → saída
locals    → valor calculado            module    → pasta de recursos reutilizável
state     → memória do Terraform       backend   → onde o state fica (S3 + lock)

for_each / count → repetição           depends_on → ordem que o código não revela
import          → trazer para o state  force-unlock → soltar trava órfã
```
