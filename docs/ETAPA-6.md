# Etapa 6 — GitOps: manifestos em Kustomize e ArgoCD gerenciando os 5 serviços

Objetivo: abandonar o `kubectl apply` manual. Os manifestos passam a viver em `gitops/`, e o ArgoCD
mantém o cluster igual ao que está no Git, sincronizando automaticamente.

## O que foi feito

### 1. `gitops/apps/<serviço>/` — um diretório Kustomize por microsserviço

Substitui a pasta `k8s/` da Fase 2 (arquivos numerados aplicados à mão, removida nesta etapa).

```
gitops/apps/auth-service/
├── kustomization.yaml     # namespace, recursos, ConfigMap gerado e TAG DA IMAGEM
├── namespace.yaml
├── external-secret.yaml   # (auth, flag, targeting, evaluation)
├── deployment.yaml
├── service.yaml
├── ingress.yaml
└── hpa.yaml               # (evaluation, analytics)
```

| Serviço | Namespace | Porta | Caminho no ALB | Secret (Secrets Manager) | HPA |
|---|---|---|---|---|---|
| auth-service | `auth` | 8001 | `/auth` | `togglemaster/auth-service` | — |
| flag-service | `flags` | 8002 | `/flags` | `togglemaster/flag-service` | — |
| targeting-service | `targeting` | 8003 | `/targeting` | `togglemaster/targeting-service` | — |
| evaluation-service | `evaluation` | 8004 | `/evaluation` | `togglemaster/evaluation-service` + `...-api-key` | 1–5 |
| analytics-service | `analytics` | 8005 | `/analytics` | — (só SQS/DynamoDB, role do nó) | 1–5 |

O que mudou em relação aos manifestos da Fase 2:

| Antes (Fase 2) | Agora | Por quê |
|---|---|---|
| `Secret` com base64 preenchido à mão | `ExternalSecret` → Secrets Manager | Nenhum valor sensível no Git; senhas geradas pelo Terraform |
| `AWS_ACCESS_KEY_ID/SECRET/SESSION_TOKEN` em Secret + CronJob de refresh | removidos | Pods usam a role do nó via IMDS (Etapa 3) |
| Imagem `fase2/<svc>:latest` (conta antiga) | `togglemaster/<svc>:v1.0.0-<sha7>` definida em `kustomization.yaml` | Tag imutável por commit: rastreável e atualizável pelo CI |
| `ConfigMap` fixo | `configMapGenerator` (nome com hash) | Mudança de configuração reinicia os pods automaticamente |
| Ingress `nginx` com `rewrite-target` | Ingress `alb`, um ALB compartilhado (`group.name`) com `url-rewrite` | ingress-nginx foi descontinuado; ALB Controller já está instalado; 1 ALB em vez de 5 |
| `replicas: 1` em todos | sem `replicas` onde há HPA | Evita disputa entre ArgoCD (Git) e HPA |
| — | label `elbv2.k8s.aws/pod-readiness-gate-inject` no namespace + `preStop` de 15s | Rolling update sem 502: pod novo só fica Ready depois de saudável no ALB; pod antigo espera sair da rotação |

Reescrita de caminho no ALB (ex.: `/auth/health` → `/health` no pod):

```yaml
alb.ingress.kubernetes.io/transforms.auth-service: >-
  [{"type":"url-rewrite","urlRewriteConfig":{"rewrites":[{"regex":"^/auth/?(.*)$","replace":"/$1"}]}}]
```

Onde a tag da imagem é definida (é esta linha que o CI vai alterar na Etapa 8):

```yaml
# gitops/apps/auth-service/kustomization.yaml
images:
  - name: auth-service
    newName: 583383233548.dkr.ecr.us-east-1.amazonaws.com/togglemaster/auth-service
    newTag: v1.0.0-84706c4
```

> O desafio cita "alterar o arquivo deployment.yaml". Com Kustomize a tag fica em
> `kustomization.yaml`, que é o ponto único de alteração; o `deployment.yaml` usa só o nome lógico
> da imagem. O efeito no cluster é o mesmo.

Valores específicos da conta AWS (registry do ECR e URL da fila SQS) estão escritos nos manifestos.
Se a conta do Lab mudar, ajustar em `gitops/apps/*/kustomization.yaml`.

### 2. ArgoCD: `ApplicationSet` (em `terraform/platform`)

Chart local `charts/argocd-apps`, instalado pelo Terraform, com um `ApplicationSet` que usa o
gerador *git directories*: **uma `Application` para cada pasta em `gitops/apps/`**.

- Adicionar um microsserviço = adicionar uma pasta. Nada muda no ArgoCD.
- `syncPolicy.automated` com `prune` (remove o que saiu do Git) e `selfHeal` (desfaz alteração manual).
- Repositório público → sem credencial de Git no cluster.
- Variáveis `gitops_repo_url`, `gitops_revision` (padrão `main`) e `gitops_apps_path`.

A estrutura planejada `gitops/argocd/` (app-of-apps) foi substituída por esse `ApplicationSet`:
o vínculo ArgoCD ↔ repositório fica junto da instalação do ArgoCD, como código Terraform.

### 3. `metrics-server` (módulo `eks`)

Addon gerenciado do EKS, necessário para os `HorizontalPodAutoscaler` lerem CPU dos pods.

### 4. Scripts de bootstrap

