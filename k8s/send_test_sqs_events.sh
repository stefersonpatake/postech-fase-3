#!/usr/bin/env bash
set -euo pipefail

# Evita que o AWS CLI abra o pager (less) e fique esperando "q" a cada saída
export AWS_PAGER=""

# Envia um lote de mensagens de teste para a fila toggle-master-events,
# no mesmo formato que o evaluation-service publica (evaluation-service/sqs.go)
# e que o analytics-service espera consumir (analytics-service/app.py):
#   { "user_id": "...", "flag_name": "...", "result": true|false, "timestamp": "..." }
#
# SQS send-message-batch aceita no máximo 10 entries por chamada, então o
# total é enviado em lotes.

QUEUE_URL="${SQS_QUEUE_URL:-https://sqs.us-east-1.amazonaws.com/785619296841/toggle-master-events}"
REGION="${AWS_REGION:-us-east-1}"
TOTAL="${TOTAL:-1000}"
BATCH_SIZE=10  # limite máximo da API send-message-batch do SQS

echo "Enviando $TOTAL mensagens de teste para: $QUEUE_URL"

for ((start = 1; start <= TOTAL; start += BATCH_SIZE)); do
  end=$((start + BATCH_SIZE - 1))
  if ((end > TOTAL)); then
    end=$TOTAL
  fi

  entries="[]"
  for ((i = start; i <= end; i++)); do
    now="$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")"
    body=$(jq -nc \
      --arg user_id "user-$i" \
      --arg flag_name "enable-new-checkout" \
      --argjson result true \
      --arg timestamp "$now" \
      '{user_id: $user_id, flag_name: $flag_name, result: $result, timestamp: $timestamp}')
    entries=$(jq -c --arg id "$i" --arg body "$body" \
      '. + [{Id: $id, MessageBody: $body}]' <<<"$entries")
  done

  echo "Lote $start-$end..."
  failed=$(aws sqs send-message-batch \
    --queue-url "$QUEUE_URL" \
    --entries "$entries" \
    --region "$REGION" \
    --query 'Failed' \
    --output json)

  if [[ "$failed" != "null" && "$failed" != "[]" ]]; then
    echo "Falhas no lote $start-$end: $failed"
  fi
done

echo "Concluído."
