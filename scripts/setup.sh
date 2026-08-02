#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

# ── Verificações ──────────────────────────────────────────────────────────────
info "Verificando pré-requisitos..."

if ! command -v docker &>/dev/null; then
    die "Docker não encontrado. Instale em: https://docs.docker.com/engine/install/"
fi

if docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
else
    die "Docker Compose não encontrado. Instale o plugin: https://docs.docker.com/compose/install/"
fi
info "Docker Compose disponível: $($COMPOSE_CMD version --short)"

# ── .env ──────────────────────────────────────────────────────────────────────
if [[ ! -f "${PROJECT_DIR}/.env" ]]; then
    info "Copiando .env.example para .env..."
    cp "${PROJECT_DIR}/.env.example" "${PROJECT_DIR}/.env"
    warn "Arquivo .env criado. EDITE-O antes de continuar: nano ${PROJECT_DIR}/.env"
else
    info ".env já existe – não sobrescrito."
fi

# Carrega variáveis do .env
set -a
# shellcheck source=/dev/null
source "${PROJECT_DIR}/.env"
set +a

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

# ── Diretórios persistentes ───────────────────────────────────────────────────
info "Criando diretórios em /srv/homelab/..."

BASE=/srv/homelab

if [[ "$EUID" -ne 0 ]]; then
    warn "Este script precisa de sudo para criar diretórios em /srv/. Tentando com sudo..."
    SUDO="sudo"
else
    SUDO=""
fi

$SUDO mkdir -p \
    "${BASE}/caddy/data" \
    "${BASE}/caddy/config" \
    "${BASE}/gitea/data" \
    "${BASE}/gitea/postgres" \
    "${BASE}/vaultwarden/data" \
    "${BASE}/linkwarden/data" \
    "${BASE}/linkwarden/postgres" \
    "${BASE}/adguard/work" \
    "${BASE}/adguard/conf"

# Gitea data: propriedade do usuário host
$SUDO chown -R "${PUID}:${PGID}" "${BASE}/gitea/data"
$SUDO chmod -R 750 "${BASE}/gitea/data"

# PostgreSQL Alpine usa UID 70
$SUDO chown 70:70 "${BASE}/gitea/postgres"
$SUDO chmod 700 "${BASE}/gitea/postgres"
$SUDO chown 70:70 "${BASE}/linkwarden/postgres"
$SUDO chmod 700 "${BASE}/linkwarden/postgres"

# Vaultwarden
$SUDO chmod 750 "${BASE}/vaultwarden/data"

# Linkwarden data
$SUDO chown -R "${PUID}:${PGID}" "${BASE}/linkwarden/data"
$SUDO chmod -R 750 "${BASE}/linkwarden/data"

# Caddy
$SUDO chmod 750 "${BASE}/caddy/data" "${BASE}/caddy/config"

# AdGuard
$SUDO chmod 750 "${BASE}/adguard/work" "${BASE}/adguard/conf"

info "Diretórios criados com sucesso."

# ── Rede Docker ───────────────────────────────────────────────────────────────
if ! docker network inspect homelab &>/dev/null; then
    info "Criando rede Docker 'homelab'..."
    docker network create homelab
else
    info "Rede 'homelab' já existe."
fi

# ── Imagem Caddy personalizada ────────────────────────────────────────────────
info "Construindo imagem do Caddy com plugin Sablier..."
$COMPOSE_CMD -f "${PROJECT_DIR}/compose.yaml" build caddy

# ── Validação do Compose ──────────────────────────────────────────────────────
info "Validando compose.yaml..."
$COMPOSE_CMD -f "${PROJECT_DIR}/compose.yaml" config --quiet && info "compose.yaml válido."

# ── Variáveis pendentes ───────────────────────────────────────────────────────
MISSING=()
check_var() {
    local val
    val=$(grep -E "^${1}=" "${PROJECT_DIR}/.env" | cut -d= -f2- || true)
    if [[ -z "$val" || "$val" == "CHANGE_ME" ]]; then
        MISSING+=("$1")
    fi
}

check_var "GITEA_DB_PASSWORD"
check_var "VAULTWARDEN_ADMIN_TOKEN"
check_var "LINKWARDEN_DB_PASSWORD"
check_var "LINKWARDEN_NEXTAUTH_SECRET"

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo ""
    warn "As seguintes variáveis precisam ser preenchidas no .env:"
    for v in "${MISSING[@]}"; do
        echo "  - $v"
    done
    echo ""
    warn "Execute: nano ${PROJECT_DIR}/.env"
    echo ""
    echo "Para gerar valores seguros:"
    echo "  openssl rand -base64 48"
    echo ""
else
    echo ""
    info "Todas as variáveis obrigatórias estão preenchidas."
    echo ""
    info "Próximo passo: ./scripts/start.sh"
fi
