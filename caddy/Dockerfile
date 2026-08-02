FROM caddy:2.11.4-builder AS builder

RUN xcaddy build \
    --with github.com/sablierapp/sablier-caddy-plugin@v1.0.2

FROM caddy:2.11.4-alpine
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