| Script | Quando usar | O que faz |
|---|---|---|
| `scripts/bootstrap-images.sh` | 1º deploy e após recriar o ambiente | Build `linux/amd64`, push no ECR com `v1.0.0-<sha7>`, atualiza `newTag` nos `kustomization.yaml`. No dia a dia isso é papel do CI |
| `scripts/bootstrap-service-api-key.sh` | 1º deploy e após recriar o ambiente | Pede a `SERVICE_API_KEY` ao auth-service **de dentro do pod** (a `MASTER_KEY` não sai do cluster), grava no Secrets Manager, força o ESO a ressincronizar e reinicia o evaluation-service |
| `scripts/test-services.sh` | Sempre | `/health` dos 5 serviços pelo ALB + fluxo ponta a ponta (flag → regra → avaliação → SQS → DynamoDB) |

`infra-up.sh` agora imprime essa sequência ao final.

### 5. Arquivos da Fase 2 removidos

`k8s/` (manifestos, CronJob de credenciais e scripts de teste), `build-images-and-push.sh` e
`refresh-academy-credentials.sh`. Continuam disponíveis no histórico do Git.

## Como testar

```bash
# 0. Manifestos renderizam
for d in gitops/apps/*; do kubectl kustomize $d >/dev/null && echo "ok $d"; done

# 1. Imagens no ECR e tags no Git (commitar e enviar a alteração de gitops/)
./scripts/bootstrap-images.sh

# 2. ApplicationSet (a camada platform já aplicada cria; padrão: branch main)
cd terraform/platform && terraform apply && cd ../..

# 3. As 5 Applications: Synced / Healthy
kubectl get applications -n argocd
kubectl get pods -A | grep -E '^(auth|flags|targeting|evaluation|analytics) '
kubectl get externalsecret -A        # SecretSynced
kubectl get ingress -A               # todos com o MESMO endereço de ALB
kubectl get hpa -A                   # cpu: N%/70%

# 4. UI do ArgoCD mostrando os 5 microsserviços
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 8080:80      # http://localhost:8080, usuário admin

# 5. Chave de serviço e teste ponta a ponta
./scripts/bootstrap-service-api-key.sh
./scripts/test-services.sh

# 6. GitOps na prática: alterar algo em gitops/, commit + push, e observar (até ~60s)
kubectl get applications -n argocd -w

# 7. Self-heal: alteração manual é desfeita
kubectl scale deployment auth-service -n auth --replicas=3
kubectl get deployment auth-service -n auth -w     # volta para 1
```

## Resultado da validação (2026-10-04)

Validado com o `ApplicationSet` apontando temporariamente para o branch `fase3/etapa-6`
(`terraform apply -var gitops_revision=fase3/etapa-6`).

| Verificação | Resultado |
|---|---|
| `kubectl kustomize` nos 5 diretórios | ✅ |
| Imagens no ECR | ✅ 5 imagens `v1.0.0-ba71c38` (1ª carga) |
| `metrics-server` | ✅ `kubectl top nodes` e HPAs com `cpu: 1%/70%` |
| Applications | ✅ 5 `Synced` / `Healthy` |
| Pods | ✅ 5 `Running` (schemas aplicados nos 3 RDS pelos entrypoints) |
| ExternalSecrets | ✅ 4 `SecretSynced` |
| Ingress | ✅ 5 Ingress em 1 ALB (`k8s-togglemaster-...`) |
| `/health` pelo ALB (reescrita de caminho) | ✅ 200 nos 5 serviços |
| `bootstrap-service-api-key.sh` | ✅ chave emitida, gravada e aplicada |
| Ponta a ponta | ✅ avaliação respondeu 200 e o evento chegou ao DynamoDB (0 → 1 item); ✅ criação de flag com a chave (201) e rejeição sem chave (401) |
| Sync automático | ✅ commit `8e6e640` (label nos namespaces) aplicado pelo ArgoCD em ~70s, sem intervenção |
| Rolling update com readiness gate | ✅ 89 de 90 requisições com 200 durante o restart |
| Rolling update com `preStop` | ✅ 120 de 120 requisições com 200 durante o restart do evaluation-service |
| Self-heal | ✅ `kubectl scale --replicas=3` no auth-service desfeito pelo ArgoCD em ~3s |
| Ambiente recriado do zero | ✅ `infra-up.sh` (38 + 5 recursos) → `bootstrap-images.sh` (`v1.0.0-84706c4`) → 5 Applications `Synced`/`Healthy` em ~2 min → `bootstrap-service-api-key.sh` |
| `test-services.sh` completo | ✅ health ×5, 401 sem chave, flag 201, regra 201, avaliação 200 (`result: true`), evento no DynamoDB (0 → 1) |
| `ApplicationSet` apontando para `main` | ⏳ após o merge deste PR: `terraform -chdir=terraform/platform apply` (sem `-var`) |

### Problemas encontrados

- **502 logo após um restart**: o ALB ainda apontava para o pod antigo. Resolvido com o *pod
  readiness gate* (label no namespace) e `preStop`.
- **`test-services.sh` retornava 400 no cadastro**: erro de aspas no JSON montado pelo script
  (o cadastro manual retornava 201). Corrigido montando o JSON com `printf`.

## Custos desta etapa

1 Application Load Balancer (~US$ 0,0225/h + LCUs).
