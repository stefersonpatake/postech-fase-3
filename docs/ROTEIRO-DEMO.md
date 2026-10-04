# Roteiro do vídeo de demonstração (até 20 minutos)

O desafio pede quatro demonstrações: **IaC**, **pipeline falhando no passo de segurança e depois
passando**, **pipeline atualizando a tag no GitOps** e **ArgoCD sincronizando sozinho**. Um único
fluxo cobre as três últimas: uma alteração no `flag-service`.

## Antes de gravar (não aparece no vídeo)

```bash
./scripts/infra-up.sh                     # se o ambiente estiver derrubado (~20 min)
./scripts/sync-gh-secrets.sh              # credenciais do Academy válidas no GitHub
for s in auth flag targeting evaluation analytics; do gh workflow run $s-service.yml; done   # só se recriou o ambiente
./scripts/bootstrap-service-api-key.sh    # só se recriou o ambiente
./scripts/test-services.sh                # tudo verde antes de começar
git checkout main && git pull
```

Deixar abertos:

| Janela | Conteúdo |
|---|---|
| Terminal 1 | raiz do repositório |
| Terminal 2 | `kubectl -n argocd port-forward svc/argocd-server 8080:80` |
| Navegador 1 | ArgoCD em `http://localhost:8080` (usuário `admin`; senha: comando em `docs/ETAPA-5.md`) |
| Navegador 2 | GitHub → aba **Actions** |
| Navegador 3 | Console AWS (VPC, EKS, RDS) |
| Editor | VS Code no repositório |

Dica: a sessão do Academy dura 4 horas. Gravar logo após renovar as credenciais.

## Parte 1 — Contexto (1 min)

- O problema: `kubectl apply` manual, credenciais em arquivos, vulnerabilidade em produção,
  ambiente recriado à mão em dias.
- A solução, mostrando o diagrama do `README.md`: Terraform → CI DevSecOps → GitOps com ArgoCD.

## Parte 2 — Infraestrutura como código (5 min)

1. **Estrutura** no editor: `terraform/modules/` (8 módulos), `terraform/infra/`, `terraform/platform/`.
2. **LabRole por data source** — `terraform/infra/data.tf` e `terraform/infra/eks.tf`
   (nenhum recurso de IAM criado).
3. **State remoto** — `terraform/infra/backend.tf` (`use_lockfile = true`) e:
   ```bash
   aws s3 ls s3://togglemaster-tfstate-583383233548 --recursive
   ```
4. **Plan e apply**:
   ```bash
   cd terraform/infra
   terraform plan          # "No changes": a AWS está igual ao código
   terraform state list | wc -l
   ```
   Para mostrar um `apply` rápido de verdade, alterar `node_desired_size` não é recomendado ao vivo
   (lento). Opção segura: adicionar uma tag em `default_tags` de `versions.tf`, `terraform apply`
   (atualiza tags em segundos) e depois desfazer. Alternativa: incluir no vídeo um trecho acelerado
   do `./scripts/infra-up.sh` gravado antes.
5. **Resultado no console AWS**: VPC e subnets, cluster EKS e nós, 3 instâncias RDS, ElastiCache,
   DynamoDB, SQS, 5 repositórios ECR, secrets no Secrets Manager.
6. **Plataforma também é código**: `terraform/platform/` (ArgoCD, External Secrets, ALB Controller) e
   ```bash
   kubectl get pods -n argocd
   ```

Frase de fechamento: recriar o ambiente inteiro leva ~20 minutos com um comando.

## Parte 3 — Pipeline DevSecOps falhando e passando (6 min)

1. Mostrar `.github/workflows/_ci-python.yml`: os 5 estágios e a regra de bloqueio.
2. Inserir uma dependência vulnerável:
   ```bash
   git checkout -b demo/dependencia-vulneravel
   echo "PyYAML==5.3.1" >> flag-service/requirements.txt
   git commit -am "flag-service: adiciona PyYAML" && git push -u origin demo/dependencia-vulneravel
   gh pr create --fill
   ```
