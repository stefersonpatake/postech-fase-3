# Etapa 7 — Pipelines de CI com DevSecOps

Objetivo: um pipeline por microsserviço, executado a cada Pull Request e a cada push na `main`, com
build, testes, lint, análise de segurança (SCA + SAST), scan da imagem e publicação no ECR.
Uma vulnerabilidade crítica interrompe o pipeline antes de a imagem ser publicada.

## O que foi feito

### 1. Workflows (`.github/workflows/`)

| Arquivo | Papel |
|---|---|
| `_ci-go.yml` | Pipeline reutilizável (`workflow_call`) dos serviços Go |
| `_ci-python.yml` | Pipeline reutilizável dos serviços Python |
| `auth-service.yml`, `evaluation-service.yml` | Chamam `_ci-go.yml` |
| `flag-service.yml`, `targeting-service.yml`, `analytics-service.yml` | Chamam `_ci-python.yml` |
| `sonarcloud.yml` | Análise do repositório no SonarCloud |

Cada workflow de serviço só dispara quando algo muda na pasta do serviço (ou no próprio workflow),
via filtro `paths`. Alterar o `flag-service` não reconstrói os outros quatro.

### 2. Estágios (jobs) de cada pipeline

```
Build & Unit Test ─┐
                   ├─► Security Scan (SCA + SAST) ─► Docker Build, Scan & Push
Lint ──────────────┘
```

| Job | Go | Python |
|---|---|---|
| **Build & Unit Test** | `go build`, `go test -race -cover` | `pip install`, `compileall`, `pytest` |
| **Lint** | `golangci-lint` v2 (errcheck, govet, staticcheck, ineffassign, unused) | `flake8` |
| **Security – SCA** | Trivy `fs` sobre `go.mod` | Trivy `fs` sobre `requirements.txt` |
| **Security – SAST** | `gosec` | `bandit` |
| **Docker** | `docker build` → Trivy `image` → login ECR → push | idem |

O job seguinte só roda se o anterior passar (`needs`). O push no ECR acontece **apenas em push na
`main`**; em Pull Request a imagem é construída e escaneada, mas não publicada.

Tag da imagem: `v1.0.0-<7 primeiros caracteres do commit>` (ex.: `v1.0.0-a1b2c3d`).

### 3. Regra de bloqueio

| Ferramenta | Relatório (não bloqueia) | Bloqueia o pipeline |
|---|---|---|
| Trivy `fs` (dependências) | HIGH e CRITICAL | **CRITICAL** (`--exit-code 1`) |
| Trivy `image` (container) | HIGH e CRITICAL | **CRITICAL** com correção disponível (`--ignore-unfixed`) |
| gosec / bandit (código) | todos os achados | severidade **HIGH** |

gosec e bandit só têm três níveis (LOW/MEDIUM/HIGH); HIGH é o máximo e é tratado como "crítico".
Cada ferramenta roda duas vezes: uma para mostrar o relatório completo no log, outra com o limiar
de bloqueio. `--ignore-unfixed` na imagem evita bloquear por CVEs de pacotes do sistema para as
quais ainda não existe correção (não há ação possível).

### 4. SonarCloud

Workflow separado, analisando o repositório inteiro (um projeto: `stefersonpatake_postech-fase-3`).
Serve como painel de qualidade/segurança e adiciona o check "SonarCloud Code Analysis" ao PR
(quality gate). Cinco pipelines enviando análises para o mesmo projeto se sobrescreveriam, por isso
não está dentro dos pipelines por serviço. Configuração em `sonar-project.properties`.

Pré-requisito: **Automatic Analysis desligado** no projeto (Administration → Analysis Method).

### 5. Credenciais

- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` (secrets) e `AWS_REGION` (variable):
  gravados por `./scripts/sync-gh-secrets.sh`. **Expiram com a sessão do Academy**: se o push no ECR
  falhar com `ExpiredToken`, rodar o script de novo e reexecutar o job.
- `SONAR_TOKEN` (secret).
- Trivy é executado pela imagem oficial fixada (`ghcr.io/aquasecurity/trivy:0.74.0`), e as demais
  ferramentas têm versão fixada.

### 6. Mudanças no código dos serviços

O desafio pede os estágios "se houver" testes; não havia nenhum, nem `go.sum`. Para os pipelines
terem o que executar e passarem de forma legítima:

| Mudança | Motivo |
|---|---|
| Testes unitários: `*_test.go` (auth, evaluation) e `tests/` com pytest (flag, targeting, analytics) | Estágio de testes. Os testes Python substituem banco/AWS por mocks antes do import do `app.py` |
| `go.sum` versionado; Dockerfile com `go mod download` em vez de `go mod tidy` | Builds reprodutíveis e SCA sobre versões exatas |
| `.golangci.yml`, `.flake8`, `requirements-dev.txt`, `.dockerignore` | Configuração das ferramentas; testes ficam fora da imagem |
| Go 1.21 → **1.25**, Alpine 3.19 → **3.22** + `apk upgrade` | Trivy apontava CVE **CRITICAL** na stdlib do Go 1.21 (CVE-2025-68121) |
| Python 3.9 → **3.11** + `apt-get upgrade` | Trivy apontava **15 CRITICAL** em pacotes Debian (perl, openssl); Python 3.9 está sem suporte |
| Usuário não-root (`USER app`) nos 5 Dockerfiles | Apontado pelo SonarCloud (containers rodando como root) |
| evaluation-service: validação de `flag_name` + `url.PathEscape` | **gosec G704 (SSRF), severidade HIGH** — ver abaixo |
| evaluation-service: `io/ioutil` → `io`; erro do `Redis.Set` tratado | staticcheck / errcheck |
| targeting-service: import não usado; newline no fim dos `app.py` | flake8 |
| `docker-compose.yml`: `DB_PASSWORD` → `DB_PASS` | Os `entrypoint.sh` leem `DB_PASS`; o compose não subia auth/flag/targeting |

### 7. Vulnerabilidades reais encontradas pelo pipeline

1. **SSRF / path traversal no evaluation-service (gosec G704, HIGH)** — bloqueou o primeiro pipeline.
   O `flag_name` vinha da query string e era concatenado na URL das chamadas ao flag-service e ao
   targeting-service: `GET /evaluate?flag_name=../admin` alteraria o caminho da requisição interna.
   Correção: o nome é validado (`^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$`, senão HTTP 400) e escapado com
   `url.PathEscape`. Como a análise de fluxo do gosec não reconhece a validação, as 4 linhas ficaram
   marcadas com `#nosec G704` e a justificativa no próprio código.
