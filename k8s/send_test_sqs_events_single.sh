#!/usr/bin/env bash
set -euo pipefail

# Mesmo teste de carga que send_test_sqs_events.sh, mas enviando uma
# mensagem por chamada (send-message) em vez de em lotes (send-message-batch).
# Serve para comparar a sobrecarga (nº de chamadas de API, tempo total)
# entre as duas abordagens.
#
# Formato da mensagem igual ao publicado pelo evaluation-service
# (evaluation-service/sqs.go) e esperado pelo analytics-service
# (analytics-service/app.py):
#   { "user_id": "...", "flag_name": "...", "result": true|false, "timestamp": "..." }

export AWS_PAGER=""

QUEUE_URL="${SQS_QUEUE_URL:-https://sqs.us-east-1.amazonaws.com/785619296841/toggle-master-events}"
REGION="${AWS_REGION:-us-east-1}"
TOTAL="${TOTAL:-1000}"
PROGRESS_EVERY="${PROGRESS_EVERY:-50}"

echo "Enviando $TOTAL mensagens de teste (uma por chamada) para: $QUEUE_URL"

start_time=$SECONDS
failures=0

for ((i = 1; i <= TOTAL; i++)); do
  now="$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")"
  body=$(jq -nc \
    --arg user_id "user-$i" \
    --arg flag_name "enable-new-checkout" \
    --argjson result true \
    --arg timestamp "$now" \
    '{user_id: $user_id, flag_name: $flag_name, result: $result, timestamp: $timestamp}')

  if ! aws sqs send-message \
    --queue-url "$QUEUE_URL" \
    --message-body "$body" \
    --region "$REGION" \
    --output json >/dev/null; then
    ((failures++)) || true
    echo "Falha ao enviar mensagem $i"
  fi

  if ((i % PROGRESS_EVERY == 0 || i == TOTAL)); then
    echo "Enviadas $i/$TOTAL..."
  fi
done

elapsed=$((SECONDS - start_time))
echo "Concluído em ${elapsed}s ($failures falhas)."
