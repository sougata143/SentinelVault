# SentinelVault Production Deployment Guide

This guide outlines the production deployment topology for **SentinelVault**, focused heavily on enforcing the **Secure Context (HTTPS)** environment mathematically required by WebAuthn/FIDO2 passkey mechanics [10], while maintaining zero-knowledge data security invariants [8].

---

## 1. The Secure Context Imperative (WebAuthn / HTTPS)

WebAuthn, Passkeys, and the CTAP2 hardware key APIs strictly require a **Secure Context** (HTTPS) in modern browsers [24]. Registering, asserting, or communicating with physical authenticators will throw DOM exceptions or fail silently over plain HTTP (with the sole exception of `localhost` during development) [24]. 

Furthermore, because SentinelVault handles highly sensitive key material in memory, enabling **HTTP Strict Transport Security (HSTS)** and restrictive **Content Security Policies (CSP)** is mandatory to prevent cross-site scripting (XSS) and token extraction attempts.

---

## 2. Production Topology

In a production environment, we deploy a TLS-terminating Reverse Proxy at the network boundary. This proxy:
1. Orchestrates Let's Encrypt SSL certificates automatically (ACME protocol).
2. Forwards TLS traffic down to our internal Docker bridge network (`sentinelvault-net`) [57].
3. Handles domain/routing rules to split traffic across our unified Flutter Web Frontend and the four stateless backend microservices [8, 9].

```
                     [ HTTPS Client Traffic ]
                               │
                               ▼ (Port 443 - TLS Terminated)
                     ┌──────────────────┐
                     │  Traefik Proxy   │ (Auto Let's Encrypt / ACME)
                     └─┬──┬──┬──┬──┬──┬─┘
       ┌───────────────┘  │  │  │  │  └────────────────┐
       ▼ (Port 80)        │  │  │  ▼ (Port 3004)       ▼
┌──────────────┐          │  │  ┌──────────────────┐ ┌──────────┐
│   frontend   │          │  │  │ sharing-service  │ │ postgres │
│(Nginx/Flutter│          │  │  └──────────────────┘ └──────────┘
└──────────────┘          │  ▼ (Port 3003)             ▲
                          │ ┌──────────────────┐       │ (Private DB Net)
                          │ │security-analysis │───────┘
                          │ └──────────────────┘
                          ▼ (Port 3002)
                        ┌──────────────────┐
                        │     sync-api     │
                        └──────────────────┘
```

---

## 3. Production Compose Configuration (`docker-compose.prod.yml`)

The production Compose configuration mounts **Traefik** as the TLS-terminating gateway. It runs in front of your pre-existing services and binds them together using Docker network isolation [57].

