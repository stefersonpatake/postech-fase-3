#!/usr/bin/env bash
#
# test-data-connectivity.sh
#
# Valida, a partir de pods temporários no EKS, que o cluster alcança os recursos
# de dados criados pelo Terraform:
#   - 3 RDS PostgreSQL (usando as credenciais guardadas no Secrets Manager)
#   - ElastiCache Redis (TLS)
#   - SQS e DynamoDB (credenciais da role do nó, via IMDS)
# Nenhuma senha é impressa.
#
# Uso: ./scripts/test-data-connectivity.sh

set -uo pipefail

PROJECT="${PROJECT:-togglemaster}"
NS=default
FAILED=0

secret_field() { # secret_field <secret> <campo>
  aws secretsmanager get-secret-value --secret-id "$PROJECT/$1" --query SecretString --output text \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['$2'])"
}

run_pod() { # run_pod <nome> <imagem> [--env=...] -- <comando...>
  local name="$1" image="$2"; shift 2
  kubectl delete pod "$name" -n $NS --ignore-not-found >/dev/null 2>&1
  kubectl run "$name" -n $NS --image="$image" --restart=Never "$@" >/dev/null
  kubectl wait -n $NS --for=jsonpath='{.status.phase}'=Succeeded "pod/$name" --timeout=120s >/dev/null 2>&1
  local rc=$?
  kubectl logs -n $NS "$name" 2>&1 | sed 's/^/   /'
  kubectl delete pod "$name" -n $NS >/dev/null 2>&1
  [ $rc -eq 0 ] && echo "   ✅ ok" || { echo "   ❌ falhou"; FAILED=1; }
}

for svc in auth flag targeting; do
  echo "🐘 RDS $svc"
  run_pod "pg-test-$svc" postgres:17-alpine \
    --env="PGHOST=$(secret_field $svc-service DB_HOST)" \
    --env="PGUSER=$(secret_field $svc-service DB_USER)" \
    --env="PGDATABASE=$(secret_field $svc-service DB_NAME)" \
    --env="PGPASSWORD=$(secret_field $svc-service DB_PASS)" \
    --command -- psql -tA -c \
    "select 'db=' || current_database() || ' user=' || current_user || ' ssl=' || (select ssl from pg_stat_ssl where pid = pg_backend_pid())"
done

echo "🟥 Redis (TLS)"
run_pod redis-test redis:7-alpine \
  --command -- redis-cli --tls -u "$(secret_field evaluation-service REDIS_URL)" ping

QUEUE_URL=$(aws sqs get-queue-url --queue-name "$PROJECT-events" --query QueueUrl --output text)
echo "📨 SQS + 🗄️  DynamoDB (identidade do pod = role do nó)"
run_pod aws-test public.ecr.aws/aws-cli/aws-cli:latest \
  --env="AWS_DEFAULT_REGION=${AWS_REGION:-us-east-1}" --env="Q=$QUEUE_URL" \
  --command -- sh -c '
    aws sts get-caller-identity --query Arn --output text &&
    aws sqs send-message --queue-url "$Q" --message-body connectivity-test --query MessageId --output text &&
    R=$(aws sqs receive-message --queue-url "$Q" --wait-time-seconds 5 --query "Messages[0].ReceiptHandle" --output text) &&
    aws sqs delete-message --queue-url "$Q" --receipt-handle "$R" && echo "sqs: enviou, recebeu e apagou" &&
    aws dynamodb put-item --table-name ToggleMasterAnalytics --item "{\"event_id\":{\"S\":\"connectivity-test\"}}" &&
    aws dynamodb get-item --table-name ToggleMasterAnalytics --key "{\"event_id\":{\"S\":\"connectivity-test\"}}" --query Item.event_id.S --output text &&
    aws dynamodb delete-item --table-name ToggleMasterAnalytics --key "{\"event_id\":{\"S\":\"connectivity-test\"}}" && echo "dynamodb: gravou, leu e apagou"'

echo
[ $FAILED -eq 0 ] && echo "✅ Todos os testes de conectividade passaram" || { echo "❌ Houve falhas"; exit 1; }
