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
