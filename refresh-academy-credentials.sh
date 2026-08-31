#!/usr/bin/env bash
#
# refresh-academy-credentials.sh
#
# Atualiza o secret "aws-credentials-file" (kube-system) com o conteúdo atual
# do seu arquivo de credenciais local, dispara manualmente o CronJob
# "credentials-refresher" pra propagar isso para os secrets dos serviços
# (targeting-service, analytics-service) e para o aws-load-balancer-controller,
# e confere o resultado dentro dos pods.
#
# Uso:
#   ./refresh-academy-credentials.sh
#   ./refresh-academy-credentials.sh /caminho/alternativo/credentials
#
# Pré-requisito: o arquivo local (padrão ~/.aws/credentials) já precisa estar
# com o token NOVO copiado do AWS Academy Lab antes de rodar este script.

set -euo pipefail

CRED_FILE="${1:-$HOME/.aws/credentials}"
NAMESPACE="kube-system"
JOB_NAME="credentials-refresh-manual"

if [ ! -f "$CRED_FILE" ]; then
  echo "❌ Arquivo de credenciais não encontrado em: $CRED_FILE"
  echo "   Uso: $0 [caminho-do-arquivo-credentials]"
  exit 1
fi

echo "🔄 Atualizando secret aws-credentials-file (namespace $NAMESPACE) a partir de $CRED_FILE ..."
kubectl create secret generic aws-credentials-file \
  --from-file=credentials="$CRED_FILE" \
  -n "$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "🧹 Removendo execução manual anterior (se existir) ..."
kubectl delete job "$JOB_NAME" -n "$NAMESPACE" --ignore-not-found

echo "🚀 Disparando o CronJob credentials-refresher manualmente ..."
kubectl create job --from=cronjob/credentials-refresher "$JOB_NAME" -n "$NAMESPACE"

echo "⏳ Aguardando o Job terminar (timeout 90s) ..."
if kubectl wait --for=condition=complete "job/$JOB_NAME" -n "$NAMESPACE" --timeout=90s; then
  echo "✅ Job concluído com sucesso. Log:"
  kubectl logs -n "$NAMESPACE" "job/$JOB_NAME"
else
  echo "❌ Job não completou a tempo ou falhou. Log e eventos:"
  kubectl logs -n "$NAMESPACE" "job/$JOB_NAME" || true
  kubectl describe "job/$JOB_NAME" -n "$NAMESPACE" | tail -n 20
  exit 1
fi

echo
echo "🔎 Conferindo credenciais dentro dos pods ..."
echo "--- targeting-service ---"
kubectl exec -n targeting deploy/targeting-service -- env 2>/dev/null | grep -E "^AWS_" || echo "(não foi possível ler o env do pod)"
echo "--- analytics-service ---"
kubectl exec -n analytics deploy/analytics-service -- env 2>/dev/null | grep -E "^AWS_" || echo "(não foi possível ler o env do pod)"

echo
echo "🎉 Pronto. Se os valores acima baterem com o que está em $CRED_FILE, a propagação funcionou."