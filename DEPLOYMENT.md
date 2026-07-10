# SentinelVault Deployment Guide

This document describes how to deploy the SentinelVault zero-knowledge password manager backend services to Google Cloud Platform (GCP) using Terraform, configure required secrets, and set up the GitHub Actions CI pipeline.

---

## 🏗️ Architecture Overview

The production infrastructure deployed via [infra/](file:///Users/sougataroy/Downloads/Kaggle%20Antigravity/SentinelVault/infra/) consists of:
1. **Google Cloud Run**: Serverless deployment for the three microservices:
   - `auth-service` (port `3001`)
   - `sync-api` (port `3002`)
   - `security-analysis-service` (port `3003`)
2. **Cloud SQL (PostgreSQL)**: Managed relational database for storing user verification credentials (salt, SRP verifier) and encrypted vault items.
3. **Memorystore (Redis)**: Cache instance for session management and token blacklisting.
4. **Cloud Storage (GCS)**: Bucket for storing uploaded files that pass reputation scanning (for user file secure storage).
5. **Secrets Manager**: Centralized, secure storage for sensitive API keys and tokens.
6. **Serverless VPC Access Connector**: Required to allow Cloud Run microservices to safely communicate with Postgres and Redis over private GCP networks.

---

## 🛠️ Local Prerequisites

Before deploying the infrastructure, install the following tools locally:
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install)
- [Terraform CLI (>= 1.5.0)](https://developer.hashicorp.com/terraform/downloads)
- [Docker](https://docs.docker.com/get-docker/)

---

## 🔑 GCP Authentication Setup

1. Log into your Google Cloud account:
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```
2. Create or select a GCP project and set it locally:
   ```bash
   gcloud config set project YOUR_PROJECT_ID
   ```
3. Create a Service Account for Terraform and grant it `Owner` permissions:
   ```bash
   gcloud iam service-accounts create terraform-deployer --display-name="Terraform Deployer"
   gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
     --member="serviceAccount:terraform-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
     --role="roles/owner"
   ```
4. Generate a Service Account JSON Key and save it locally:
   ```bash
   gcloud iam service-accounts keys create terraform-key.json \
     --iam-account=terraform-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com
   ```
5. Export the key file path:
   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS="$(pwd)/terraform-key.json"
   ```

---

## 🚀 Deploying Infrastructure with Terraform

1. Navigate to the `infra` directory:
   ```bash
   cd infra
   ```
2. Create a `terraform.tfvars` file to supply the sensitive credentials (never commit this file):
   ```hcl
   gcp_project_id      = "YOUR_PROJECT_ID"
   gcp_region          = "us-central1"
   db_password         = "SecurePostgresPassword123!"
   jwt_secret          = "YourSuperSecretJWTSigningToken"
   gemini_api_key      = "AIzaSy..." # Google Gemini API key
   virustotal_api_key  = "vt_api_key_..." # VirusTotal API Key
   hibp_api_key        = "hibp_api_key_..." # Have I Been Pwned API Key
   ```
3. Initialize Terraform:
   ```bash
   terraform init
   ```
4. Preview the resources to be created:
   ```bash
   terraform plan
   ```
5. Apply the configuration to deploy the infrastructure:
   ```bash
   terraform apply
   ```
   *Verify the outputs after completion (Cloud Run Service URLs, database connections).*

---

## 🐳 Building and Pushing Container Images

After Terraform creates the Artifact Registry repository, build and push your backend Docker images:

1. Authenticate Docker with GCP Artifact Registry:
   ```bash
   gcloud auth configure-docker us-central1-docker.pkg.dev
   ```
2. Build, tag, and push each service:
   ```bash
   # Auth Service
   cd ../backend/auth-service
   docker build -t us-central1-docker.pkg.dev/YOUR_PROJECT_ID/sentinelvault-images/auth-service:latest .
   docker push us-central1-docker.pkg.dev/YOUR_PROJECT_ID/sentinelvault-images/auth-service:latest

   # Sync API
   cd ../sync-api
   docker build -t us-central1-docker.pkg.dev/YOUR_PROJECT_ID/sentinelvault-images/sync-api:latest .
   docker push us-central1-docker.pkg.dev/YOUR_PROJECT_ID/sentinelvault-images/sync-api:latest

   # Security Analysis Service
   cd ../security-analysis-service
   docker build -t us-central1-docker.pkg.dev/YOUR_PROJECT_ID/sentinelvault-images/security-analysis-service:latest .
   docker push us-central1-docker.pkg.dev/YOUR_PROJECT_ID/sentinelvault-images/security-analysis-service:latest
   ```
3. Redeploy the Cloud Run services to pull the new images:
   ```bash
   gcloud run deploy auth-service --image=us-central1-docker.pkg.dev/YOUR_PROJECT_ID/sentinelvault-images/auth-service:latest --region=us-central1
   gcloud run deploy sync-api --image=us-central1-docker.pkg.dev/YOUR_PROJECT_ID/sentinelvault-images/sync-api:latest --region=us-central1
   gcloud run deploy security-analysis-service --image=us-central1-docker.pkg.dev/YOUR_PROJECT_ID/sentinelvault-images/security-analysis-service:latest --region=us-central1
   ```

---

## 🤖 CI Pipeline Setup (GitHub Actions)

The [.github/workflows/ci.yml](file:///Users/sougataroy/Downloads/Kaggle%20Antigravity/SentinelVault/.github/workflows/ci.yml) workflow automatically runs on every Push and Pull Request targeting `main` or `master`.

### Enforcing Merging Invariant
To ensure no failing code can be merged into production:
1. In your GitHub Repository, navigate to **Settings** > **Branches**.
2. Under **Branch protection rules**, click **Add rule** for the `main`/`master` branch.
3. Check the option: **"Require status checks to pass before merging"**.
4. Search for and select the following status check jobs:
   - `Flutter Core and App Tests`
   - `Node.js Backend Tests (auth-service)`
   - `Node.js Backend Tests (security-analysis-service)`
   - `Node.js Backend Tests (sync-api)`
5. Save the protection rule. Merges will now be blocked automatically on test failures.
