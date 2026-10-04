#!/usr/bin/env bash
#
# infra-up.sh
#
# Sobe o ambiente inteiro na ordem correta:
#   1. bucket de state (terraform/bootstrap/bootstrap.sh)
#   2. terraform/infra     (rede, EKS, bancos, SQS, ECR, secrets)
#   3. terraform/platform  (ALB Controller, ESO, ArgoCD)
# Camadas ainda sem código Terraform são ignoradas.
#
# Uso:
#   ./scripts/infra-up.sh            # pede confirmação em cada camada
#   ./scripts/infra-up.sh -y         # sem confirmação
#   ./scripts/infra-up.sh --dry-run  # só mostra o plan, não altera nada

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

if ! $DRY_RUN; then
  echo; echo "━━━ bootstrap (bucket de state) ━━━"
  "$TF_DIR/bootstrap/bootstrap.sh"
fi

for layer in "${LAYERS[@]}"; do
  echo; echo "━━━ $layer ━━━"
  if ! layer_has_code "$layer"; then
    echo "⏭️  Sem código Terraform ainda, ignorando."
    continue
  fi
  layer_init "$layer"
  if $DRY_RUN; then
    terraform -chdir="$TF_DIR/$layer" plan -input=false
  else
    terraform -chdir="$TF_DIR/$layer" apply -input=false $AUTO_APPROVE
  fi
done

echo
if $DRY_RUN; then
  echo "ℹ️  Dry-run: nada foi alterado."
else
  echo "✅ Ambiente no ar:"
  for layer in "${LAYERS[@]}"; do
    layer_has_code "$layer" && echo "   $layer: $(layer_resource_count "$layer") recursos"
  done
fi