```yaml
version: "3.8"

services:
  # --- Network Edge: Reverse Proxy & SSL Termination ---
  traefik:
    image: traefik:v3.0
    container_name: sentinelvault-gateway
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
      - "--certificatesresolvers.myresolver.acme.tlschallenge=true"
      - "--certificatesresolvers.myresolver.acme.email=${ACME_EMAIL}"
      - "--certificatesresolvers.myresolver.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - letsencrypt_certs:/letsencrypt
    restart: always
    networks:
      - sentinelvault-net

  # --- Flutter Web Frontend ---
  frontend:
    image: sentinelvault-frontend:latest
    container_name: sentinelvault-ui
    build:
      context: .
      dockerfile: Dockerfile-v2
      args:
        - AUTH_BASE_URL=https://auth.${DOMAIN_NAME}
        - SYNC_BASE_URL=https://sync.${DOMAIN_NAME}
        - SECURITY_BASE_URL=https://security.${DOMAIN_NAME}
        - SHARING_BASE_URL=https://sharing.${DOMAIN_NAME}
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.frontend.rule=Host(`${DOMAIN_NAME}`)"
      - "traefik.http.routers.frontend.entrypoints=websecure"
      - "traefik.http.routers.frontend.tls.certresolver=myresolver"
      - "traefik.http.services.frontend.loadbalancer.server.port=8080"
    restart: always
    depends_on:
      auth-service:
        condition: service_healthy
    networks:
      - sentinelvault-net

  # --- Microservice: Authentication & Passkeys ---
  auth-service:
    image: sentinelvault-auth:latest
    container_name: sentinelvault-auth
    build:
      context: ./backend/auth-service
      dockerfile: Dockerfile
    env_file:
      - .env.prod
    environment:
      DATABASE_URL: postgres://postgres:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
      REDIS_URL: redis://redis:6379
      AUTH_PORT: 3001
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.auth.rule=Host(`auth.${DOMAIN_NAME}`)"
      - "traefik.http.routers.auth.entrypoints=websecure"
      - "traefik.http.routers.auth.tls.certresolver=myresolver"
      - "traefik.http.services.auth.loadbalancer.server.port=3001"
    restart: always
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - sentinelvault-net

  # --- Microservice: Sync API (Zero-Knowledge Store) ---
  sync-api:
    image: sentinelvault-sync:latest
    container_name: sentinelvault-sync
    build:
      context: ./backend/sync-api
      dockerfile: Dockerfile
    env_file:
      - .env.prod
    environment:
      DATABASE_URL: postgres://postgres:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
      REDIS_URL: redis://redis:6379
      SYNC_PORT: 3002
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.sync.rule=Host(`sync.${DOMAIN_NAME}`)"
      - "traefik.http.routers.sync.entrypoints=websecure"
      - "traefik.http.routers.sync.tls.certresolver=myresolver"
      - "traefik.http.services.sync.loadbalancer.server.port=3002"
    restart: always
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - sentinelvault-net

  # --- Microservice: Security Analysis (Gemini Integration) ---
  security-analysis-service:
    image: sentinelvault-security-analysis:latest
    container_name: sentinelvault-security-analysis
    build:
      context: ./backend/security-analysis-service
      dockerfile: Dockerfile
    env_file:
      - .env.prod
    environment:
      DATABASE_URL: postgres://postgres:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
      REDIS_URL: redis://redis:6379
      SECURITY_ANALYSIS_PORT: 3003
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.security.rule=Host(`security.${DOMAIN_NAME}`)"
      - "traefik.http.routers.security.entrypoints=websecure"
      - "traefik.http.routers.security.tls.certresolver=myresolver"
      - "traefik.http.services.security.loadbalancer.server.port=3003"
    restart: always
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - sentinelvault-net

  # --- Microservice: PQC Sharing Engine & Key Directory ---
  sharing-service:
    image: sentinelvault-sharing:latest
    container_name: sentinelvault-sharing
    build:
      context: ./backend/sharing-service
      dockerfile: Dockerfile
    env_file:
      - .env.prod
    environment:
      DATABASE_URL: postgres://postgres:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
      REDIS_URL: redis://redis:6379
      SHARING_PORT: 3004
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.sharing.rule=Host(`sharing.${DOMAIN_NAME}`)"
      - "traefik.http.routers.sharing.entrypoints=websecure"
      - "traefik.http.routers.sharing.tls.certresolver=myresolver"
      - "traefik.http.services.sharing.loadbalancer.server.port=3004"
    restart: always
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - sentinelvault-net

  # --- Database State Tier ---
  postgres:
    image: postgres:16-alpine
    container_name: sentinelvault-db
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-sentinelvault}
      POSTGRES_USER: ${POSTGRES_USER:-sentinel_admin}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres_prod_data:/var/lib/postgresql/data
    healthcheck:
      test: [ "CMD-SHELL", "pg_isready -U sentinel_admin -d sentinelvault" ]
      interval: 5s
      timeout: 5s
      retries: 10
    restart: always
    networks:
      - sentinelvault-net

  redis:
    image: redis:7-alpine
    container_name: sentinelvault-cache
    volumes:
      - redis_prod_data:/data
    healthcheck:
      test: [ "CMD", "redis-cli", "ping" ]
      interval: 5s
      timeout: 5s
      retries: 10
    restart: always
    networks:
      - sentinelvault-net

networks:
  sentinelvault-net:
    driver: bridge

volumes:
  letsencrypt_certs:
  postgres_prod_data:
  redis_prod_data:
```

---

## 4. Production Security Headers Configuration (`nginx.prod.conf`)

For the Nginx server running inside your production `frontend` stage, replace the basic development server with strict security rules to mitigate MITM, clickjacking, and mime-sniffing:

```nginx
# nginx.prod.conf
server {
    listen 8080;
    server_name localhost;

    # Secure HTTP Headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-eval' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self' https: wss:; object-src 'none'; frame-ancestors 'none';" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    root /usr/share/nginx/html;
    index index.html;

    # Handle Flutter Single Page App (SPA) Routing
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Cache Static Assets (CSS, JS, WebAssembly, Images)
    location ~* \.(?:css|js|wasm|woff2?|png|jpg|jpeg|svg|ico)$ {
        expires 1y;
        add_header Cache-Control "public, no-transform";
        access_log off;
    }

    # Explicitly do not cache index.html or service worker
    location = /index.html {
        expires -1;
        add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0";
    }

    location = /flutter_service_worker.js {
        expires -1;
        add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0";
    }

    # Gzip Compression Setup
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_types text/plain text/css application/json application/javascript application/wasm image/svg+xml;
}
```

---

## 5. Deployment Checklist & Step-by-Step

### Step 1: Create Production Env File
Create a `.env.prod` file in the root of your project:
```bash
DOMAIN_NAME=yourdomain.com
ACME_EMAIL=admin@yourdomain.com
POSTGRES_PASSWORD=generate-a-strong-32-character-password-here
JWT_SECRET=generate-a-strong-32-character-secret-key-here
REDIS_URL=redis://redis:6379
```

### Step 2: Build and Deploy the Containers
Run the Docker Compose command targeting the production configuration:
```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build
```

### Step 3: Verify TLS handshake & secure session
Navigate to your configured domain name (e.g., `https://yourdomain.com`) in a web browser [28]. Open Developer Tools and verify that:
1. The connection is successfully terminated over TLS 1.3.
2. WebAuthn triggers securely (you can register and log in with your device's native fingerprint/passkey prompt).
3. The response headers include the strict HSTS, CSP, and X-Frame-Options configured in Nginx.