2. **CVEs críticas nas imagens** (stdlib do Go 1.21; perl/openssl do Debian) — teriam bloqueado o
   job Docker; corrigidas atualizando as imagens base.
3. **Containers como root** (SonarCloud) — corrigido com usuário sem privilégios.

Achados HIGH que **não** bloqueiam e ficam registrados no log (dívida técnica): dependências como
Flask 2.2.2, Werkzeug 2.2.2, gunicorn 20.1.0, `golang.org/x/crypto` 0.20.0, `golang.org/x/net` 0.21.0.

## Como testar

### Localmente (mesmos comandos do pipeline)

```bash
# Go (auth-service, evaluation-service)
cd auth-service
docker run --rm -v "$PWD":/src -w /src golang:1.25-alpine go test -cover ./...
docker run --rm -v "$PWD":/src -w /src golangci/golangci-lint:v2.14.0 golangci-lint run ./...
trivy fs --scanners vuln --severity CRITICAL --exit-code 1 .

# Python (flag-service, targeting-service, analytics-service)
cd ../flag-service
docker run --rm -v "$PWD":/src -w /src python:3.11-slim sh -c \
  'pip install -q -r requirements.txt -r requirements-dev.txt && pytest -q && flake8 . && bandit -q -r . -x ./tests --severity-level high'
trivy fs --scanners vuln --severity CRITICAL --exit-code 1 .

# Imagem
docker build -t flag-service:ci . && trivy image --severity CRITICAL --ignore-unfixed --exit-code 1 flag-service:ci

# Aplicação inteira com as imagens novas
cd .. && docker compose up -d --build
for p in 8001 8002 8003 8004 8005; do curl -s -o /dev/null -w "$p %{http_code}\n" localhost:$p/health; done
docker compose down
```

### No GitHub

```bash
gh pr checks <número-do-PR>          # todos os jobs do PR
gh run list --limit 10               # execuções recentes
gh run view <id> --log-failed        # log do que falhou
```

### Pipeline falhando por segurança (cenário da demo)

```bash
git checkout -b demo/vulnerabilidade
echo "PyYAML==5.3.1" >> flag-service/requirements.txt     # CVE-2020-14343 (CRITICAL)
git commit -am "Dependência vulnerável" && git push -u origin demo/vulnerabilidade
gh pr create --fill
# Job "Security Scan (SCA + SAST)" falha em "SCA - Trivy fs (bloqueia se houver CRITICAL)";
# o job "Docker Build, Scan & Push" não é executado.

# Correção: remover a linha (ou usar PyYAML>=5.4), commit + push → pipeline passa.
```

## Resultado da validação (2026-10-04)

| Verificação | Resultado |
|---|---|
| `actionlint` nos workflows | ✅ sem erros |
| PR #8, 1ª execução | ⚠️ 20 de 22 checks: evaluation-service bloqueado pelo gosec (G704 HIGH) e quality gate do Sonar reprovado (root + cobertura) |
| PR #8, após correções | ✅ **22 de 22 checks**: 5 × (Build & Test, Lint, Security, Docker) + SonarCloud Scan + quality gate |
| Testes unitários | ✅ auth 3 testes, evaluation 6, flag 6, targeting 6, analytics 4 |
| Imagens novas (Trivy, CRITICAL) | ✅ 0 em todas as 5 (antes: 1 nas Go, 15 nas Python) |
| Imagens novas funcionando (`docker compose`) | ✅ `/health` 200 nos 5; usuário `app`; Python 3.11; 401 sem chave, flag 201, regra 201, `flag_name` inválido 400 |
| Regra de bloqueio do SCA | ✅ `PyYAML==5.3.1` → Trivy acusa CVE-2020-14343 CRITICAL (simulado localmente) |
| Push no ECR | ⏳ só ocorre em push na `main`: será exercitado no merge deste PR |

## Observações

- No merge, os 5 pipelines publicam imagens `v1.0.0-<sha do merge>` no ECR, mas o cluster **ainda não
  as usa**: a atualização da tag em `gitops/` é a Etapa 8.
- Custos: GitHub Actions e SonarCloud são gratuitos para repositório público.
