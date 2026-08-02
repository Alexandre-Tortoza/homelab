Quero que você crie um homelab self-hosted, reproduzível e seguro usando Docker Compose.

O projeto deve conter apenas estes serviços:

- Gitea
- Vaultwarden
- Linkwarden
- Caddy como reverse proxy

O objetivo é conseguir clonar o repositório em outro computador, restaurar os dados persistentes e executar toda a infraestrutura novamente com poucos comandos.

## Requisitos gerais

Crie a estrutura completa do projeto, incluindo:

- `compose.yaml`
- `Caddyfile`
- `.env.example`
- `.gitignore`
- `README.md`
- Scripts de inicialização, backup, restauração e atualização
- Diretórios de configuração por serviço
- Healthchecks sempre que possível
- Volumes persistentes
- Rede Docker interna compartilhada
- Versões fixadas das imagens, evitando `latest`
- Política `restart: unless-stopped`
- Limites básicos de recursos quando apropriado
- Logs com rotação configurada
- Dependências corretamente declaradas
- Configuração compatível com Docker Compose moderno

Use uma estrutura semelhante a:

```text
homelab/
├── compose.yaml
├── Caddyfile
├── .env.example
├── .gitignore
├── README.md
├── data/
│   └── .gitkeep
├── scripts/
│   ├── setup.sh
│   ├── start.sh
│   ├── stop.sh
│   ├── update.sh
│   ├── backup.sh
│   ├── restore.sh
│   └── status.sh
└── backups/
    └── .gitkeep
```

Os dados persistentes reais não devem ser versionados no Git.

## Rede e acesso

Os serviços devem ser acessados somente pelo reverse proxy Caddy.

Não publique diretamente as portas internas do Gitea, Vaultwarden, Linkwarden ou dos bancos de dados.

O Caddy deve publicar somente:

```text
80
443
```

Use uma rede Docker chamada:

```text
homelab
```

Todos os serviços web devem entrar nessa rede.

Considere que o acesso principal será feito por Tailscale. Não configure exposição pública obrigatória nem abertura de portas no roteador.

Use estes hostnames configuráveis pelo `.env`:

```text
git.home.arpa
vault.home.arpa
links.home.arpa
```

Configure o Caddy para usar TLS interno inicialmente:

```caddyfile
tls internal
```

Documente no README como instalar o certificado raiz do Caddy nos dispositivos clientes.

Também documente como substituir posteriormente os hostnames internos por um domínio real.

## Gitea

Configure o Gitea com:

- Banco PostgreSQL dedicado
- Repositórios Git
- Issues
- Pull requests
- Wiki
- Git LFS
- Package Registry
- Container Registry
- SSH para operações Git
- Armazenamento persistente
- URL pública configurada pelo `.env`
- Cadastro público desabilitado por padrão
- Criação do primeiro administrador documentada

O acesso web deve ocorrer por:

```text
https://git.home.arpa
```

Para Git via SSH, publique uma porta configurável no host, usando por padrão:

```text
2222
```

Exemplo esperado:

```bash
git clone ssh://git@git.home.arpa:2222/usuario/repositorio.git
```

Configure corretamente:

```text
ROOT_URL
SSH_DOMAIN
SSH_PORT
SSH_LISTEN_PORT
DOMAIN
```

O PostgreSQL do Gitea não deve ser compartilhado com outros serviços.

Inclua healthchecks para o Gitea e para o PostgreSQL.

## Vaultwarden

Configure o Vaultwarden com:

- Armazenamento persistente em `/data`
- Cadastro público desabilitado por padrão
- WebSocket habilitado
- URL pública configurada pelo `.env`
- Token administrativo obrigatório
- SMTP opcional, configurável pelo `.env`
- Banco SQLite, salvo no volume persistente
- Backups consistentes do diretório `/data`

O acesso deve ocorrer por:

```text
https://vault.home.arpa
```

Não coloque senhas ou tokens reais no repositório.

Inclua no `.env.example`:

