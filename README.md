# Homelab

Self-hosted, reproduzível e seguro com Docker Compose. Serviços escalam para zero quando não estão em uso — Caddy e Sablier ficam sempre ativos; Gitea, Vaultwarden e Linkwarden dormem até a primeira requisição.

## 1. Arquitetura

```
Internet / Tailscale
       │
    Caddy :443 (:80 → redirect)
       │
   Sablier (scale-to-zero manager)
   ┌────┴──────────────────────────┐
   │            │                  │
gitea:3000  vaultwarden:80  linkwarden:3000
   │                               │
gitea-db:5432             linkwarden-db:5432
```

**Rede:** todos os containers compartilham a rede Docker `homelab`. Nenhum banco publica porta no host. Apenas Caddy publica 80/443 e Gitea publica a porta SSH.

**Scale-to-zero com Sablier:** o plugin do Caddy intercepta cada requisição e acorda os containers correspondentes. Após `SESSION_DURATION` sem tráfego, o Sablier para os containers. Caddy e Sablier ficam sempre ativos (consumo mínimo ~50 MB).

## 2. Pré-requisitos

- Docker Engine 24+
- Docker Compose plugin v2+
- Tailscale no host (recomendado)
- `sudo` para criar `/srv/homelab/`

## 3. Estrutura dos diretórios

```
homelab/               ← repositório (receita apenas)
├── compose.yaml
├── Caddyfile
├── .env.example
├── caddy/Dockerfile
├── scripts/
└── backups/

/srv/homelab/          ← dados persistentes (fora do repositório)
├── caddy/{data,config}
├── gitea/{data,postgres}
├── vaultwarden/data
└── linkwarden/{data,postgres}
```

## 4. Configuração do .env

```bash
cp .env.example .env
nano .env
```

Variáveis obrigatórias:

| Variável | Descrição |
|---|---|
| `GITEA_DB_PASSWORD` | Senha do PostgreSQL do Gitea |
| `VAULTWARDEN_ADMIN_TOKEN` | Token ou hash argon2 do admin |
| `LINKWARDEN_DB_PASSWORD` | Senha do PostgreSQL do Linkwarden |
| `LINKWARDEN_NEXTAUTH_SECRET` | Secret de autenticação do Linkwarden |

Gere valores seguros:

```bash
openssl rand -base64 48
```

### Token administrativo do Vaultwarden

Para gerar um hash argon2 (recomendado):

```bash
docker run --rm -it vaultwarden/server \
  /vaultwarden hash --preset owasp
```

Cole o resultado completo (`$argon2id$...`) em `VAULTWARDEN_ADMIN_TOKEN`.

## 5. Inicialização

```bash
cp .env.example .env
nano .env
sudo ./scripts/setup.sh
./scripts/start.sh
./scripts/status.sh
```

## 6. Configuração de DNS com Tailscale

Os domínios usam o formato `git.MACHINE.ts.net`, onde `MACHINE` é o nome da sua máquina no Tailscale.

**Encontre o nome e o IP Tailscale da máquina:**

```bash
tailscale status
# ou no painel: https://login.tailscale.com/admin/machines
# O IP começa com 100.x.x.x
```

### Opção A — `/etc/hosts` em cada cliente (mais simples)

Adicione em cada dispositivo que vai acessar o homelab:

```
# Linux/macOS: /etc/hosts
# Windows: C:\Windows\System32\drivers\etc\hosts
100.x.x.x  git.MACHINE.ts.net  vault.MACHINE.ts.net  links.MACHINE.ts.net
```

### Opção B — Tailscale split-DNS (recomendado, zero config nos clientes)

Requer um resolvedor DNS local no servidor (Pi-hole, AdGuard Home ou CoreDNS).
Configure-o com registros wildcard `*.MACHINE.ts.net → 100.x.x.x`, depois:

```
Tailscale Admin → DNS → Add nameserver
→ IP Tailscale do servidor
→ Restrict to domain: MACHINE.ts.net
```

Todos os dispositivos Tailscale passam a resolver `*.MACHINE.ts.net` automaticamente.

## 7. Uso com Tailscale

```bash
# Instale no servidor
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Verifique o IP atribuído (sempre 100.x.x.x)
tailscale ip -4
```

Com MagicDNS ativo no Tailscale Admin, o nome `MACHINE` já resolve entre dispositivos Tailscale. Os subdomínios (`git.`, `vault.`, `links.`) precisam da Opção A ou B acima.

## 8. Instalação do certificado raiz do Caddy

O Caddy usa `tls internal` e gera sua própria CA. Instale em cada cliente:

```bash
# Extraia o certificado (no servidor, após o primeiro start)
docker cp homelab-caddy:/data/caddy/pki/authorities/local/root.crt ./caddy-root.crt

# Linux (Arch/Debian/Ubuntu)
sudo cp caddy-root.crt /usr/local/share/ca-certificates/caddy-root.crt
sudo update-ca-certificates

# macOS
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain caddy-root.crt

# Windows (PowerShell admin)
Import-Certificate -FilePath caddy-root.crt -CertStoreLocation Cert:\LocalMachine\Root

# Firefox: Preferências → Privacidade → Ver certificados → Autoridades → Importar
```

## 9. Criação dos primeiros administradores

