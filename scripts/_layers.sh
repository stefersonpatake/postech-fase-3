#!/usr/bin/env bash
#
# _layers.sh — funções compartilhadas por infra-up.sh e infra-down.sh.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"

# Ordem de criação. A destruição usa a ordem inversa.
LAYERS=(infra platform)

check_credentials() {
  aws sts get-caller-identity >/dev/null 2>&1 || {
    echo "❌ Credenciais AWS inválidas/expiradas. Atualize ~/.aws/credentials com o token do Academy."
    exit 1
  }
  echo "🔑 Conta AWS: $(aws sts get-caller-identity --query Account --output text)"
}

# Uma camada só é processada se já tiver código Terraform.
layer_has_code() {
  compgen -G "$TF_DIR/$1/*.tf" >/dev/null
}

layer_init() {
  terraform -chdir="$TF_DIR/$1" init -input=false >/dev/null
}

layer_resource_count() {
  terraform -chdir="$TF_DIR/$1" state list 2>/dev/null | grep -vc '^data\.' || true
}
