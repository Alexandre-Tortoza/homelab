#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_DIR}"

# shellcheck source=/dev/null
source .env

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
    die "Uso: $0 <caminho-do-backup>\nExemplo: $0 ./backups/2026-08-02_11-30-00"
fi

BACKUP_DIR="$1"
[[ -d "${BACKUP_DIR}" ]] || die "Diretório de backup não encontrado: ${BACKUP_DIR}"

# ── Arquivos obrigatórios ─────────────────────────────────────────────────────
REQUIRED=(
    "gitea-postgres.sql.gz"
    "linkwarden-postgres.sql.gz"
    "gitea-data.tar.gz"
    "vaultwarden-data.tar.gz"
    "linkwarden-data.tar.gz"
)
for f in "${REQUIRED[@]}"; do
    [[ -f "${BACKUP_DIR}/${f}" ]] || die "Arquivo obrigatório ausente: ${BACKUP_DIR}/${f}"
done
info "Todos os arquivos obrigatórios encontrados."

# ── Confirmação ───────────────────────────────────────────────────────────────
echo ""
warn "ATENÇÃO: Esta operação VAI SOBRESCREVER todos os dados atuais em /srv/homelab/"
echo ""
read -r -p "Digite 'sim' para confirmar: " CONFIRM
[[ "${CONFIRM}" == "sim" ]] || die "Restauração cancelada."

# ── Para os containers ────────────────────────────────────────────────────────
info "Parando todos os containers..."
docker compose down || true

# Garante que os volumes não estejam em uso
sleep 3

# ── Restaura dados persistentes ───────────────────────────────────────────────
restore_dir() {
    local label="$1"
    local dest_parent="$2"
    local archive="${BACKUP_DIR}/${label}.tar.gz"
    if [[ -f "${archive}" ]]; then
        info "Restaurando ${label}..."
        rm -rf "${dest_parent}"
        mkdir -p "$(dirname "${dest_parent}")"
        tar -xzf "${archive}" -C "$(dirname "${dest_parent}")"
        info "  → ${dest_parent}"
    else
        warn "Arquivo não encontrado, ignorando: ${archive}"
    fi
}

restore_dir "gitea-data"       /srv/homelab/gitea/data
restore_dir "vaultwarden-data" /srv/homelab/vaultwarden/data
restore_dir "linkwarden-data"  /srv/homelab/linkwarden/data
restore_dir "caddy-data"       /srv/homelab/caddy/data

# ── Corrige permissões ────────────────────────────────────────────────────────
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

info "Corrigindo permissões..."

chown -R "${PUID}:${PGID}" /srv/homelab/gitea/data || true
chmod -R 750 /srv/homelab/gitea/data || true

chown 70:70 /srv/homelab/gitea/postgres || true
chmod 700 /srv/homelab/gitea/postgres || true

chown 70:70 /srv/homelab/linkwarden/postgres || true
chmod 700 /srv/homelab/linkwarden/postgres || true

chown -R "${PUID}:${PGID}" /srv/homelab/linkwarden/data || true
chmod -R 750 /srv/homelab/linkwarden/data || true

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

zcat "${BACKUP_DIR}/gitea-postgres.sql.gz" | \
    docker exec -i homelab-gitea-db \
    psql -U "${GITEA_DB_USER:-gitea}" -d "${GITEA_DB_NAME:-gitea}"

info "Restaurando banco Linkwarden..."
docker exec -i homelab-linkwarden-db \
    psql -U "${LINKWARDEN_DB_USER:-linkwarden}" -d postgres \
    -c "DROP DATABASE IF EXISTS \"${LINKWARDEN_DB_NAME:-linkwarden}\";" \
    -c "CREATE DATABASE \"${LINKWARDEN_DB_NAME:-linkwarden}\" OWNER \"${LINKWARDEN_DB_USER:-linkwarden}\";"

zcat "${BACKUP_DIR}/linkwarden-postgres.sql.gz" | \
    docker exec -i homelab-linkwarden-db \
    psql -U "${LINKWARDEN_DB_USER:-linkwarden}" -d "${LINKWARDEN_DB_NAME:-linkwarden}"

# ── Para bancos novamente (Sablier gerencia o ciclo de vida) ──────────────────
info "Parando bancos (Sablier irá iniciá-los sob demanda)..."
docker compose stop gitea-db linkwarden-db

# ── Inicia gateway ────────────────────────────────────────────────────────────
info "Iniciando Caddy e Sablier..."
docker compose up -d caddy sablier

echo ""
info "Restauração concluída com sucesso!"
echo ""
docker compose ps