### Gitea

Na primeira visita a `https://git.<machine>.<tailnet>.ts.net`, o assistente de instalação cria o admin. Ou via CLI:

```bash
docker exec -it homelab-gitea gitea admin user create \
  --username admin --password 'SenhaForte!' \
  --email admin@exemplo.com --admin
```

### Vaultwarden

Acesse `https://vault.<machine>.<tailnet>.ts.net/admin` com o `VAULTWARDEN_ADMIN_TOKEN`. Para criar o primeiro usuário, use a interface normal com o cadastro temporariamente ativado pelo painel admin.

### Linkwarden

O primeiro usuário criado em `https://links.<machine>.<tailnet>.ts.net` recebe permissões de admin automaticamente.

## 10. Git por SSH no Gitea

```bash
git clone ssh://git@git.<machine>.<tailnet>.ts.net:2222/usuario/repo.git

# ou configure ~/.ssh/config
Host git.<machine>.<tailnet>.ts.net
  Port 2222
  User git
```

> **Limitação scale-to-zero:** SSH não acorda o Gitea automaticamente. Acesse `https://git.<machine>.<tailnet>.ts.net` primeiro para iniciá-lo, depois use SSH.

## 11. Container Registry do Gitea

```bash
docker login git.<machine>.<tailnet>.ts.net
docker tag app:latest git.<machine>.<tailnet>.ts.net/usuario/app:latest
docker push git.<machine>.<tailnet>.ts.net/usuario/app:latest
docker pull git.<machine>.<tailnet>.ts.net/usuario/app:latest
```

## 12. Backup

```bash
./scripts/backup.sh
```

Gera em `backups/<timestamp>/`:
- `gitea-postgres.sql.gz`, `linkwarden-postgres.sql.gz` — dumps SQL
- `gitea-data.tar.gz`, `vaultwarden-data.tar.gz`, `linkwarden-data.tar.gz`, `caddy-data.tar.gz`
- `manifest.txt`

Para agendar (cron às 03:00):

```bash
0 3 * * * /caminho/homelab/scripts/backup.sh >> /var/log/homelab-backup.log 2>&1
```

## 13. Restauração

```bash
./scripts/restore.sh ./backups/2026-08-02_11-30-00
```

O script pede confirmação antes de sobrescrever qualquer dado.

## 14. Atualização

```bash
# 1. Verifique as novas versões nos repositórios oficiais
# 2. Edite .env (ex: GITEA_IMAGE=gitea/gitea:1.23.0)
nano .env

# 3. Execute (faz backup automático antes)
./scripts/update.sh
```

Para rollback:

```bash
./scripts/restore.sh ./backups/<timestamp-pré-atualização>
```

## 15. Migração para outro computador

```bash
git clone <URL-DO-REPOSITORIO> homelab
cd homelab

# Transfira o backup (via scp, Tailscale, etc.)
scp -r user@antigo:/caminho/homelab/backups/TIMESTAMP ./backups/

cp .env.example .env
nano .env
sudo ./scripts/setup.sh
sudo ./scripts/restore.sh ./backups/TIMESTAMP
```

> O repositório é apenas a receita. Os dados devem ser transferidos via backup/restore.

## 16. Diagnóstico de problemas

```bash
./scripts/status.sh

docker compose logs -f caddy
docker compose logs -f sablier
docker compose logs -f gitea

# Testar conectividade interna ao Sablier
docker exec homelab-caddy wget -qO- http://sablier:10000/api/strategies/groups

# Validar compose
docker compose config

# Ver certificado TLS
openssl s_client -connect git.<machine>.<tailnet>.ts.net:443 -servername git.<machine>.<tailnet>.ts.net
```

### Scale-to-zero não funciona

```bash
# Verifique se o Sablier enxerga os containers
docker exec homelab-sablier wget -qO- http://localhost:10000/api/strategies/groups
# ou
docker logs homelab-sablier
```

## 17. Como parar todos os serviços

```bash
./scripts/stop.sh
```

Dados em `/srv/homelab/` não são apagados.

## 18. Como remover containers sem apagar dados

```bash
docker compose down --remove-orphans
# Para remover imagens também: docker compose down --rmi all
```

## Scale-to-zero: comportamento e limitações

| Serviço | Modo | Comportamento no cold start |
|---|---|---|
| Gitea | Dynamic | Tela de carregamento no browser (~30-90s) |
| Vaultwarden | Blocking | Clientes esperam silenciosamente (~10-20s) |
| Linkwarden | Dynamic | Tela de carregamento no browser (~20-40s) |

**Limitações:**
- SSH do Gitea não acorda o container — acesse a web UI antes
- Apps Bitwarden podem falhar na sync durante cold start — abra o app para acordar
- Ajuste `*_SESSION_DURATION` no `.env` conforme sua necessidade

## Como substituir por domínio real (Let's Encrypt)

1. Aponte registros DNS para seu IP público
2. Edite `.env` com os novos domínios
3. No `Caddyfile`, remova `tls internal` de cada bloco
4. `docker compose restart caddy`

## Firewall

```bash
sudo ufw default deny incoming
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 2222/tcp  # Git SSH
sudo ufw enable
```

Com Tailscale, pode restringir à interface `tailscale0` e não abrir portas no roteador.
