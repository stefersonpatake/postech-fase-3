# PosTech DevOps — Fase 2

## Resumo

Criação de um cluster **EKS na AWS Academy**, contornando as limitações da `LabRole`, e
deploy da arquitetura de microsserviços (`auth`, `flag`, `targeting`, `evaluation`, `analytics`).

## Decisão principal

Usar **"Configuração personalizada"** (EKS clássico com *Managed Node Groups*).

> ⚠️ **Nunca** usar "Configuração rápida" (EKS Auto Mode) — quebra com a `LabRole`.

---

## Criação do Cluster

Assistente do console em 6 etapas:

| Etapa | Configuração |
|-------|--------------|
| **Configurar cluster** | Nome livre; Kubernetes mais recente (1.36); IAM role = `LabRole`; **desmarcar** "Modo automático do EKS"; **habilitar** "Acesso ao cluster"; modo de autenticação = **"API do EKS e ConfigMap"**; sem criptografia envelopada (exige KMS); sem proteção contra exclusão. |
| **Redes** | VPC padrão; todas as subnets; IPv4; endpoint **Público** (essencial para o `kubectl`). |
| **Observabilidade** | Tudo desabilitado (evita custo). |
| **Complementos** | Apenas `CoreDNS`, `VPC CNI` e `kube-proxy` — desmarcar todos os outros. |
| **Configs dos add-ons** | Manter versões padrão. |
| **Analisar e criar** | Criar e aguardar (~10–15 min) até o status ficar **Ativo**. |

## Criação do Node Group

- **IAM role:** `LabRole`
- **AMI:** Amazon Linux 2023
- **Capacidade:** On-Demand
- **Instância:** `t3.medium` — disco 20 GiB
- **Escala:** mín. 1 / máx. 2 / desejado 1; reparo automático habilitado
- **Rede:** todas as subnets; sem acesso remoto (SSH)
- Aguardar (~5–10 min) até **Ativo**.

## Conexão e teste

```bash
aws eks update-kubeconfig --region us-east-1 --name serious-drummer-player

kubectl get nodes        # 1 nó Ready, v1.36.3-eks
kubectl create deployment nginx --image=nginx
kubectl get pods         # nginx Running 1/1
kubectl expose deployment nginx --port=80 --type=LoadBalancer
kubectl get svc          # próximo passo: pegar o EXTERNAL-IP
```

**Resultado:** cluster EKS + 1 node `t3.medium` ativos, `kubectl` conectado, `nginx` rodando

Internet
    ↓
Load Balancer (ELB)
    ↓
Service (nginx - porta 80)
    ↓
Pod (nginx - Running)
    ↓
Node (t3.medium - EC2)
    ↓
Cluster EKS (Kubernetes 1.36)

---

## Desafios — Debug e estabilização dos serviços no EKS

Durante o deploy no EKS foram identificados e corrigidos os seguintes problemas que impediam
o funcionamento correto da arquitetura de microsserviços:

### 1. Health checks com porta incorreta

O `evaluation-service` expõe a aplicação na porta **8004**, mas os probes de *liveness*/*readiness*
apontavam para **3000**, causando `CrashLoopBackOff`.

### 2. Conexão TLS ausente com o Redis (ElastiCache Serverless)

A variável `REDIS_URL` usava o esquema `redis://` na porta `6379`, mas o ElastiCache Serverless
exige TLS. Corrigida para `rediss://...:6380`. Foi necessário ajustar tanto o **ConfigMap** quanto
um **Secret** que sobrescrevia esse valor com a configuração antiga.

### 3. Security Group bloqueando tráfego para o ElastiCache

Não havia regra de *ingress* liberando a porta `6380` entre o Security Group dos nós EKS e o do
ElastiCache. Regra adicionada via console AWS.

### 4. Falha causada por auto-instrumentação OpenTelemetry

A injeção automática do OTel Python (`v0.19.0`) era incompatível com o runtime Python 3.9 dos
serviços, causando crash. Desativada via annotations nos serviços `analytics-service`,
`targeting-service` e `evaluation-service`:

```yaml
instrumentation.opentelemetry.io/inject-python: "false"
cloudwatch.aws.amazon.com/auto-annotate-python: "false"
```
