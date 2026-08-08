# SentinelVault — Production Deployment Guide & Cost Analysis

This guide provides comprehensive, step-by-step instructions and itemized cost breakdowns for deploying the **SentinelVault** hybrid zero-knowledge password management platform across multiple cloud providers and infrastructure tiers.

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

## Deployment Options & Itemized Cost Summary

| Option | Cloud Platform | Estimated Cost / Month | Infrastructure Components Included | Operational Complexity |
| :--- | :--- | :--- | :--- | :--- |
| **[Option 1](#option-1-single-vps-with-docker-compose-recommended)** | **Single VPS (Hetzner / DigitalOcean / AWS EC2)** | **$7.00 – $20.00** | All-in-one VPS container stack + Let's Encrypt SSL | ⚡ Low (15 mins) |
| **[Option 2](#option-2-managed-paas-railway--render)** | **PaaS (Railway / Render)** | **$15.00 – $35.00** | Managed Postgres + Redis + 4 App Services + CDN | ⚡ Low (Zero Infra) |
| **[Option 3](#option-3-enterprise-aws-cloud-architecture-terraform)** | **AWS Cloud (ECS Fargate + RDS)** | **$68.00 – $145.00** | Multi-AZ RDS + ElastiCache + ECS Fargate + ALB + CloudFront | 🛠️ Moderate |
| **[Option 4](#option-4-enterprise-gcp-cloud-architecture-terraform)** | **GCP Cloud (Cloud Run + Cloud SQL)** | **$45.00 – $110.00** | Cloud SQL + Memorystore + Cloud Run v2 + GCS/Cloud CDN | 🛠️ Moderate |

---

## Option 1: Single VPS with Docker Compose (Recommended)

Deploying to a single Linux Virtual Private Server (VPS) via Docker Compose is the most straightforward, performant, and cost-effective deployment method.

### 💰 Itemized Monthly Cost Breakdown

| Component | Provider & Specification | Cost / Month |
| :--- | :--- | :--- |
| **Compute Server** | Hetzner Cloud CPX21 (3 vCPU, 4GB RAM, 80GB NVMe) | **€7.05 (~$7.60)** |
| *Alternative Compute* | DigitalOcean Droplet (2 vCPU, 4GB RAM, 80GB SSD) | $24.00 |
| *Alternative Compute* | AWS EC2 `t4g.medium` (2 vCPU ARM, 4GB RAM) | $24.20 |
| **SSL/TLS Certificate** | Let's Encrypt (Certbot) | **$0.00** (Free) |
| **Domain DNS** | Cloudflare DNS / Route 53 | **$0.00 - $0.50** |
| **Estimated Total** | **Hetzner Base** | **~$8.00 / month** |

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

#### Step 6: Configure SSL/TLS Certificate via Let's Encrypt
Run Certbot to obtain a free SSL/TLS certificate for your domain:
```bash
sudo certbot --nginx -d vault.yourdomain.com
```

---

## Option 2: Managed PaaS (Railway / Render)

For teams preferring zero infrastructure maintenance, automatic Git push deployments, and fully managed databases.

### 💰 Itemized Monthly Cost Breakdown

| Resource | Service Tiers | Cost / Month |
| :--- | :--- | :--- |
| **PostgreSQL Database** | Managed PostgreSQL (8GB Storage, Shared CPU) | $7.00 |
| **Redis Cache** | Managed Redis (256MB RAM) | $3.00 |
| **4 Backend Services** | Railway/Render Web Services (512MB RAM each x 4) | $20.00 |
| **Frontend CDN** | Cloudflare Pages / Vercel Hobby | **$0.00** (Free) |
| **Estimated Total** | **PaaS Stack** | **~$30.00 / month** |

---

### Detailed Steps

#### Step 1: Provision Database & Cache Services
1. Log in to [Railway](https://railway.app) or [Render](https://render.com).
2. Create a new **PostgreSQL Database** instance (Version 15+). Record the `DATABASE_URL`.
3. Create a new **Redis** instance (Version 7+). Record the `REDIS_URL`.

#### Step 2: Deploy Backend Microservices
In your PaaS dashboard, connect your GitHub repository `SentinelVault` and create four Web Services:

1. **`auth-service`**: Root `backend/auth-service`, Build Command: `npm install --legacy-peer-deps && npm run build`, Start Command: `npm run start:prod`
2. **`sync-api`**: Root `backend/sync-api`, Build Command: `npm install --legacy-peer-deps && npm run build`, Start Command: `npm run start:prod`
3. **`sharing-service`**: Root `backend/sharing-service`, Build Command: `npm install --legacy-peer-deps && npm run build`, Start Command: `npm run start:prod`
4. **`security-analysis-service`**: Root `backend/security-analysis-service`, Build Command: `npm install --legacy-peer-deps && npm run build`, Start Command: `npm run start:prod`

#### Step 3: Deploy Flutter Web Client to Cloudflare Pages
Deploy compiled `app/build/web` to **Cloudflare Pages** or **Vercel** with custom domain binding (`app.sentinelvault.io`).

---

## Option 3: Enterprise AWS Cloud Architecture (Terraform)

Designed for enterprise grade high availability, multi-AZ database replication, and auto-scaling container fleets using AWS ECS Fargate, RDS, and ElastiCache.

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

### 💰 Itemized Monthly Cost Breakdown

| AWS Resource | Specification / Tier | Cost / Month |
| :--- | :--- | :--- |
| **AWS RDS PostgreSQL** | `db.t4g.medium` (2 vCPU, 4GB RAM, 20GB Storage) | $32.40 |
| **AWS ElastiCache Redis** | `cache.t4g.small` (1 node, 1.37GB RAM) | $12.10 |
| **AWS ECS Fargate Tasks** | 4 Services x 0.25 vCPU, 0.5GB RAM | $18.40 |
| **Application Load Balancer** | 1 ALB + LCU traffic | $18.00 |
| **NAT Gateway + EIP** | 1 NAT Gateway in Public Subnet | $32.00 |
| **S3 + CloudFront CDN** | Static Web Assets + Data Egress | $2.00 |
| **Estimated Total** | **AWS Enterprise Infrastructure** | **~$114.90 / month** |

---

### Detailed Automated Provisioning via Terraform

SentinelVault includes a pre-configured Terraform manifest at `terraform/aws/main.tf`.

#### Step 1: Install Terraform & AWS CLI
```bash
# Install Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform awscli -y
```

#### Step 2: Configure AWS Credentials
```bash
aws configure
```

#### Step 3: Initialize & Provision Infrastructure
```bash
cd terraform/aws
terraform init
terraform apply -var="db_password=YOUR_STRONG_DB_PASSWORD" -var="jwt_secret=YOUR_JWT_SECRET"
```

#### Step 4: Build and Push Docker Images to ECR
```bash
# ECR Login
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com

# Build & Push Services
for SERVICE in auth-service sync-api sharing-service security-analysis-service; do
  docker build -t sentinelvault/$SERVICE ../backend/$SERVICE
  docker tag sentinelvault/$SERVICE:latest <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/sentinelvault/$SERVICE:latest
  docker push <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/sentinelvault/$SERVICE:latest
done
```

---

## Option 4: Enterprise GCP Cloud Architecture (Terraform)

Serverless enterprise deployment utilizing **Google Cloud Run v2**, **Cloud SQL PostgreSQL**, **Memorystore Redis**, and **Cloud Storage / Cloud CDN**.

### 💰 Itemized Monthly Cost Breakdown

| GCP Resource | Specification / Tier | Cost / Month |
| :--- | :--- | :--- |
| **Cloud SQL PostgreSQL** | `db-custom-2-7680` (2 vCPU, 7.5GB RAM, 20GB SSD) | $48.00 |
| **Memorystore for Redis** | Basic Tier (2GB Memory) | $26.00 |
| **Cloud Run v2 Fleet** | 4 Microservices (Auto-scale 0 to N instances) | ~$10.00 (Pay per request) |
| **Artifact Registry** | Container image storage | $1.50 |
| **Cloud Storage + Cloud CDN**| Web frontend hosting + CDN caching | $1.50 |
| **Estimated Total** | **GCP Cloud Infrastructure** | **~$87.00 / month** |

---

### Detailed Automated Provisioning via Terraform

SentinelVault includes a pre-configured GCP Terraform manifest at `terraform/gcp/main.tf`.

#### Step 1: Authenticate with Google Cloud
```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_GCP_PROJECT_ID
```

#### Step 2: Initialize & Provision Infrastructure
```bash
cd terraform/gcp
terraform init
terraform apply \
  -var="gcp_project_id=YOUR_GCP_PROJECT_ID" \
  -var="db_password=YOUR_STRONG_DB_PASSWORD" \
  -var="jwt_secret=YOUR_JWT_SECRET"
```

#### Step 3: Build & Push Microservice Containers to Artifact Registry
```bash
gcloud auth configure-docker us-central1-docker.pkg.dev

for SERVICE in auth-service sync-api sharing-service security-analysis-service; do
  docker build -t us-central1-docker.pkg.dev/YOUR_GCP_PROJECT_ID/sentinelvault/$SERVICE:latest ../backend/$SERVICE
  docker push us-central1-docker.pkg.dev/YOUR_GCP_PROJECT_ID/sentinelvault/$SERVICE:latest
done
```

---

## Production Operations & Security Checklist

### 1. Database Backups & Disaster Recovery
Automate daily PostgreSQL backups using `pg_dump` pushed to encrypted storage:
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

## Summary & Final Recommendation

- **Best Value / Easiest**: Deploy **Option 1 (Single Hetzner/DigitalOcean VPS with Docker Compose)** for **~$8/month**.
- **Best Managed PaaS**: Deploy **Option 2 (Railway / Render)** for **~$30/month**.
- **Best Cloud Native Enterprise**: Deploy **Option 4 (GCP Cloud Run + Cloud SQL via Terraform)** for **~$87/month** or **Option 3 (AWS ECS Fargate via Terraform)** for **~$114/month**.
