#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_DIR}"

if [[ ! -f .env ]]; then
    echo "Arquivo .env não encontrado. Execute primeiro: ./scripts/setup.sh" >&2
    exit 1
fi

echo "Iniciando Caddy e Sablier (serviços de gateway)..."
docker compose up -d caddy sablier

echo ""
echo "Gateway ativo. Os serviços de aplicação (Gitea, Vaultwarden, Linkwarden)"
echo "serão iniciados automaticamente pelo Sablier na primeira requisição."
echo ""
echo "URLs:"
# shellcheck source=/dev/null
source .env
echo "  Gitea:       https://git.${TAILSCALE_MACHINE}.ts.net"
echo "  Vaultwarden: https://vault.${TAILSCALE_MACHINE}.ts.net"
echo "  Linkwarden:  https://links.${TAILSCALE_MACHINE}.ts.net"
echo ""
echo "Para ver o status: ./scripts/status.sh"
