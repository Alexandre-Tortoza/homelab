#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_DIR}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }

echo ""
warn "Este script atualiza os containers para as versões definidas em .env"
warn "Ele NÃO altera automaticamente as versões fixadas no .env"
echo ""
warn "Para atualizar uma versão, edite .env manualmente:"
echo "  GITEA_IMAGE=gitea/gitea:X.Y.Z"
echo "  VAULTWARDEN_IMAGE=vaultwarden/server:X.Y.Z"
echo "  etc."
echo ""
read -r -p "Continuar com as versões atuais do .env? [s/N] " CONFIRM
[[ "${CONFIRM,,}" == "s" ]] || { echo "Cancelado."; exit 0; }

# ── Backup antes de atualizar ─────────────────────────────────────────────────
info "Executando backup preventivo..."
"${SCRIPT_DIR}/backup.sh"

# ── Pull das novas imagens ────────────────────────────────────────────────────
info "Baixando novas imagens..."
docker compose pull --ignore-pull-failures

info "Reconstruindo imagem do Caddy..."
docker compose build caddy

# ── Recria os containers ──────────────────────────────────────────────────────
info "Recriando containers..."
docker compose up -d --force-recreate caddy sablier

# Aguarda os bancos e apps escalados pelo Sablier ficarem prontos quando acessados
info "Gateway atualizado. Containers de aplicação serão recriados pelo Sablier sob demanda."

echo ""
info "Atualização concluída."
warn "Imagens antigas não foram removidas. Para limpar manualmente: docker image prune"
echo ""
docker compose ps