```text
VAULTWARDEN_ADMIN_TOKEN
VAULTWARDEN_SIGNUPS_ALLOWED=false
VAULTWARDEN_DOMAIN
```

Explique no README como gerar um hash seguro para o token administrativo, caso a versão utilizada suporte ou recomende essa configuração.

## Linkwarden

Configure o Linkwarden com:

- PostgreSQL dedicado
- Armazenamento persistente
- Arquivamento de páginas
- Uploads persistentes
- URL pública configurada pelo `.env`
- Segredo de autenticação obrigatório
- Cadastro público desabilitado, quando suportado
- Healthchecks para aplicação e banco

O acesso deve ocorrer por:

```text
https://links.home.arpa
```

Inclua no `.env.example` variáveis semelhantes a:

```text
LINKWARDEN_DATABASE_PASSWORD
LINKWARDEN_NEXTAUTH_SECRET
LINKWARDEN_NEXTAUTH_URL
```

Use os nomes oficiais esperados pela versão atual do Linkwarden. Verifique a documentação oficial antes de definir as variáveis.

O PostgreSQL do Linkwarden deve ser separado do PostgreSQL do Gitea.

## Caddy

Configure o Caddy como único reverse proxy.

O `Caddyfile` deve conter rotas para:

```text
git.home.arpa
vault.home.arpa
links.home.arpa
```

Cada hostname deve encaminhar para o nome interno correto do container.

Exemplo conceitual:

```caddyfile
{$GITEA_DOMAIN} {
    tls internal
    reverse_proxy gitea:3000
}

{$VAULTWARDEN_DOMAIN} {
    tls internal
    reverse_proxy vaultwarden:80
}

{$LINKWARDEN_DOMAIN} {
    tls internal
    reverse_proxy linkwarden:3000
}
```

Adicione headers de segurança adequados, sem quebrar WebSockets, uploads, Git LFS ou o Container Registry do Gitea.

Não configure autenticação adicional no Caddy na frente do Vaultwarden.

Persista os diretórios `/data` e `/config` do Caddy.

## Persistência

Prefira bind mounts em:

```text
/srv/homelab/
```

Estrutura esperada no host:

```text
/srv/homelab/
├── caddy/
│   ├── data/
│   └── config/
├── gitea/
│   ├── data/
│   └── postgres/
├── vaultwarden/
│   └── data/
└── linkwarden/
    ├── data/
    └── postgres/
```

O script `setup.sh` deve:

- Verificar se Docker está instalado
- Verificar se Docker Compose está disponível
- Criar os diretórios necessários
- Configurar permissões adequadas
- Criar a rede Docker, caso necessário
- Copiar `.env.example` para `.env` se o arquivo não existir
- Não sobrescrever um `.env` existente
- Validar o arquivo Compose
- Informar claramente quais variáveis ainda precisam ser preenchidas

Não use permissões `777`.

## Segredos

O `.env.example` deve conter placeholders, nunca segredos reais.

Inclua variáveis para:

- Domínios
- Senhas dos PostgreSQL
- Secrets do Linkwarden
- Token administrativo do Vaultwarden
- UID e GID quando necessário
- Timezone `America/Sao_Paulo`
- Porta SSH do Gitea

Crie um script ou instruções para gerar valores seguros usando:

```bash
openssl rand -base64 48
```

O arquivo `.env` deve estar no `.gitignore`.

## Backups

Crie `scripts/backup.sh` que:

- Pare ou coloque os serviços em um estado consistente quando necessário
- Gere dumps dos bancos PostgreSQL
- Faça backup dos dados persistentes
- Inclua Gitea, Vaultwarden, Linkwarden e Caddy
- Grave os backups em uma pasta com timestamp
- Comprima os arquivos
- Valide se os comandos foram concluídos
- Restaure os serviços ao final, mesmo em caso de erro
- Não remova backups automaticamente sem configuração explícita

Estrutura esperada:

