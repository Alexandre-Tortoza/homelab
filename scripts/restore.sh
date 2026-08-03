#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_DIR}"

# shellcheck source=/dev/null
source .env

DATA_DIR="${DATA_DIR:-/mnt/hd2/homelab}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { error "$*"; exit 1; }

# ── Argumento obrigatório ─────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
    die "Uso: $0 <caminho-do-dump>\nExemplo: $0 ${DATA_DIR}/sql-dumps/2026-08-02_11-30-00"
fi

DUMP_DIR="$1"
[[ -d "${DUMP_DIR}" ]] || die "Diretório de dump não encontrado: ${DUMP_DIR}"

# ── Arquivos obrigatórios ─────────────────────────────────────────────────────
REQUIRED=(
    "gitea-postgres.sql.gz"
    "linkwarden-postgres.sql.gz"
)
for f in "${REQUIRED[@]}"; do
    [[ -f "${DUMP_DIR}/${f}" ]] || die "Arquivo obrigatório ausente: ${DUMP_DIR}/${f}"
done
info "Todos os arquivos obrigatórios encontrados."

# ── Confirmação ───────────────────────────────────────────────────────────────
echo ""
warn "ATENÇÃO: Esta operação VAI SOBRESCREVER todos os dados em ${DATA_DIR}/"
echo ""
read -r -p "Digite 'sim' para confirmar: " CONFIRM
[[ "${CONFIRM}" == "sim" ]] || die "Restauração cancelada."

# ── Para os containers ────────────────────────────────────────────────────────
info "Parando todos os containers..."
docker compose down || true

sleep 3

# ── Inicia os bancos para restaurar dumps ─────────────────────────────────────
info "Iniciando bancos de dados para restauração..."
docker compose up -d gitea-db linkwarden-db

info "Aguardando PostgreSQL ficar saudável..."
for i in $(seq 1 30); do
    if docker exec homelab-gitea-db pg_isready -U "${GITEA_DB_USER:-gitea}" &>/dev/null; then
        break
    fi
    sleep 2
    if [[ $i -eq 30 ]]; then
        die "Timeout aguardando gitea-db"
    fi
done

for i in $(seq 1 30); do
    if docker exec homelab-linkwarden-db pg_isready -U "${LINKWARDEN_DB_USER:-linkwarden}" &>/dev/null; then
        break
    fi
    sleep 2
    if [[ $i -eq 30 ]]; then
        die "Timeout aguardando linkwarden-db"
    fi
done

# ── Restaura dumps SQL ────────────────────────────────────────────────────────
info "Restaurando banco Gitea..."
docker exec -i homelab-gitea-db \
    psql -U "${GITEA_DB_USER:-gitea}" -d postgres \
    -c "DROP DATABASE IF EXISTS \"${GITEA_DB_NAME:-gitea}\";" \
    -c "CREATE DATABASE \"${GITEA_DB_NAME:-gitea}\" OWNER \"${GITEA_DB_USER:-gitea}\";"

zcat "${DUMP_DIR}/gitea-postgres.sql.gz" | \
    docker exec -i homelab-gitea-db \
    psql -U "${GITEA_DB_USER:-gitea}" -d "${GITEA_DB_NAME:-gitea}"

info "Restaurando banco Linkwarden..."
docker exec -i homelab-linkwarden-db \
    psql -U "${LINKWARDEN_DB_USER:-linkwarden}" -d postgres \
    -c "DROP DATABASE IF EXISTS \"${LINKWARDEN_DB_NAME:-linkwarden}\";" \
    -c "CREATE DATABASE \"${LINKWARDEN_DB_NAME:-linkwarden}\" OWNER \"${LINKWARDEN_DB_USER:-linkwarden}\";"

zcat "${DUMP_DIR}/linkwarden-postgres.sql.gz" | \
    docker exec -i homelab-linkwarden-db \
    psql -U "${LINKWARDEN_DB_USER:-linkwarden}" -d "${LINKWARDEN_DB_NAME:-linkwarden}"

# ── Corrige permissões ────────────────────────────────────────────────────────
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

info "Corrigindo permissões em ${DATA_DIR}..."

chown -R "${PUID}:${PGID}" "${DATA_DIR}/gitea/data" || true
chmod -R 750 "${DATA_DIR}/gitea/data" || true

chown 70:70 "${DATA_DIR}/gitea/postgres" || true
chmod 700 "${DATA_DIR}/gitea/postgres" || true

chown 70:70 "${DATA_DIR}/linkwarden/postgres" || true
chmod 700 "${DATA_DIR}/linkwarden/postgres" || true

chown -R "${PUID}:${PGID}" "${DATA_DIR}/linkwarden/data" || true
chmod -R 750 "${DATA_DIR}/linkwarden/data" || true

# ── Para bancos novamente (Sablier gerencia o ciclo de vida) ──────────────────
info "Parando bancos (Sablier irá iniciá-los sob demanda)..."
docker compose stop gitea-db linkwarden-db

# ── Inicia gateway ────────────────────────────────────────────────────────────
info "Iniciando gateway e serviços permanentes..."
docker compose up -d caddy sablier coredns homepage kopia

echo ""
info "Restauração concluída com sucesso!"
echo ""
docker compose ps
