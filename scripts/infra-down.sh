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
  if [ -n "$(kubectl get ingress -A --no-headers 2>/dev/null)" ]; then
    echo "⚠️  Ainda há Ingress no cluster; as sobras serão removidas direto na AWS."
  else
    echo "✅ Nenhum Ingress restante."
  fi
}

# Rede de segurança para o que o controller deixar para trás (ALBs e security
# groups "k8s-*"): nada disso está no state, e qualquer sobra faz o DeleteVpc
# falhar com DependencyViolation depois de ~20 min de retry. Roda depois que a
# camada platform (e com ela o controller) já foi destruída, identificando os
# recursos pela tag elbv2.k8s.aws/cluster.
cleanup_orphan_lb_resources() {
  local cluster="${PROJECT:-togglemaster}-eks"
  local tag="elbv2.k8s.aws/cluster"
  local arn sg ref rules found=false

  for arn in $(aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerArn' --output text 2>/dev/null); do
    [ "$(aws elbv2 describe-tags --resource-arns "$arn" \
      --query "TagDescriptions[0].Tags[?Key=='$tag'].Value | [0]" --output text 2>/dev/null)" = "$cluster" ] || continue
    $found || { echo; echo "━━━ limpeza de órfãos do load balancer controller ━━━"; found=true; }
    echo "🧹 Removendo load balancer órfão: ${arn##*:loadbalancer/}"
    aws elbv2 delete-load-balancer --load-balancer-arn "$arn"
    aws elbv2 wait load-balancers-deleted --load-balancer-arns "$arn" || true
  done

  local sgs
  sgs=$(aws ec2 describe-security-groups --filters "Name=tag:$tag,Values=$cluster" \
    --query 'SecurityGroups[].GroupId' --output text 2>/dev/null)
  [ -n "$sgs" ] || return 0
  $found || { echo; echo "━━━ limpeza de órfãos do load balancer controller ━━━"; }

  # Regras de outros SGs (nós/cluster) que apontam para os órfãos impedem a exclusão.
  for sg in $sgs; do
    for ref in $(aws ec2 describe-security-groups --filters "Name=ip-permission.group-id,Values=$sg" \
      --query 'SecurityGroups[].GroupId' --output text); do
      rules=$(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$ref" \
        --query "SecurityGroupRules[?!IsEgress && ReferencedGroupInfo.GroupId=='$sg'].SecurityGroupRuleId" --output text)
      [ -n "$rules" ] && aws ec2 revoke-security-group-ingress --group-id "$ref" \
        --security-group-rule-ids $rules >/dev/null
    done
  done

  # As ENIs de um ALB recém-apagado levam alguns segundos para serem liberadas.
  local attempt
  for sg in $sgs; do
    echo "🧹 Removendo security group órfão: $sg"
    for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
      aws ec2 delete-security-group --group-id "$sg" >/dev/null 2>&1 && continue 2
      sleep 10
    done
    echo "⚠️  Não foi possível remover $sg; o destroy da VPC deve falhar."
  done
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
    [ "$layer" = infra ] && cleanup_orphan_lb_resources
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