```text
backups/
└── 2026-08-02_11-30-00/
    ├── gitea-postgres.sql.gz
    ├── linkwarden-postgres.sql.gz
    ├── gitea-data.tar.gz
    ├── vaultwarden-data.tar.gz
    ├── linkwarden-data.tar.gz
    ├── caddy-data.tar.gz
    └── manifest.txt
```

Crie também `scripts/restore.sh` que:

- Receba o caminho do backup como argumento
- Peça confirmação antes de sobrescrever dados
- Pare os containers
- Restaure diretórios persistentes
- Restaure os bancos PostgreSQL
- Corrija permissões
- Suba os serviços novamente
- Mostre o status final
- Aborte em caso de arquivos obrigatórios ausentes

## Atualizações

Crie `scripts/update.sh` que:

- Faça backup antes da atualização
- Baixe as novas imagens
- Recrie os containers
- Aguarde os healthchecks
- Exiba o status
- Não remova imagens antigas automaticamente
- Permita rollback manual

Não altere automaticamente as versões fixadas no `compose.yaml`.

Documente como atualizar conscientemente cada versão.

## Segurança

Aplique estas regras:

- Nenhum banco deve publicar portas no host
- Apenas Caddy deve publicar HTTP e HTTPS
- Gitea pode publicar somente a porta SSH configurável
- Cadastro público desabilitado
- Containers sem privilégios
- Sem `privileged: true`
- Sem montagem do socket Docker dentro das aplicações
- Filesystem somente leitura quando for seguro
- `no-new-privileges:true` quando compatível
- Senhas fortes obrigatórias
- Imagens oficiais ou reconhecidas
- Tags de versão fixadas
- Permissões mínimas nos diretórios persistentes
- Serviços acessíveis apenas pela rede privada ou Tailscale
- Instruções de firewall no README

Não use soluções que exijam expor o Docker Socket ao Caddy ou às aplicações.

## README

O README deve explicar:

1. Arquitetura.
2. Pré-requisitos.
3. Estrutura dos diretórios.
4. Configuração do `.env`.
5. Inicialização.
6. Configuração de DNS.
7. Uso com Tailscale.
8. Instalação do certificado raiz do Caddy.
9. Criação dos usuários administradores.
10. Clone e push por SSH no Gitea.
11. Login e uso do Container Registry do Gitea.
12. Backup.
13. Restauração.
14. Atualização.
15. Migração para outro computador.
16. Diagnóstico de problemas.
17. Como parar todos os serviços.
18. Como remover containers sem apagar dados.

Inclua comandos concretos, por exemplo:

```bash
cp .env.example .env
nano .env
./scripts/setup.sh
./scripts/start.sh
./scripts/status.sh
```

## Migração para outro computador

A solução deve permitir este fluxo:

```bash
git clone <URL-DO-REPOSITORIO> homelab
cd homelab
cp .env.example .env
nano .env
sudo ./scripts/setup.sh
sudo ./scripts/restore.sh ./backups/<BACKUP>
docker compose up -d
```

Documente que o repositório contém apenas a receita e que os dados devem ser restaurados separadamente.

## Qualidade da implementação

Antes de finalizar:

- Verifique as imagens e variáveis de ambiente nas documentações oficiais atuais
- Execute `docker compose config`
- Corrija referências inválidas
- Garanta que todos os serviços estejam na rede correta
- Confirme que os bancos não estejam expostos
- Confirme que apenas Caddy e o SSH do Gitea tenham portas publicadas
- Valide os scripts com `shellcheck`, caso esteja disponível
- Use `set -Eeuo pipefail` nos scripts Bash
- Adicione tratamento de erros
- Evite valores mágicos repetidos
- Não invente variáveis de ambiente inexistentes

## Forma de execução

Não apenas descreva a solução.

Crie os arquivos diretamente no diretório atual.

Ao terminar:

1. Mostre a árvore final de arquivos.
2. Liste as decisões de arquitetura.
3. Mostre as variáveis que preciso preencher.
4. Execute as validações disponíveis.
5. Informe problemas ou limitações encontrados.
6. Não execute `docker compose up -d` sem minha confirmação.

---

implemente scale-to-zero inicialmente.
com o Sablier
