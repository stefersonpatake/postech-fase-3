# Etapa 8 — Entrega contínua: o CI atualiza a tag no GitOps

Objetivo: fechar o ciclo. Ao final do pipeline de CI, um passo registra no repositório de GitOps a
nova tag da imagem. O ArgoCD detecta o commit e sincroniza o cluster. Ninguém (nem o CI) executa
`kubectl apply`.

```
push na main ─► CI (build, testes, lint, segurança) ─► imagem no ECR (v1.0.0-<sha7>)
                                                            │
                          commit do bot em gitops/apps/<serviço>/kustomization.yaml
                                                            │
                               ArgoCD detecta (≤ 60s) ─► rolling update no EKS
```

## O que foi feito

### 1. Job `gitops` nos pipelines reutilizáveis (`_ci-go.yml`, `_ci-python.yml`)

Quinto estágio, depois de `Docker Build, Scan & Push`:

| Aspecto | Como |
|---|---|
| Quando roda | Só se o job Docker publicou uma imagem (`needs.docker.outputs.image_tag != ''`), ou seja, na `main` |
| O que altera | A linha `newTag:` de `gitops/apps/<serviço>/kustomization.yaml` |
| Autor do commit | `github-actions[bot]`, mensagem `gitops(<serviço>): imagem v1.0.0-<sha7>` |
| Permissão | `contents: write` apenas neste job (os demais continuam `read`); usa o `GITHUB_TOKEN` do próprio workflow, sem PAT |
| Concorrência | Até 6 tentativas: `fetch` + `reset` para a `main` mais recente, altera, `push`; se outro serviço enviou antes, repete |
| Idempotência | Se a tag já é a desejada, encerra sem commit |

```yaml
gitops:
  name: GitOps - atualizar tag da imagem
  needs: docker
  if: needs.docker.outputs.image_tag != ''
  permissions:
    contents: write
  steps:
    - uses: actions/checkout@v7
      with: { ref: main }
    - run: |
        sed -i -E "s|^([[:space:]]*newTag:).*|\1 $TAG|" "gitops/apps/$SERVICE/kustomization.yaml"
        git commit -am "gitops($SERVICE): imagem $TAG" && git push origin HEAD:main
```

> O desafio descreve "alterar o arquivo deployment.yaml". Com Kustomize, a tag fica em
> `kustomization.yaml` (campo `images`), que é o arquivo alterado pelo pipeline.

### 2. Por que não há loop de pipelines

- O commit do bot só toca em `gitops/`, que não está nos `paths` de nenhum workflow de serviço.
- Além disso, pushes feitos com o `GITHUB_TOKEN` não disparam novos workflows (regra do GitHub).

### 3. Outros ajustes

| Ajuste | Motivo |
|---|---|
| `workflow_dispatch` nos 5 workflows de serviço | Republicar imagens e atualizar o GitOps sob demanda (ex.: após `infra-up.sh`, quando o ECR volta vazio), sem depender de Docker local: `gh workflow run auth-service.yml` |
| Push no ECR ignorado se a tag já existe | Tags são imutáveis; reexecutar o pipeline do mesmo commit não falha mais |
| Publicação na `main` também em execução manual | Condição passou de "evento push" para "branch main e não é PR" |

## Como testar

```bash
# 1. Alterar qualquer coisa em um serviço e levar para a main (via PR)
#    ex.: uma mensagem de log no flag-service

# 2. Acompanhar o pipeline na main
gh run list --branch main --limit 5
gh run watch <id>                       # 5 jobs: build-test, lint, security, docker, gitops

# 3. Commit do bot com a nova tag
git pull
git log --oneline -3 -- gitops/         # gitops(flag-service): imagem v1.0.0-xxxxxxx
grep newTag gitops/apps/flag-service/kustomization.yaml

# 4. ArgoCD detecta e sincroniza sozinho
kubectl get applications -n argocd -w   # flag-service: OutOfSync → Synced / Progressing → Healthy
kubectl get deployment flag-service -n flags -o jsonpath='{.spec.template.spec.containers[0].image}'; echo

# 5. Aplicação continua funcionando
./scripts/test-services.sh

# Republicar tudo manualmente (ex.: ambiente recriado)
for s in auth flag targeting evaluation analytics; do gh workflow run $s-service.yml; done
```

Na UI do ArgoCD (`kubectl -n argocd port-forward svc/argocd-server 8080:80`), a Application do
serviço mostra o novo commit em *Last Sync* e os pods sendo substituídos.

## Resultado da validação (2026-10-04)

Validado no merge do PR #9 (commit `a13ec71`): como os workflows mudaram, os 5 pipelines dispararam
ao mesmo tempo na `main`.

| Verificação | Resultado |
|---|---|
| `actionlint` | ✅ |
| `sed` altera somente a linha `newTag` | ✅ |
| PR #9 | ✅ 20 checks; job `gitops` *skipped* nos 5 (em PR nada é publicado) |
| Pipelines na `main` | ✅ 5 de 5, com os 5 estágios (Build & Test, Lint, Security, Docker, GitOps) |
| Imagens no ECR | ✅ `v1.0.0-a13ec71` nos 5 repositórios |
| Commits do bot | ✅ 5 commits `gitops(<serviço>): imagem v1.0.0-a13ec71`, sem conflito entre pipelines simultâneos |
| ArgoCD | ✅ 5 Applications `Synced` / `Healthy` na nova revisão, sem intervenção |
| Deployments | ✅ os 5 com a imagem `v1.0.0-a13ec71` |
| Imagens novas no cluster | ✅ pods rodando como usuário `app` (sem root) |
| `scripts/test-services.sh` | ✅ todos os testes (health ×5, 401 sem chave, flag 201, regra 201, avaliação 200, evento no DynamoDB) |
