# Laboratório de Terraform (sem AWS, sem custo)

Um projeto Terraform pequeno que imita a estrutura do projeto real (`terraform/infra`), mas só cria
**arquivos na sua máquina**. Serve para entender o ciclo da ferramenta antes de mexer em nuvem.

Leia junto com o [guia](../TERRAFORM-GUIA.md). Tempo: cerca de 40 minutos.

| Neste laboratório | Equivalente no projeto real |
|---|---|
| provider `local` (cria arquivos) | provider `aws` (cria recursos na AWS) |
| `data "local_file" "role_existente"` | `data "aws_iam_role" "lab"` (LabRole) |
| `random_password.banco` com `for_each` | `random_password.db` (senhas do RDS) |
| `module "servico"` com `for_each` | `module "rds"` com `for_each` |
| `terraform.tfstate` local | state no bucket S3 |

```bash
cd docs/terraform-lab
```

## Exercício 1 — `init`: preparar a pasta

```bash
terraform init
```

O Terraform lê `versions.tf`, baixa os providers `local` e `random` para `.terraform/` e registra as
versões exatas em `.terraform.lock.hcl`.

**Observe:** nada foi criado ainda. `init` só prepara. É o primeiro comando em qualquer pasta
Terraform, e precisa ser repetido quando providers, módulos ou backend mudam.

## Exercício 2 — `plan` e `apply`: criar

```bash
terraform plan
```

O plano mostra o que **seria** feito, sem fazer. Leia a última linha: `Plan: 4 to add, 0 to change, 0 to destroy`.
O símbolo `+` significa "será criado".

```bash
terraform apply        # mostra o plano de novo e pede "yes"
ls saida/
cat saida/togglemaster-lab-auth.conf
```

**Observe:**
- Foram criados 4 recursos: 2 senhas e 2 arquivos (um por serviço da variável `servicos`).
- A linha `role = arn:aws:iam::...` veio do **data source**, que leu `existente/lab-role.txt`.
- Os **outputs** aparecem no final; `senhas` aparece como `(sensitive value)`.

## Exercício 3 — Idempotência: rodar de novo não muda nada

```bash
terraform plan
```

Resultado: `No changes. Your infrastructure matches the configuration.`

Esse é o conceito central. Você não escreve "crie um arquivo"; você **declara** "este arquivo deve
existir". O Terraform compara o desejado (código) com o que existe (state + realidade) e só age na
diferença. Rodar 1 ou 100 vezes dá o mesmo resultado.

## Exercício 4 — O state: a memória do Terraform

```bash
terraform state list
terraform state show 'module.servico["auth"].local_file.config'
terraform output
terraform output -json senhas
ls -la terraform.tfstate
```

**Observe:**
- `state list` mostra tudo o que o Terraform gerencia, com o "endereço" de cada recurso.
  `module.servico["auth"]` é a instância `auth` do módulo criado com `for_each`.
- `terraform.tfstate` é um arquivo JSON. É nele que o Terraform anota o que criou.
- `output -json senhas` revela as senhas: `sensitive` só esconde do terminal, **o valor está no
  state em texto**. Por isso o state do projeto real fica em bucket privado e criptografado, e
  nunca vai para o Git.

## Exercício 5 — Mudar uma variável: ler um plano de alteração

```bash
terraform plan -var ambiente=prod
```

**Observe:** `-/+ ... must be replaced` e `# forces replacement` ao lado de `filename`.
O nome do arquivo depende de `var.ambiente`; como um arquivo não pode ser "renomeado" pelo provider,
o Terraform planeja destruir e recriar. As senhas não aparecem no plano: não dependem da variável.

Símbolos de um plano:

| Símbolo | Significado |
|---|---|
| `+` | criar |
| `-` | destruir |
| `~` | alterar no lugar |
| `-/+` | destruir e recriar (*replacement*) |

Não aplique (foi só um `plan`). Em nuvem, `-/+` em um banco de dados significa perda de dados:
ler o plano antes do `apply` é o hábito mais importante com Terraform.

