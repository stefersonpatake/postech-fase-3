# Estimativa de custos (AWS, us-east-1)

O relatório de entrega pede um **print da estimativa de custos**. O print oficial deve ser gerado na
[AWS Pricing Calculator](https://calculator.aws/) com os dados abaixo, que refletem exatamente o que
o Terraform provisiona.

> Os valores desta página são **aproximados**, baseados nos preços de tabela on-demand da região
> us-east-1 (a API de preços não é acessível pela conta do AWS Academy). Use-os para conferir a
> ordem de grandeza; o número oficial é o da calculadora.

## O que cadastrar na calculadora

| # | Serviço na calculadora | Configuração |
|---|---|---|
| 1 | Amazon EKS | 1 cluster, suporte padrão, 730 h/mês |
| 2 | Amazon EC2 | 3 × `t3.medium`, Linux, On-Demand, 730 h/mês; EBS gp3 20 GB por instância |
| 3 | Amazon VPC → NAT Gateway | 1 NAT Gateway, 730 h/mês, ~10 GB processados |
| 4 | Amazon VPC → Public IPv4 | 3 endereços em uso (1 do NAT + 2 do ALB) |
| 5 | Elastic Load Balancing | 1 Application Load Balancer, tráfego baixo (~1 LCU) |
| 6 | Amazon RDS for PostgreSQL | 3 × `db.t3.micro`, Single-AZ, On-Demand; 20 GB gp3 cada; sem backup adicional |
| 7 | Amazon ElastiCache | Redis OSS, 1 nó `cache.t3.micro`, On-Demand |
| 8 | Amazon DynamoDB | On-demand, 1 GB, ~1 milhão de escritas/mês |
| 9 | Amazon SQS | Fila padrão, ~1 milhão de requisições/mês (dentro do nível gratuito) |
| 10 | Amazon ECR | ~2 GB de imagens (5 repositórios, até 15 imagens cada) |
| 11 | AWS Secrets Manager | 5 secrets |
| 12 | Amazon S3 | < 1 GB (state do Terraform) |

## Estimativa aproximada — ambiente ligado 24×7

| Recurso | Cálculo | US$/mês |
|---|---|---:|
| EKS (control plane) | 0,10 × 730 h | 73,00 |
| EC2 — 3 × t3.medium | 3 × 0,0416 × 730 h | 91,10 |
| EBS dos nós | 3 × 20 GB × 0,08 | 4,80 |
| NAT Gateway | 0,045 × 730 h + dados | ~33,30 |
| IPv4 públicos | 3 × 0,005 × 730 h | 10,95 |
| Application Load Balancer | 0,0225 × 730 h + ~1 LCU | ~22,30 |
| RDS — 3 × db.t3.micro | 3 × 0,018 × 730 h | 39,42 |
| RDS — armazenamento | 3 × 20 GB × 0,115 | 6,90 |
| ElastiCache — cache.t3.micro | 0,017 × 730 h | 12,41 |
| Secrets Manager | 5 × 0,40 | 2,00 |
| DynamoDB, SQS, ECR, S3 | uso baixo | ~2,00 |
| **Total aproximado** | | **~US$ 298/mês** (≈ US$ 0,41/h) |

Ferramentas externas sem custo para repositório público: GitHub Actions, SonarCloud. ArgoCD,
External Secrets e ALB Controller rodam nos nós já contabilizados.

## Custo real do projeto

Painel "Custo e uso" do console AWS em 04/10/2026: **US$ 4,46** acumulados no mês e previsão de
**US$ 18,51** para o fechamento.

![Painel Custo e uso da AWS em 04/10/2026](img/custo-e-uso-aws-2026-10-04.png)

O ambiente não fica ligado 24×7: `./scripts/infra-down.sh` destrói tudo ao fim de cada sessão e
`./scripts/infra-up.sh` recria em ~20 minutos. A ~US$ 0,41/h, uma sessão de 4 horas custa cerca de
US$ 1,65. Esse é o principal ganho financeiro de ter a infraestrutura inteira como código.

## Onde reduzir em um cenário real

| Item | Economia | Contrapartida |
|---|---|---|
| Nós em Spot ou Graviton (`t4g.medium`) | 20–70% do EC2 | Spot pode ser interrompido; Graviton exige imagens arm64 |
| 1 instância RDS com 3 bancos | ~US$ 30/mês | Perde o isolamento por serviço (o desafio pede 3 instâncias) |
| VPC endpoints no lugar do NAT | parte dos US$ 33 | Só compensa com pouco tráfego de saída para a internet |
| Savings Plans / instâncias reservadas | até ~40% | Compromisso de 1 a 3 anos |

Em produção o custo **subiria** em disponibilidade: NAT por zona, RDS Multi-AZ com backups, Redis
com réplica.
