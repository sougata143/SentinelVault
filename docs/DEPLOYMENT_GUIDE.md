# SentinelVault — Production Deployment Guide

This guide provides comprehensive, step-by-step instructions for deploying the **SentinelVault** hybrid zero-knowledge password management platform in a production cloud environment.

---

## System Architecture Overview

SentinelVault comprises five primary infrastructure components:

```
                          ┌──────────────────────────┐
                          │   Flutter Web / Native   │
                          │   Client App (HTTPS)     │
                          └─────────────┬────────────┘
                                        │
                                        ▼
                          ┌──────────────────────────┐
                          │ Nginx Reverse Proxy / SSL│
                          │     (Port 80 / 443)      │
                          └─────────────┬────────────┘
                                        │
          ┌─────────────────────┬───────┴─────────────┬─────────────────────┐
          │                     │                     │                     │
          ▼                     ▼                     ▼                     ▼
┌───────────────────┐ ┌───────────────────┐ ┌───────────────────┐ ┌───────────────────┐
│   Auth Service    │ │     Sync API      │ │  Sharing Service  │ │ Security Analysis │
│   (Port 3001)     │ │    (Port 3002)    │ │    (Port 3004)    │ │    (Port 3003)    │
└─────────┬─────────┘ └─────────┬─────────┘ └─────────┬─────────┘ └─────────┬─────────┘
          │                     │                     │                     │
          └─────────────────────┼─────────────────────┴─────────────────────┘
                                │
                      ┌─────────┴─────────┐
                      │                   │
                      ▼                   ▼
            ┌───────────────────┐ ┌───────────────┐
            │   PostgreSQL 15   │ │    Redis 7    │
            │    (Port 5432)    │ │  (Port 6379)  │
            └───────────────────┘ └───────────────┘
```

1. **Frontend Client**: Flutter Web application compiled to static web assets (HTML/JS/Wasm) or native desktop/mobile clients.
2. **Reverse Proxy / SSL Gateway**: Nginx handling HTTPS termination, rate limiting, and request routing.
3. **Backend Microservices (Node.js/NestJS)**:
   - `auth-service`: Authentication, user registration, OPAQUE/SRP session management, PATs, SSO.
   - `sync-api`: Vault sync protocol, encrypted blob store, folder share recipient queries.
   - `sharing-service`: PQC key directory, monotonic share versions, secure share links, emergency contacts.
   - `security-analysis-service`: K-anonymity breach monitoring & password strength analysis.
4. **Data Stores**:
   - **PostgreSQL 15**: Relational persistence for user accounts, encrypted items, share invites, and metadata.
   - **Redis 7**: Cache store, rate limiting, and pub/sub messaging.

---

## Deployment Options at a Glance