3. Em **Actions**, abrir a execução do `flag-service`:
   - `Build & Unit Test` e `Lint` passam;
   - `Security Scan (SCA + SAST)` **falha** no passo *SCA - Trivy fs (bloqueia se houver CRITICAL)*:
     `PyYAML 5.3.1 — CVE-2020-14343 — CRITICAL`;
   - `Docker Build, Scan & Push` nem é executado. Nenhuma imagem foi publicada.
4. Corrigir:
   ```bash
   sed -i '' 's/PyYAML==5.3.1/PyYAML==6.0.2/' flag-service/requirements.txt
   git commit -am "flag-service: PyYAML sem vulnerabilidade crítica" && git push
   ```
5. Mostrar o pipeline do PR passando em todos os estágios (o estágio GitOps aparece como
   *skipped*: em PR nada é publicado).

Enquanto o pipeline roda (~3 min), comentar: SAST com gosec/bandit, SonarCloud no PR, scan da
imagem com Trivy, e as vulnerabilidades reais que o pipeline encontrou no projeto (SSRF no
evaluation-service, CVEs críticas nas imagens base) — `docs/ETAPA-7.md`.

## Parte 4 — GitOps: o pipeline atualiza a tag (3 min)

1. Mostrar a tag atual:
   ```bash
   grep newTag gitops/apps/flag-service/kustomization.yaml
   ```
2. Fazer o merge do PR (pela interface do GitHub).
3. Em **Actions**, a execução na `main`: agora com `Docker Build, Scan & Push` publicando no ECR e
   **`GitOps - atualizar tag da imagem`**.
4. Mostrar o commit do bot:
   ```bash
   git checkout main && git pull
   git log --oneline -3 -- gitops/
   grep newTag gitops/apps/flag-service/kustomization.yaml     # v1.0.0-<sha do merge>
   ```
5. Mostrar a imagem no ECR (console ou
   `aws ecr describe-images --repository-name togglemaster/flag-service --query 'imageDetails[].imageTags'`).

## Parte 5 — ArgoCD sincronizando sozinho (3 min)

1. Na UI do ArgoCD: as **5 Applications** `Synced` / `Healthy` (requisito: interface gerenciando os
   5 microsserviços).
2. Abrir `flag-service`: em até ~60 segundos após o commit do bot o ArgoCD detecta a nova revisão,
   cria o novo ReplicaSet e troca o pod. Mostrar a árvore de recursos e o *Last Sync* com o commit
   `gitops(flag-service): imagem v1.0.0-...`.
3. Confirmar no terminal:
   ```bash
   kubectl get applications -n argocd
   kubectl get deployment flag-service -n flags -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
   ./scripts/test-services.sh
   ```
4. (Opcional, 30 s) **Self-heal** — alteração manual é desfeita:
   ```bash
   kubectl scale deployment auth-service -n auth --replicas=3
   kubectl get deployment auth-service -n auth -w      # volta para 1 em segundos
   ```

## Parte 6 — Encerramento (1–2 min)

- Credenciais: nenhuma senha no Git. Mostrar `gitops/apps/auth-service/external-secret.yaml` e o
  secret no Secrets Manager (só os nomes das chaves).
- Recapitular: tudo que existe na AWS e no cluster está no repositório; deploy acontece por commit.
- Custos: `docs/CUSTOS.md`; derrubar com `./scripts/infra-down.sh`.

## Depois de gravar

```bash
git push origin --delete demo/dependencia-vulneravel
./scripts/infra-down.sh
```

## Se algo der errado durante a gravação

| Sintoma | Causa provável | Ação |
|---|---|---|
| Push no ECR falha com `ExpiredToken` | Sessão do Academy expirou | `./scripts/sync-gh-secrets.sh` e *Re-run failed jobs* |
| `kubectl` / `terraform` com `ExpiredToken` | Idem, credenciais locais | Atualizar `~/.aws/credentials` |
| `Error acquiring the state lock` | Terraform interrompido antes | `docs/ETAPA-1.md` → Solução de problemas |
| ArgoCD demora a detectar | Intervalo de verificação de 60s | Aguardar ou clicar em *Refresh* na Application |
| `evaluation` responde 502 | `SERVICE_API_KEY` não emitida após recriar o ambiente | `./scripts/bootstrap-service-api-key.sh` |
