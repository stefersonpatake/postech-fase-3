#!/usr/bin/env bash
#
# infra-down.sh
#
# Derruba o ambiente na ordem inversa da criação (platform → infra) para parar
# a cobrança entre sessões de trabalho. O bucket de state NÃO é removido: ele
# guarda o histórico e custa praticamente zero.
#
# Uso:
#   ./scripts/infra-down.sh            # pede confirmação em cada camada
#   ./scripts/infra-down.sh -y         # sem confirmação
#   ./scripts/infra-down.sh --dry-run  # só mostra o que seria destruído

set -euo pipefail
source "$(dirname "$0")/_layers.sh"

AUTO_APPROVE=""
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    -y|--yes)  AUTO_APPROVE="-auto-approve" ;;
    --dry-run) DRY_RUN=true ;;
    *) echo "Opção desconhecida: $arg"; exit 1 ;;
  esac
done

check_credentials

# Load balancers criados pelo AWS Load Balancer Controller (a partir de Ingress) não
# estão no state do Terraform. Se o controller for removido antes deles, os ALBs ficam
# órfãos e a exclusão da VPC trava. Por isso, antes de destruir:
#   1. remove as Applications do ArgoCD (senão ele recria os Ingress);
#   2. apaga todos os Ingress e espera o controller remover os ALBs.
cleanup_cluster_load_balancers() {
  local cluster="${PROJECT:-togglemaster}-eks"
  aws eks describe-cluster --name "$cluster" >/dev/null 2>&1 || return 0
  aws eks update-kubeconfig --name "$cluster" >/dev/null 2>&1 || return 0
  kubectl get ns >/dev/null 2>&1 || return 0

  echo; echo "━━━ limpeza de load balancers do cluster ━━━"
  if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
    echo "🧹 Removendo Applications do ArgoCD..."
    kubectl delete applications.argoproj.io --all -n argocd --timeout=180s 2>/dev/null || true
  fi
  if [ -n "$(kubectl get ingress -A --no-headers 2>/dev/null)" ]; then
    echo "🧹 Removendo Ingress (o controller apaga os ALBs)..."
    kubectl delete ingress --all -A --timeout=300s || true
  fi
  echo "✅ Nenhum Ingress restante."
}

$DRY_RUN || cleanup_cluster_load_balancers

for (( i=${#LAYERS[@]}-1; i>=0; i-- )); do
  layer="${LAYERS[$i]}"
  echo; echo "━━━ $layer ━━━"
  if ! layer_has_code "$layer"; then
    echo "⏭️  Sem código Terraform ainda, ignorando."
    continue
  fi
  layer_init "$layer"
  if [ "$(layer_resource_count "$layer")" -eq 0 ]; then
    echo "⏭️  Nenhum recurso no state, nada a destruir."
    continue
  fi
  if $DRY_RUN; then
    terraform -chdir="$TF_DIR/$layer" plan -destroy -input=false
  else
    terraform -chdir="$TF_DIR/$layer" destroy -input=false $AUTO_APPROVE
  fi
done

echo
if $DRY_RUN; then
  echo "ℹ️  Dry-run: nada foi destruído."
else
  echo "✅ Ambiente derrubado. Recursos restantes por camada:"
  for layer in "${LAYERS[@]}"; do
    layer_has_code "$layer" && echo "   $layer: $(layer_resource_count "$layer")"
  done
  echo "   (bucket de state preservado; para recriar: ./scripts/infra-up.sh)"
fi
