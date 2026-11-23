# MicroCRM front end (Angular). Multi-stage: Node only exists in the build stage,
# the final image is Caddy serving the static files.
# Containerization plan: docs/documentation-technique.md, section 3.1.

# ---- Build stage ----
FROM node:26.13.1-alpine AS build
WORKDIR /src

# Dependencies first (cached until package*.json change); lifecycle scripts disabled (supply chain)
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts

COPY . .
RUN npm run build

# ---- Runtime stage ----
FROM caddy:2.11.9-alpine

# Unprivileged user. Caddy keeps its state in /data and /config, so it must own them.
# The official binary can still bind ports 80/443 (cap_net_bind_service) for HTTPS in production.
RUN addgroup -S web && adduser -S -G web web \
    && chown -R web:web /data /config
COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=build /src/dist/microcrm/browser /srv
USER web

# Locally: plain HTTP on 8080. In production: SITE_ADDRESS=<domain> enables automatic HTTPS.
ENV SITE_ADDRESS=:8080
EXPOSE 8080
