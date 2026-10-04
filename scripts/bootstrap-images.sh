#!/usr/bin/env bash
#
# bootstrap-images.sh
#
# Carga inicial das imagens no ECR, para o primeiro sync do ArgoCD (ou após
# recriar o ambiente com infra-up.sh, já que o destroy apaga os repositórios).
# No dia a dia quem constrói e publica as imagens é o pipeline de CI.
#
# Para cada serviço: build linux/amd64 → push com a tag v1.0.0-<sha7 do commit> →
# atualiza newTag em gitops/apps/<serviço>/kustomization.yaml.
# Depois é preciso commitar e enviar a alteração de gitops/ para o branch
# monitorado pelo ArgoCD.
#
# Uso:
#   ./scripts/bootstrap-images.sh                       # os 5 serviços
#   ./scripts/bootstrap-images.sh auth-service          # só um

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT="${PROJECT:-togglemaster}"
REGION="${AWS_REGION:-us-east-1}"
SERVICES=("$@")
[ ${#SERVICES[@]} -eq 0 ] && SERVICES=(auth-service flag-service targeting-service evaluation-service analytics-service)

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
TAG="v1.0.0-$(git rev-parse --short=7 HEAD)"

echo "🔐 Login no ECR ($REGISTRY)"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY" >/dev/null

for svc in "${SERVICES[@]}"; do
  repo="$PROJECT/$svc"
  image="$REGISTRY/$repo:$TAG"
  echo; echo "━━━ $svc → $TAG ━━━"

  # Tags são imutáveis no ECR: se já existe, não reconstrói.
  if aws ecr describe-images --repository-name "$repo" --image-ids imageTag="$TAG" --region "$REGION" >/dev/null 2>&1; then
    echo "⏭️  Imagem já existe no ECR."
  else
    docker buildx build --platform linux/amd64 --provenance=false -t "$image" --push "./$svc"
  fi

  perl -pi -e "s|newTag: .*|newTag: $TAG|" "gitops/apps/$svc/kustomization.yaml"
  echo "✅ gitops/apps/$svc/kustomization.yaml → $TAG"
done

echo
echo "Próximo passo: commitar e enviar gitops/ para o branch monitorado pelo ArgoCD."
