#!/usr/bin/env bash
#
# bootstrap-service-api-key.sh
#
# A SERVICE_API_KEY usada pelo evaluation-service para chamar flag-service e
# targeting-service é emitida pelo auth-service em runtime (POST /admin/keys) e
# fica gravada (hash) no banco do auth. Este script:
#   1. pede uma chave nova ao auth-service, de dentro do próprio pod (a MASTER_KEY
#      nunca sai do cluster);
#   2. grava a chave no AWS Secrets Manager (togglemaster/evaluation-service-api-key);
#   3. força o External Secrets Operator a ressincronizar e reinicia o evaluation-service.
#
# Rodar uma vez após o primeiro deploy, e de novo sempre que o ambiente for
# recriado (o banco do auth nasce vazio).
#
# Uso:
#   ./scripts/bootstrap-service-api-key.sh           # só age se a chave ainda for "PENDENTE"
#   ./scripts/bootstrap-service-api-key.sh --force   # emite uma chave nova mesmo assim

set -euo pipefail

PROJECT="${PROJECT:-togglemaster}"
SECRET_ID="$PROJECT/evaluation-service-api-key"
FORCE=false
[ "${1:-}" = "--force" ] && FORCE=true

current=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ID" --query SecretString --output text \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["SERVICE_API_KEY"])')

if [ "$current" != "PENDENTE" ] && ! $FORCE; then
  echo "ℹ️  $SECRET_ID já tem uma chave. Use --force para emitir outra."
  exit 0
fi

echo "⏳ Aguardando o auth-service ficar disponível..."
kubectl rollout status deployment/auth-service -n auth --timeout=180s >/dev/null

echo "🔑 Emitindo chave no auth-service..."
response=$(kubectl exec -n auth deploy/auth-service -- sh -c '
  wget -qO- \
    --header "Authorization: Bearer $MASTER_KEY" \
    --header "Content-Type: application/json" \
    --post-data "{\"name\":\"evaluation-service\"}" \
    http://localhost:8001/admin/keys')

payload=$(printf '%s' "$response" | python3 -c '
import sys, json
key = json.load(sys.stdin)["key"]
print(json.dumps({"SERVICE_API_KEY": key}))')

echo "☁️  Gravando no Secrets Manager ($SECRET_ID)..."
aws secretsmanager put-secret-value --secret-id "$SECRET_ID" --secret-string "$payload" >/dev/null

echo "🔄 Ressincronizando o ExternalSecret e reiniciando o evaluation-service..."
kubectl annotate externalsecret evaluation-service-secret -n evaluation \
  force-sync="$(date +%s)" --overwrite >/dev/null
sleep 5
kubectl rollout restart deployment/evaluation-service -n evaluation >/dev/null
kubectl rollout status deployment/evaluation-service -n evaluation --timeout=180s >/dev/null

echo "✅ SERVICE_API_KEY emitida e aplicada ao evaluation-service."
