# Etapa 5 — Plataforma no cluster (ALB Controller, External Secrets, ArgoCD)

Objetivo: instalar via Terraform (provider `helm`) os componentes de plataforma que rodam dentro do
EKS e que as aplicações vão usar: entrada de tráfego, sincronização de segredos e GitOps.

## O que foi feito

### 1. Camada `terraform/platform`

Camada separada da `infra`, com state próprio (`platform/terraform.tfstate` no mesmo bucket).
Motivo: o provider `helm` precisa do endpoint do cluster na hora do `plan`; mantendo em outra
camada, o cluster já existe quando ela roda.

| Arquivo | Conteúdo |
|---|---|
| `backend.tf` | Backend S3 com `use_lockfile` |
| `versions.tf` | Providers `aws` e `helm`; o `helm` autentica com `aws eks get-token` (token de curta duração, sem depender do kubeconfig local) |
| `data.tf` | `terraform_remote_state` da camada `infra` (nome do cluster, VPC) + `aws_eks_cluster` |
| `alb-controller.tf` | AWS Load Balancer Controller |
| `external-secrets.tf` | External Secrets Operator + chart local `platform-config` |
| `argocd.tf` | ArgoCD |
| `charts/platform-config/` | Chart local com o `ClusterSecretStore` |

### 2. Componentes instalados

| Componente | Chart (versão fixada) | Namespace | Configuração |
|---|---|---|---|
| AWS Load Balancer Controller | `eks/aws-load-balancer-controller` 3.5.0 | `kube-system` | `clusterName`, `region`, `vpcId` vindos do state da infra |
| External Secrets Operator | `external-secrets/external-secrets` 2.11.0 | `external-secrets` | `installCRDs = true` |
| `ClusterSecretStore aws-secrets-manager` | chart local `platform-config` | (cluster) | Provider AWS Secrets Manager, **sem bloco `auth`** |
| ArgoCD | `argo/argo-cd` 10.9.6 (app v3.5.3) | `argocd` | `server.insecure` (TLS fora do pod), reconciliação a cada 60s, Dex desligado |

Decisões:

- **Sem credenciais estáticas.** ALB Controller e ESO usam a cadeia padrão de credenciais, que
  resolve para a role do nó (LabRole) via IMDS (Etapa 3). Nada de `secretRef` com access key.
- **`ClusterSecretStore` em chart local.** `kubernetes_manifest` exige que o CRD exista na hora do
  `plan`, o que quebraria um `apply` do zero. Um chart Helm local é aplicado depois do ESO
  (`depends_on`) e resolve a ordem.
- **Versões de chart fixadas** em variáveis: upgrade é uma mudança explícita e revisável no código.
- **ArgoCD sem Ingress/ALB.** A UI é acessada por `port-forward`; evita mais um ALB cobrado por hora e
  expor o painel de deploy na internet. As Applications ficam no Git (`gitops/argocd/`, Etapa 6).

### 3. Problema encontrado: corrida com o webhook do ALB Controller

No primeiro `apply` os três charts foram instalados em paralelo e o ESO falhou:

```
Internal error occurred: failed calling webhook "mservice.elbv2.k8s.aws": ...
no endpoints available for service "aws-load-balancer-webhook-service"
```

O ALB Controller registra um webhook que intercepta a criação de **todo** `Service`. Enquanto seus
pods não estão prontos, qualquer `Service` novo é rejeitado.

Correção: `depends_on = [helm_release.alb_controller]` no ESO e no ArgoCD (o `helm_release` só
conclui com os pods prontos). O release do ESO que ficou com status `failed` (fora do state) foi
removido com `helm uninstall external-secrets -n external-secrets` e o `apply` seguinte concluiu.

### 4. `scripts/infra-down.sh`: limpeza de load balancers

ALBs criados pelo controller a partir de `Ingress` não estão no state do Terraform. Se o controller
for destruído antes deles, ficam órfãos e a exclusão da VPC trava. O script agora, antes de destruir:

1. remove as `Applications` do ArgoCD (senão ele recria os Ingress);
2. apaga todos os `Ingress` e aguarda o controller remover os ALBs.

## Como testar

```bash
cd terraform/platform
terraform init
terraform plan -detailed-exitcode; echo $?      # 0 = sem mudanças
terraform output

# Pods de plataforma Running
kubectl get pods -n argocd
kubectl get pods -n external-secrets
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl get ingressclass                         # alb

# ClusterSecretStore válido (ESO conseguiu falar com o Secrets Manager)
kubectl get clustersecretstore                   # STATUS Valid, READY True

# Sincronização de um segredo real do Secrets Manager
kubectl create ns eso-test
kubectl apply -f - <<'YAML'
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata: { name: auth-test, namespace: eso-test }
spec:
  refreshInterval: 1h
  secretStoreRef: { kind: ClusterSecretStore, name: aws-secrets-manager }
  target: { name: auth-test }
  dataFrom:
    - extract: { key: togglemaster/auth-service }
YAML
kubectl wait -n eso-test externalsecret/auth-test --for=condition=Ready --timeout=60s
kubectl get secret auth-test -n eso-test -o jsonpath='{.data}' | python3 -c 'import sys,json; print(list(json.load(sys.stdin)))'
kubectl delete ns eso-test

# ArgoCD — UI
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 8080:80
# abrir http://localhost:8080  (usuário: admin)

# ArgoCD — CLI (usa o port-forward embutido da própria CLI)
export ARGOCD_OPTS="--port-forward --port-forward-namespace argocd --plaintext"
argocd login --username admin \
  --password "$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
argocd version --short
argocd cluster list
argocd app list                                  # vazio até a Etapa 6
```

> Na CLI, prefira `ARGOCD_OPTS` com `--port-forward`: nos testes, `argocd login localhost:8080`
> através de um `kubectl port-forward` separado falhou na conexão gRPC, enquanto a UI (HTTP)
> funcionou normalmente.

## Resultado da validação (2026-10-04)

| Verificação | Resultado |
|---|---|
| `terraform apply` | ✅ 4 releases Helm (após a correção de ordem) |
| `plan -detailed-exitcode` | ✅ exit 0 |
| ArgoCD | ✅ 6 pods `Running` (server, repo-server, application-controller, applicationset, notifications, redis) |
| External Secrets | ✅ 3 pods `Running` |
| ALB Controller | ✅ 2 pods `Running`, `IngressClass alb`, sem erros no log |
| `ClusterSecretStore` | ✅ `Valid` / `Ready=True` |
| `ExternalSecret` de teste | ✅ Secret K8s criado com `DATABASE_URL`, `DB_*`, `MASTER_KEY` vindos de `togglemaster/auth-service` |
| ArgoCD UI | ✅ HTTP 200 em `http://localhost:8080` |
| ArgoCD CLI | ✅ login `admin`, server v3.5.3, cluster `in-cluster` |
| `infra-down.sh --dry-run` | ✅ `platform`: 4 a destruir; `infra`: 56 a destruir |

## Custos desta etapa

Nenhum recurso AWS novo cobrado: os componentes rodam nos nós existentes (19 pods no cluster).
