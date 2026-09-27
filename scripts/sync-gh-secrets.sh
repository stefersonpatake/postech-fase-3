#!/usr/bin/env bash
#
# sync-gh-secrets.sh
#
# Copia as credenciais temporárias do AWS Academy (perfil local) para os
# GitHub Secrets do repositório, usados pelos workflows de CI (login no ECR).
# Rodar a cada nova sessão do Learner Lab, depois de atualizar ~/.aws/credentials.
#
# Uso:
#   ./scripts/sync-gh-secrets.sh
#   AWS_PROFILE=outro ./scripts/sync-gh-secrets.sh
#   REPO=owner/repo ./scripts/sync-gh-secrets.sh

set -euo pipefail

PROFILE="${AWS_PROFILE:-default}"
REPO="${REPO:-stefersonpatake/postech-fase-3}"

command -v gh >/dev/null || { echo "❌ gh CLI não encontrado"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "❌ Rode 'gh auth login' primeiro"; exit 1; }

echo "🔎 Validando credenciais do perfil '$PROFILE' ..."
aws sts get-caller-identity --profile "$PROFILE" >/dev/null \
  || { echo "❌ Credenciais inválidas/expiradas. Atualize ~/.aws/credentials com o token do Academy."; exit 1; }

KEY_ID=$(aws configure get aws_access_key_id --profile "$PROFILE")
SECRET=$(aws configure get aws_secret_access_key --profile "$PROFILE")
TOKEN=$(aws configure get aws_session_token --profile "$PROFILE")
REGION=$(aws configure get region --profile "$PROFILE" || echo us-east-1)
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)

echo "🔐 Enviando secrets para $REPO ..."
gh secret set AWS_ACCESS_KEY_ID     --repo "$REPO" --body "$KEY_ID"
gh secret set AWS_SECRET_ACCESS_KEY --repo "$REPO" --body "$SECRET"
gh secret set AWS_SESSION_TOKEN     --repo "$REPO" --body "$TOKEN"
gh variable set AWS_REGION          --repo "$REPO" --body "${REGION:-us-east-1}"
gh variable set AWS_ACCOUNT_ID      --repo "$REPO" --body "$ACCOUNT_ID"

echo "✅ Secrets atualizados:"
gh secret list --repo "$REPO"