| Option | Ideal For | Monthly Cost | Operational Complexity |
| :--- | :--- | :--- | :--- |
| **[Option 1: Single VPS + Docker Compose](#option-1-single-vps-with-docker-compose-recommended)** *(Recommended)* | Small to Medium Deployments, Self-Hosters, Startups | **$10 – $20** | ⚡ Low |
| **[Option 2: Managed PaaS (Railway / Render)](#option-2-managed-paas-railway--render)** | Dev Teams wanting zero server management | **$15 – $35** | ⚡ Low |
| **[Option 3: Enterprise Cloud (AWS ECS / GCP Cloud Run)](#option-3-enterprise-aws-cloud-architecture-ecs--rds)** | High Availability, Multi-AZ Data Centers, Large Scale | **$60 – $150+** | 🛠️ Moderate to High |

---

## Option 1: Single VPS with Docker Compose (Recommended)

Deploying to a single Linux Virtual Private Server (VPS) via Docker Compose is the most straightforward, performant, and cost-effective deployment method.

### Prerequisites
- **Recommended Cloud Providers**: Hetzner Cloud (CPX21), DigitalOcean (4GB Droplet), AWS EC2 (`t4g.medium`), Linode, or Vultr.
- **Hardware Specifications**: Minimum 2 vCPU, 4 GB RAM, 40 GB SSD.
- **Operating System**: Ubuntu 24.04 LTS (or Ubuntu 22.04 LTS).
- **Domain Name**: Registered domain with DNS pointing to your VPS IP address (e.g., `vault.yourdomain.com`).

---

### Detailed Steps

#### Step 1: Connect to VPS & Install Dependencies
SSH into your server:
```bash
ssh root@<YOUR_VPS_IP>
```
Update system packages and install Docker, Git, and Certbot:
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y docker.io docker-compose-v2 git certbot python3-certbot-nginx ufw
sudo systemctl enable --now docker
```

#### Step 2: Configure UFW Firewall
Restrict access to necessary ports only:
```bash
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

#### Step 3: Clone Repository & Create Production Environment File
```bash
cd /opt
sudo git clone https://github.com/sougata143/SentinelVault.git
cd SentinelVault
```
Create `.env` file containing strong production credentials:
```bash
cat << 'EOF' > .env
# Database Credentials
POSTGRES_DB=sentinelvault
POSTGRES_USER=sentinel_admin
POSTGRES_PASSWORD=CHANGE_THIS_TO_A_SUPER_STRONG_RANDOM_PASSWORD_123!

# Redis Configuration
REDIS_URL=redis://redis:6379

# Cryptographic & Auth Secrets
JWT_SECRET=CHANGE_THIS_TO_AN_ULTRA_SECURE_64_CHAR_RANDOM_STRING_XYZ

# Microservice Ports
AUTH_PORT=3001
SYNC_PORT=3002
SECURITY_ANALYSIS_PORT=3003
SHARING_PORT=3004
FRONTEND_PORT=8080
EOF
```

#### Step 4: Build Flutter Web Release Assets
If Flutter SDK is installed on your local dev machine or build server, build the production web bundle:
```bash
cd app
flutter build web --release --web-renderer canvaskit
cd ..
```
Upload the compiled `app/build/web` directory to your VPS at `/opt/SentinelVault/app/build/web`.

#### Step 5: Start Docker Stack
Launch all containerized services:
```bash
docker compose up -d --build
```
Verify all containers are healthy:
```bash
docker compose ps
```
You should see `sentinelvault-db`, `sentinelvault-cache`, `sentinelvault-auth`, `sentinelvault-sync`, `sentinelvault-security-analysis`, and `sentinelvault-sharing` running in healthy state.

#### Step 6: Configure SSL/TLS Certificate via Let's Encrypt
Run Certbot to obtain a free SSL/TLS certificate for your domain:
```bash
sudo certbot --nginx -d vault.yourdomain.com
```
Certbot automatically updates Nginx configuration and enables automatic certificate renewal.

#### Step 7: Verify Health Endpoints
```bash
curl -I https://vault.yourdomain.com/health
curl -I https://vault.yourdomain.com/auth/health
```

---

## Option 2: Managed PaaS (Railway / Render)

For teams preferring zero infrastructure maintenance, automatic Git push deployments, and fully managed databases.

### Architecture Topology
- **Databases**: Managed PostgreSQL & Managed Redis on Railway or Render.
- **Backend Services**: 4 Web Services running NestJS containers on Railway/Render.
- **Frontend App**: Deployed to Cloudflare Pages, Vercel, or Netlify CDN.

---

### Detailed Steps

#### Step 1: Provision Database & Cache Services
1. Log in to [Railway](https://railway.app) or [Render](https://render.com).
2. Create a new **PostgreSQL Database** instance (Version 15+). Record the `DATABASE_URL`.
3. Create a new **Redis** instance (Version 7+). Record the `REDIS_URL`.

#### Step 2: Deploy Backend Microservices
In your PaaS dashboard, connect your GitHub repository `SentinelVault` and create four Web Services:

1. **`auth-service`**:
   - Root Directory: `backend/auth-service`
   - Build Command: `npm install --legacy-peer-deps && npm run build`
   - Start Command: `npm run start:prod`
   - Environment Variables: `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET`, `AUTH_PORT=3001`

2. **`sync-api`**:
   - Root Directory: `backend/sync-api`
   - Build Command: `npm install --legacy-peer-deps && npm run build`
   - Start Command: `npm run start:prod`
   - Environment Variables: `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET`, `SYNC_PORT=3002`

3. **`sharing-service`**:
   - Root Directory: `backend/sharing-service`
   - Build Command: `npm install --legacy-peer-deps && npm run build`
   - Start Command: `npm run start:prod`
   - Environment Variables: `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET`, `SHARING_PORT=3004`

4. **`security-analysis-service`**:
   - Root Directory: `backend/security-analysis-service`
   - Build Command: `npm install --legacy-peer-deps && npm run build`
   - Start Command: `npm run start:prod`
   - Environment Variables: `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET`, `SECURITY_ANALYSIS_PORT=3003`

#### Step 3: Deploy Flutter Web Client to Cloudflare Pages / Vercel
1. Build Flutter Web locally or in GitHub Actions:
   ```bash
   cd app
   flutter build web --release
   ```
2. Deploy the `app/build/web` directory to **Cloudflare Pages** or **Vercel**.
3. Set custom domain (e.g., `app.sentinelvault.io`).

---

## Option 3: Enterprise AWS Cloud Architecture (ECS + RDS)

Designed for enterprise grade high availability, multi-AZ database replication, and auto-scaling container fleets.

```
                              ┌─────────────────────────────┐
                              │    AWS Route 53 (DNS)       │
                              └──────────────┬──────────────┘
                                             │
                                             ▼
                              ┌─────────────────────────────┐
                              │  AWS CloudFront CDN / S3    │
                              │     (Flutter Web Assets)    │
                              └──────────────┬──────────────┘
                                             │
                                             ▼
                              ┌─────────────────────────────┐
                              │   Application Load Balancer │
                              │          (ALB)              │
                              └──────────────┬──────────────┘
                                             │
                       ┌─────────────────────┴─────────────────────┐
                       │  AWS ECS Fargate Fleet (Private Subnets)  │
                       └──────────────┬──────────────┬─────────────┘
                                      │              │
                                      ▼              ▼
                              ┌──────────────┐┌──────────────┐
                              │   AWS RDS    ││AWS ElastiCache│
                              │ PostgreSQL 15││   Redis 7    │
                              └──────────────┘└──────────────┘
```

---

### Detailed Steps

#### Step 1: AWS VPC Setup
1. Create a VPC with 2 Public Subnets (for ALB) and 2 Private Subnets (for ECS Fargate, RDS, and ElastiCache) across 2 Availability Zones.
2. Provision a NAT Gateway in public subnet for outbound internet access from private tasks.

#### Step 2: Provision Database Infrastructure
1. **AWS RDS PostgreSQL**:
   - Engine: PostgreSQL 15.x
   - Instance Class: `db.t4g.medium` (Multi-AZ deployment enabled)
   - Master Credentials saved in AWS Secrets Manager.
2. **AWS ElastiCache Redis**:
   - Engine: Redis 7.x
   - Node Type: `cache.t4g.small` (Replication group across 2 AZs).

#### Step 3: Containerize and Push to AWS ECR
Create AWS ECR repositories:
```bash
aws ecr create-repository --repository-name sentinelvault/auth-service
aws ecr create-repository --repository-name sentinelvault/sync-api
aws ecr create-repository --repository-name sentinelvault/sharing-service
aws ecr create-repository --repository-name sentinelvault/security-analysis-service
```
Build and push images:
```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com

# Build & Push Auth Service
docker build -t sentinelvault/auth-service ./backend/auth-service
docker tag sentinelvault/auth-service:latest <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/sentinelvault/auth-service:latest
docker push <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/sentinelvault/auth-service:latest
```

#### Step 4: Configure ECS Fargate Tasks & Application Load Balancer
1. Create ECS Cluster named `sentinelvault-cluster`.
2. Define Fargate Task Definitions for each microservice with container ports `3001`, `3002`, `3003`, `3004`.
3. Create Application Load Balancer (ALB) with HTTPS listener (ACM SSL Certificate).
4. Configure ALB Path Routing Rules:
   - `/auth/*` → `auth-service` target group (3001)
   - `/sync/*` → `sync-api` target group (3002)
   - `/key-directory/*` → `sharing-service` target group (3004)
   - `/security/*` → `security-analysis-service` target group (3003)

#### Step 5: Static Web App Hosting on S3 + CloudFront
1. Create private S3 bucket `sentinelvault-web-assets`.
2. Upload compiled Flutter web output `app/build/web/*` to S3.
3. Create CloudFront distribution with Origin Access Control (OAC) pointing to S3 bucket.
4. Bind custom domain (`app.yourcompany.com`) via AWS Route 53.

---

## Production Operations & Security Checklist

### 1. Database Backups & Disaster Recovery
Automate daily PostgreSQL backups using `pg_dump` pushed to encrypted S3 storage:
```bash
#!/bin/bash
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/var/backups/sentinelvault"
mkdir -p $BACKUP_DIR

docker exec sentinelvault-db pg_dump -U sentinel_admin sentinelvault | gzip > $BACKUP_DIR/sentinelvault_$TIMESTAMP.sql.gz

# Retain last 14 days of backups
find $BACKUP_DIR -type f -mtime +14 -name "*.sql.gz" -delete
```
Add to crontab: `0 3 * * * /usr/local/bin/backup-db.sh`

### 2. Log Management & Monitoring
- Ensure health check endpoints are monitored via UptimeRobot / Datadog / Better Stack (`https://yourdomain.com/health`).
- Monitor Docker container logs:
  ```bash
  docker compose logs -f --tail=100
  ```

### 3. Non-Negotiable Zero-Knowledge Invariants
- **Master Password Security**: Ensure `Master Password` is never logged, transmitted, or stored on servers.
- **CORS Policies**: Explicitly restrict CORS headers in `backend/*/src/main.ts` to allowed client origin domains.
- **Secrets Isolation**: Never commit `.env` or production private keys to version control repositories.

---

## Summary Recommendation

- For **fastest setup with minimal cost**: Choose **Option 1 (VPS + Docker Compose)** on Hetzner or DigitalOcean.
- For **managed convenience**: Choose **Option 2 (Railway/Render)**.
- For **enterprise scale**: Choose **Option 3 (AWS ECS Fargate + RDS)**.
