# 🚀 SentinelVault Self-Hosting Guide

This guide provides complete instructions for self-hosting the SentinelVault zero-knowledge backend microservices on your own infrastructure using Docker Compose.

---

## 💻 Minimum Hardware & Software Requirements

| Component | Minimum Specification | Recommended Specification |
|---|---|---|
| **CPU** | 2 vCPU cores (x86_64 or ARM64) | 4 vCPU cores |
| **RAM** | 2 GB System Memory | 4 GB+ System Memory |
| **Storage** | 10 GB SSD / NVMe | 50 GB+ SSD / NVMe |
| **OS** | Ubuntu 22.04 LTS, Debian 12, RHEL 9 | Linux with Docker support |
| **Software** | Docker v24.0+ & Docker Compose v2.20+ | Latest stable Docker engine |

---

## 🔑 Environment Variables Reference

Copy `self-hosted/.env.example` to `self-hosted/.env` and configure the following variables:

| Variable | Required? | Default / Sample | Description |
|---|---|---|---|
| `JWT_SECRET` | **YES** | `openssl rand -base64 32` | HS256 secret key for session JWT verification. Must be at least 32 random characters. |
| `POSTGRES_PASSWORD` | **YES** | `random_password_here` | Root database password for PostgreSQL container. |
| `DATABASE_URL` | **YES** | `postgres://user:pass@postgres:5432/sentinelvault` | Connection DSN passed to NestJS TypeORM microservices. |
| `REDIS_URL` | **YES** | `redis://redis:6379` | Redis DSN for session token revocation denylist (`revoked:jti:<id>`). |
| `GEMINI_API_KEY` | *Optional* | *(empty)* | Optional Google Gemini API key for AI Insights. **Fallback behavior**: If left empty, security summaries fall back gracefully to local client-side analysis with zero network transmission. |
| `PORT_AUTH` | *Optional* | `3001` | Host port binding for `auth-service`. |
| `PORT_SYNC` | *Optional* | `3002` | Host port binding for `sync-api`. |
| `PORT_SECURITY` | *Optional* | `3003` | Host port binding for `security-analysis-service`. |
| `PORT_SHARING` | *Optional* | `3004` | Host port binding for `sharing-service`. |

---

## 🛠️ First-Run Setup & Deployment

### 1. Clone & Configure Environment
```bash
git clone https://github.com/sougata143/SentinelVault.git
cd SentinelVault/self-hosted
cp .env.example .env
nano .env   # Update JWT_SECRET and POSTGRES_PASSWORD
```

### 2. Start the Backend Cluster
```bash
docker compose up -d
```

### 3. Verify Container Health
```bash
docker compose ps
```
Ensure all 6 containers (`sentinelvault-selfhosted-db`, `sentinelvault-selfhosted-redis`, `sentinelvault-auth-service`, `sentinelvault-sync-api`, `sentinelvault-security-service`, `sentinelvault-sharing-service`) report `healthy` or `running`.

---

## 🔒 Reverse Proxy & TLS Termination (Nginx Example)

Self-hosted deployments **must** run behind a reverse proxy handling HTTPS/TLS termination (e.g. Nginx, Caddy, or Traefik with Let's Encrypt).

Sample Nginx block (`/etc/nginx/sites-available/sentinelvault`):

```nginx
server {
    listen 443 ssl http2;
    server_name vault.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/vault.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/vault.yourdomain.com/privkey.pem;

    # Auth Service
    location /auth/ {
        proxy_pass http://127.0.0.1:3001/auth/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Sync API
    location /sync/ {
        proxy_pass http://127.0.0.1:3002/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # Security Analysis Service
    location /security/ {
        proxy_pass http://127.0.0.1:3003/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # Sharing Service
    location /sharing/ {
        proxy_pass http://127.0.0.1:3004/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

---

## 📱 Connecting Client Apps (Mobile, Desktop, Web)

To connect your official or self-compiled SentinelVault app installs (iOS, Android, Windows, macOS, Linux, Web) to your self-hosted backend:

1. Open SentinelVault app -> Navigate to **Settings** (`⚙`).
2. Scroll to **Server Connection Settings**.
3. In **Custom Server Base URL**, enter your self-hosted domain or IP (e.g. `https://vault.yourdomain.com` or `http://192.168.1.100`).
4. Click **Save Server URL**.
5. All authentication, sync, security analysis, and folder sharing API calls will now route directly to your self-hosted instance.

---

## 📋 Self-Hoster Responsibility Matrix

| Operational Task | Hosted Version (Cloud) | Self-Hosted Version |
|---|---|---|
| **Zero-Knowledge Vault Encryption** | Handled locally on client device | Handled locally on client device |
| **SSL/TLS Certificate Renewal** | Automatically managed | **Self-hoster responsibility** (Certbot / Caddy) |
| **PostgreSQL Database Backups** | Automated hourly WAL backups & PITR | **Self-hoster responsibility** (`pg_dump` / cron) |
| **Security Updates & Patching** | Automatic rolling deployments | **Self-hoster responsibility** (`git pull` & `docker compose build`) |
| **DDoS Protection & Rate Limiting** | Managed Cloudflare Edge | **Self-hoster responsibility** (Nginx `limit_req` / Fail2ban) |