## Exercício 6 — `for_each`: adicionar um serviço sem escrever recurso novo

Crie o arquivo `lab.auto.tfvars` (arquivos `*.auto.tfvars` são lidos automaticamente):

```hcl
servicos = {
  auth      = { porta = 8001, usa_banco = true }
  flag      = { porta = 8002, usa_banco = true }
  analytics = { porta = 8005, usa_banco = false }
}
```

```bash
terraform plan         # Plan: 1 to add
terraform apply
```

**Observe:** só 1 recurso novo. O `analytics` ganhou arquivo, mas **não** ganhou senha: o
`for_each` de `random_password.banco` usa `local.servicos_com_banco`, que filtra `usa_banco = true`.
Os recursos de `auth` e `flag` não foram tocados.

No projeto real é assim que existem 3 instâncias RDS a partir de um único bloco `module "rds"`.

## Exercício 7 — Drift: alguém mexeu "por fora"

```bash
rm saida/togglemaster-lab-flag.conf
terraform plan
```

Resultado: `Objects have changed outside of Terraform` → `has been deleted` → `Plan: 1 to add`.

```bash
echo "porta = 9999" >> saida/togglemaster-lab-auth.conf
terraform plan         # agora 2 to add
terraform apply
cat saida/togglemaster-lab-auth.conf     # a linha 9999 sumiu
```

A cada `plan`, o Terraform consulta a realidade (*refresh*) e compara com o state. O que foi
apagado ou alterado manualmente é detectado e corrigido para o que o código declara.

No projeto real isso aconteceu de verdade: um `destroy` interrompido deixou o state listando 56
recursos quando só 2 existiam; o `plan` seguinte detectou e planejou recriar 38
(ver `docs/ETAPA-1.md`, "Solução de problemas").

## Exercício 8 — Remover do código = destruir

```bash
rm lab.auto.tfvars
terraform plan
```

Resultado: `module.servico["analytics"]... will be destroyed (because ... is not in configuration)`.

O que sai do código sai da infraestrutura. Não aplique ainda; vá para o próximo exercício.

## Exercício 9 — Dependências: de onde vem a ordem

```bash
terraform graph
```

Você nunca escreveu "primeiro leia o arquivo, depois crie o módulo". O Terraform montou a ordem a
partir das **referências**: `module.servico` usa `data.local_file.role_existente.content`, logo
depende dele. Recursos sem relação entre si são criados em paralelo.

Quando a dependência existe mas não aparece em nenhuma referência, usa-se `depends_on`. Exemplo real:
`terraform/platform/argocd.tf` espera o ALB Controller, que intercepta a criação de `Service`.

## Exercício 10 — `destroy`: desfazer tudo

```bash
terraform destroy
ls saida/ 2>/dev/null
cat existente/lab-role.txt
terraform state list
```

**Observe:**
- Os arquivos e as senhas sumiram; o state ficou vazio.
- `existente/lab-role.txt` **continua lá**: data source só lê, nunca cria nem apaga. É por isso
  que a LabRole do Academy não corre risco no `terraform destroy` do projeto real.

## Desafios (para fixar)

1. Adicione a variável `versao` (string) e inclua `versao = ...` no arquivo gerado pelo módulo.
   Dica: são 3 lugares (`modules/servico/variables.tf`, `modules/servico/main.tf` e a chamada em `main.tf`).
2. Crie um output `quantidade_de_servicos` usando `length(var.servicos)`.
3. Rode `terraform apply`, renomeie a chave `flag` para `flags` em `lab.auto.tfvars` e leia o plano.
   Por que ele destrói um e cria outro em vez de renomear? (O endereço no state mudou.)
4. Rode `terraform console` e avalie: `local.prefixo`, `local.servicos_com_banco`,
   `cidrsubnet("10.0.0.0/16", 4, 8)` (a função que calcula as subnets do projeto real).

Para deixar a pasta limpa ao terminar:

```bash
terraform destroy
rm -rf .terraform terraform.tfstate* lab.auto.tfvars
```
