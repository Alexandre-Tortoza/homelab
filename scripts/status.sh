#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_DIR}"

echo "═══════════════════════════════════════════════════════════"
echo " Homelab – Status dos containers"
echo "═══════════════════════════════════════════════════════════"
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "─── Logs recentes (últimas 5 linhas por serviço) ───────────"
for svc in caddy sablier coredns homepage kopia gitea gitea-db vaultwarden linkwarden linkwarden-db; do
    echo ""
    echo "▶ ${svc}:"
    docker compose logs --tail=5 --no-log-prefix "${svc}" 2>/dev/null || echo "  (container não está rodando)"
done
