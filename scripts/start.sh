#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_DIR}"

if [[ ! -f .env ]]; then
    echo "Arquivo .env não encontrado. Execute primeiro: ./scripts/setup.sh" >&2
    exit 1
fi

echo "Iniciando gateway e serviços permanentes..."
docker compose up -d caddy sablier coredns homepage kopia

echo ""
echo "Gateway ativo. Os serviços de aplicação (Gitea, Vaultwarden, Linkwarden)"
echo "serão iniciados automaticamente pelo Sablier na primeira requisição."
echo ""
echo "URLs:"
# shellcheck source=/dev/null
source .env
echo "  Homepage:    https://home.${HOMELAB_DOMAIN}"
echo "  Kopia:       https://kopia.${HOMELAB_DOMAIN}"
echo "  Gitea:       https://git.${HOMELAB_DOMAIN}"
echo "  Vaultwarden: https://vault.${HOMELAB_DOMAIN}"
echo "  Linkwarden:  https://links.${HOMELAB_DOMAIN}"
echo ""
echo "Para ver o status: ./scripts/status.sh"
