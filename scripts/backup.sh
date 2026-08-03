#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_DIR}"

# shellcheck source=/dev/null
source .env

DATA_DIR="${DATA_DIR:-/mnt/hd2/homelab}"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
DUMP_DEST="${DATA_DIR}/sql-dumps/${TIMESTAMP}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

mkdir -p "${DUMP_DEST}"

cleanup() {
    local exit_code=$?
    info "Finalizando backup (código de saída: ${exit_code})..."
    if [[ -d "${DUMP_DEST}" ]]; then
        echo "exit_code=${exit_code}" >> "${DUMP_DEST}/manifest.txt"
    fi
    if [[ ${exit_code} -ne 0 ]]; then
        error "Backup FALHOU. Verifique ${DUMP_DEST}/manifest.txt"
    fi
}
trap cleanup EXIT

info "Iniciando backup – ${TIMESTAMP}"
info "Dumps SQL: ${DUMP_DEST}"
info "Dados: ${DATA_DIR}"

# ── Manifesto ─────────────────────────────────────────────────────────────────
cat > "${DUMP_DEST}/manifest.txt" <<EOF
timestamp=${TIMESTAMP}
host=$(hostname)
data_dir=${DATA_DIR}
EOF

# ── Acorda containers para o dump ─────────────────────────────────────────────
wake_container() {
    local name="$1"
    if ! docker inspect --format '{{.State.Running}}' "${name}" 2>/dev/null | grep -q true; then
        info "Iniciando container ${name} para backup..."
        docker start "${name}"
        sleep 5
        echo "started_for_backup=${name}" >> "${DUMP_DEST}/manifest.txt"
    fi
}

# ── Dumps PostgreSQL ──────────────────────────────────────────────────────────
info "Fazendo dump do banco Gitea (PostgreSQL)..."
wake_container homelab-gitea-db
docker exec homelab-gitea-db \
    pg_dump -U "${GITEA_DB_USER:-gitea}" -d "${GITEA_DB_NAME:-gitea}" \
    | gzip > "${DUMP_DEST}/gitea-postgres.sql.gz"
info "  → gitea-postgres.sql.gz"

info "Fazendo dump do banco Linkwarden (PostgreSQL)..."
wake_container homelab-linkwarden-db
docker exec homelab-linkwarden-db \
    pg_dump -U "${LINKWARDEN_DB_USER:-linkwarden}" -d "${LINKWARDEN_DB_NAME:-linkwarden}" \
    | gzip > "${DUMP_DEST}/linkwarden-postgres.sql.gz"
info "  → linkwarden-postgres.sql.gz"

info "Fazendo dump do banco Mealie (PostgreSQL)..."
wake_container homelab-mealie-db
docker exec homelab-mealie-db \
    pg_dump -U "${MEALIE_DB_USER:-mealie}" -d "${MEALIE_DB_NAME:-mealie}" \
    | gzip > "${DUMP_DEST}/mealie-postgres.sql.gz"
info "  → mealie-postgres.sql.gz"

info "Fazendo dump do banco Immich (PostgreSQL)..."
wake_container homelab-immich-postgres
docker exec homelab-immich-postgres \
    pg_dump -U "${IMMICH_DB_USER:-immich}" -d "${IMMICH_DB_NAME:-immich}" \
    | gzip > "${DUMP_DEST}/immich-postgres.sql.gz"
info "  → immich-postgres.sql.gz"

# ── Finaliza manifesto ────────────────────────────────────────────────────────
{
    echo "files="
    ls -1 "${DUMP_DEST}"
} >> "${DUMP_DEST}/manifest.txt"

# ── Limpa dumps antigos (mantém os 7 mais recentes) ──────────────────────────
DUMPS_DIR="${DATA_DIR}/sql-dumps"
KEEP=7
OLD_COUNT=$(find "${DUMPS_DIR}" -maxdepth 1 -mindepth 1 -type d | wc -l)
if [[ ${OLD_COUNT} -gt ${KEEP} ]]; then
    info "Removendo dumps antigos (mantendo ${KEEP})..."
    find "${DUMPS_DIR}" -maxdepth 1 -mindepth 1 -type d \
        | sort | head -n -${KEEP} \
        | xargs rm -rf
fi

echo ""
info "Backup concluído: ${DUMP_DEST}"
echo ""
du -sh "${DUMP_DEST}"
echo ""
info "Kopia irá incluir estes dumps no próximo snapshot automático."
info "Para restaurar: ./scripts/restore.sh ${DUMP_DEST}"
