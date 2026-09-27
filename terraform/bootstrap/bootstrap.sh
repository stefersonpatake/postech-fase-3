#!/usr/bin/env bash
#
# bootstrap.sh
#
# Cria (ou ajusta, se já existir) o bucket S3 que guarda o state remoto das
# camadas terraform/infra e terraform/platform.
#
# Por que não Terraform? No AWS Academy um SCP nega s3:GetBucketObjectLockConfiguration,
# e o provider AWS lê essa configuração em todo refresh de aws_s3_bucket — o recurso
# fica impossível de gerenciar. O bucket de state é pré-requisito do Terraform de
# qualquer forma ("ovo e galinha"), então é criado por este script idempotente.
#
# Uso:
#   ./terraform/bootstrap/bootstrap.sh
#   PROJECT=outro REGION=us-west-2 ./terraform/bootstrap/bootstrap.sh

set -euo pipefail

PROJECT="${PROJECT:-togglemaster}"
REGION="${REGION:-us-east-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="${PROJECT}-tfstate-${ACCOUNT_ID}"

if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  echo "ℹ️  Bucket $BUCKET já existe, garantindo configurações..."
else
  echo "🪣 Criando bucket $BUCKET em $REGION ..."
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
  fi
fi

echo "🔁 Versionamento (permite recuperar states anteriores)"
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

echo "🔒 Criptografia SSE-S3"
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

echo "🚫 Bloqueio de acesso público"
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "🏷️  Tags"
aws s3api put-bucket-tagging --bucket "$BUCKET" \
  --tagging "TagSet=[{Key=Project,Value=$PROJECT},{Key=ManagedBy,Value=bootstrap.sh}]"

echo
echo "✅ Bucket de state pronto: $BUCKET"
echo "   Use no backend \"s3\": bucket = \"$BUCKET\", region = \"$REGION\", use_lockfile = true"
