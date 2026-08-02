#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_DIR}"

# shellcheck source=/dev/null
source .env

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_DIR="${PROJECT_DIR}/backups/${TIMESTAMP}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

mkdir -p "${BACKUP_DIR}"

# Containers que precisam ser garantidamente rodando para o dump do banco
GITEA_RUNNING=false
LINKWARDEN_RUNNING=false

cleanup() {
    local exit_code=$?
    info "Finalizando backup (código de saída: ${exit_code})..."
    # Reinicia serviços se necessário – eles estavam rodando via Sablier
    # não precisamos de ação aqui; apenas garantimos que o manifesto foi escrito
    if [[ -d "${BACKUP_DIR}" ]]; then
        echo "exit_code=${exit_code}" >> "${BACKUP_DIR}/manifest.txt"
    fi
    if [[ ${exit_code} -ne 0 ]]; then
        error "Backup FALHOU. Verifique ${BACKUP_DIR}/manifest.txt"
    fi
}
trap cleanup EXIT

info "Iniciando backup – ${TIMESTAMP}"
info "Destino: ${BACKUP_DIR}"

# ── Manifesto ─────────────────────────────────────────────────────────────────
cat > "${BACKUP_DIR}/manifest.txt" <<EOF
timestamp=${TIMESTAMP}
host=$(hostname)
project_dir=${PROJECT_DIR}
EOF

# ── Acorda os containers para o dump ─────────────────────────────────────────
wake_container() {
    local name="$1"
    if ! docker inspect --format '{{.State.Running}}' "${name}" 2>/dev/null | grep -q true; then
        info "Iniciando container ${name} para backup..."
        docker start "${name}"
        sleep 5
        echo "started_for_backup=true" >> "${BACKUP_DIR}/manifest.txt"
    fi
}

# ── Dump Gitea PostgreSQL ─────────────────────────────────────────────────────
info "Fazendo dump do banco Gitea (PostgreSQL)..."
wake_container homelab-gitea-db
docker exec homelab-gitea-db \
    pg_dump -U "${GITEA_DB_USER:-gitea}" -d "${GITEA_DB_NAME:-gitea}" \
    | gzip > "${BACKUP_DIR}/gitea-postgres.sql.gz"
info "  → gitea-postgres.sql.gz"

# ── Dump Linkwarden PostgreSQL ────────────────────────────────────────────────
info "Fazendo dump do banco Linkwarden (PostgreSQL)..."
wake_container homelab-linkwarden-db
docker exec homelab-linkwarden-db \
    pg_dump -U "${LINKWARDEN_DB_USER:-linkwarden}" -d "${LINKWARDEN_DB_NAME:-linkwarden}" \
    | gzip > "${BACKUP_DIR}/linkwarden-postgres.sql.gz"
info "  → linkwarden-postgres.sql.gz"

# ── Backup de dados persistentes ──────────────────────────────────────────────
backup_dir() {
    local label="$1"
    local src="$2"
    local dest="${BACKUP_DIR}/${label}.tar.gz"
    if [[ -d "${src}" ]]; then
        info "Arquivando ${src}..."
        tar -czf "${dest}" -C "$(dirname "${src}")" "$(basename "${src}")"
        info "  → ${label}.tar.gz"
    else
        warn "Diretório não encontrado, ignorando: ${src}"
    fi
}

backup_dir "gitea-data"         /srv/homelab/gitea/data
backup_dir "vaultwarden-data"   /srv/homelab/vaultwarden/data
backup_dir "linkwarden-data"    /srv/homelab/linkwarden/data
backup_dir "caddy-data"         /srv/homelab/caddy/data

# ── Finaliza manifesto ────────────────────────────────────────────────────────
{
    echo "files="
    ls -1 "${BACKUP_DIR}"
} >> "${BACKUP_DIR}/manifest.txt"

echo ""
info "Backup concluído com sucesso: ${BACKUP_DIR}"
echo ""
du -sh "${BACKUP_DIR}"
echo ""
info "Para restaurar: ./scripts/restore.sh ${BACKUP_DIR}"
