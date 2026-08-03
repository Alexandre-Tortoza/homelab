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
DATA_DIR="${DATA_DIR:-/mnt/hd2/homelab}"
KOPIA_REPOSITORY_PATH="${KOPIA_REPOSITORY_PATH:-/mnt/hd2/backups}"

# ── Valida HD secundário ──────────────────────────────────────────────────────
info "Verificando HD secundário em ${DATA_DIR}..."

MOUNT_PARENT="$(dirname "${DATA_DIR}")"
if [[ ! -d "${MOUNT_PARENT}" ]]; then
    die "Ponto de montagem não encontrado: ${MOUNT_PARENT}
Monte o HD secundário antes de continuar. Exemplo:
  sudo mount /dev/sdX1 ${MOUNT_PARENT}
Ou adicione uma entrada em /etc/fstab para montagem automática."
fi

if ! mountpoint -q "${MOUNT_PARENT}" 2>/dev/null; then
    warn "ATENÇÃO: ${MOUNT_PARENT} não parece ser um ponto de montagem separado."
    warn "Certifique-se de que DATA_DIR=${DATA_DIR} aponta para o HD secundário."
    warn "Continuar criará os diretórios no disco atual."
    read -r -p "Continuar mesmo assim? [s/N] " CONFIRM
    [[ "${CONFIRM,,}" == "s" ]] || die "Abortado. Monte o HD secundário e tente novamente."
fi

# ── Diretórios persistentes ───────────────────────────────────────────────────
info "Criando diretórios em ${DATA_DIR}..."

if [[ "$EUID" -ne 0 ]]; then
    warn "Usando sudo para criar diretórios..."
    SUDO="sudo"
else
    SUDO=""
fi

$SUDO mkdir -p \
    "${DATA_DIR}/caddy/data" \
    "${DATA_DIR}/caddy/config" \
    "${DATA_DIR}/gitea/data" \
    "${DATA_DIR}/gitea/postgres" \
    "${DATA_DIR}/vaultwarden/data" \
    "${DATA_DIR}/linkwarden/data" \
    "${DATA_DIR}/linkwarden/postgres" \
    "${DATA_DIR}/actual/data" \
    "${DATA_DIR}/mealie/data" \
    "${DATA_DIR}/mealie/postgres" \
    "${DATA_DIR}/immich/library" \
    "${DATA_DIR}/immich/model-cache" \
    "${DATA_DIR}/immich/postgres" \
    "${DATA_DIR}/grafana/data" \
    "${DATA_DIR}/prometheus/data" \
    "${DATA_DIR}/kopia/config" \
    "${DATA_DIR}/kopia/cache" \
    "${DATA_DIR}/kopia/logs" \
    "${DATA_DIR}/sql-dumps" \
    "${KOPIA_REPOSITORY_PATH}"

# Gitea data: propriedade do usuário host
$SUDO chown -R "${PUID}:${PGID}" "${DATA_DIR}/gitea/data"
$SUDO chmod -R 750 "${DATA_DIR}/gitea/data"

# PostgreSQL Alpine usa UID 70
$SUDO chown 70:70 "${DATA_DIR}/gitea/postgres"
$SUDO chmod 700 "${DATA_DIR}/gitea/postgres"
$SUDO chown 70:70 "${DATA_DIR}/linkwarden/postgres"
$SUDO chmod 700 "${DATA_DIR}/linkwarden/postgres"
$SUDO chown 70:70 "${DATA_DIR}/mealie/postgres"
$SUDO chmod 700 "${DATA_DIR}/mealie/postgres"

# Vaultwarden
$SUDO chmod 750 "${DATA_DIR}/vaultwarden/data"

# Linkwarden data
$SUDO chown -R "${PUID}:${PGID}" "${DATA_DIR}/linkwarden/data"
$SUDO chmod -R 750 "${DATA_DIR}/linkwarden/data"

# Caddy
$SUDO chmod 750 "${DATA_DIR}/caddy/data" "${DATA_DIR}/caddy/config"

# Kopia
$SUDO chmod 750 "${DATA_DIR}/kopia/config" "${DATA_DIR}/kopia/cache" "${DATA_DIR}/kopia/logs"
$SUDO chmod 750 "${KOPIA_REPOSITORY_PATH}"

info "Diretórios criados com sucesso em ${DATA_DIR}."

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
check_var "KOPIA_SERVER_PASSWORD"
check_var "KOPIA_PASSWORD"

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
