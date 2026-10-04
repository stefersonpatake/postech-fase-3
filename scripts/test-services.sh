#!/usr/bin/env bash
#
# test-services.sh
#
# Teste de fumaça + ponta a ponta dos 5 microsserviços, pelo ALB:
#   1. /health de cada serviço (valida ALB, roteamento por caminho e pods)
#   2. cria uma flag (flag-service) e uma regra (targeting-service)
#   3. avalia a flag (evaluation-service → Redis, flag, targeting, SQS)
#   4. confere que o evento chegou ao DynamoDB (analytics-service ← SQS)
#
# Uso: ./scripts/test-services.sh

set -uo pipefail

PROJECT="${PROJECT:-togglemaster}"
TABLE="${TABLE:-ToggleMasterAnalytics}"
FAILED=0

ALB=$(kubectl get ingress auth-service -n auth -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
[ -z "$ALB" ] && { echo "❌ Ingress ainda sem endereço de ALB"; exit 1; }
echo "🌐 ALB: http://$ALB"

check() { # check <descrição> <esperado> <obtido>
  if [ "$2" = "$3" ]; then echo "   ✅ $1 ($3)"; else echo "   ❌ $1 (esperado $2, obtido $3)"; FAILED=1; fi
}

echo; echo "1) Health"
for path in auth flags targeting evaluation analytics; do
  check "/$path/health" 200 "$(curl -s -o /dev/null -m 10 -w '%{http_code}' "http://$ALB/$path/health")"
done

API_KEY=$(aws secretsmanager get-secret-value --secret-id "$PROJECT/evaluation-service-api-key" \
  --query SecretString --output text | python3 -c 'import sys,json; print(json.load(sys.stdin)["SERVICE_API_KEY"])')
if [ "$API_KEY" = "PENDENTE" ]; then
  echo; echo "❌ SERVICE_API_KEY ainda não emitida: rode ./scripts/bootstrap-service-api-key.sh"; exit 1
fi

FLAG="smoke-test-$(date +%s)"
AUTHZ="Authorization: Bearer $API_KEY"

echo; echo "2) Autenticação e cadastro (flag: $FLAG)"
flag_json=$(printf '{"name":"%s","description":"teste de fumaça","is_enabled":true}' "$FLAG")
rule_json=$(printf '{"flag_name":"%s","is_enabled":true,"rules":{"type":"PERCENTAGE","value":100}}' "$FLAG")

post() { # post <caminho> <json>
  curl -s -o /dev/null -m 10 -w '%{http_code}' -X POST "http://$ALB$1" \
    -H "$AUTHZ" -H 'Content-Type: application/json' -d "$2"
}

check "GET /flags/flags sem chave é rejeitado" 401 \
  "$(curl -s -o /dev/null -m 10 -w '%{http_code}' "http://$ALB/flags/flags")"
check "POST /flags/flags" 201 "$(post /flags/flags "$flag_json")"
check "POST /targeting/rules" 201 "$(post /targeting/rules "$rule_json")"

echo; echo "3) Avaliação"
before=$(aws dynamodb scan --table-name "$TABLE" --select COUNT --query Count --output text)
resp=$(curl -s -m 10 -w '\n%{http_code}' "http://$ALB/evaluation/evaluate?user_id=user-123&flag_name=$FLAG")
check "GET /evaluation/evaluate" 200 "$(printf '%s' "$resp" | tail -1)"
echo "   resposta: $(printf '%s' "$resp" | head -1)"

echo; echo "4) Evento no DynamoDB (evaluation → SQS → analytics → DynamoDB)"
after=$before
for _ in $(seq 1 12); do
  after=$(aws dynamodb scan --table-name "$TABLE" --select COUNT --query Count --output text)
  [ "$after" -gt "$before" ] && break
  sleep 5
done
if [ "$after" -gt "$before" ]; then echo "   ✅ itens na tabela: $before → $after"; else echo "   ❌ nenhum item novo ($before)"; FAILED=1; fi

echo
[ $FAILED -eq 0 ] && echo "✅ Todos os testes passaram" || { echo "❌ Houve falhas"; exit 1; }
