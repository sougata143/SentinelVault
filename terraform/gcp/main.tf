# ==============================================================================
# SentinelVault — GCP Infrastructure Provisioning (Terraform)
# ==============================================================================
# Provisions:
# 1. VPC Network and Subnetworks
# 2. Cloud SQL PostgreSQL 15 Instance
# 3. Memorystore Redis Instance
# 4. Artifact Registry Docker Repository
# 5. Cloud Run v2 Services for 4 Microservices (Auth, Sync, Sharing, Security)
# 6. GCS Bucket and Cloud CDN for Flutter Web App Frontend
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# ------------------------------------------------------------------------------
# Variables
# ------------------------------------------------------------------------------
variable "gcp_project_id" {
  type        = string
  description = "GCP Project ID"
}

variable "gcp_region" {
  type        = string
  default     = "us-central1"
  description = "GCP Region for deployment"
}

variable "environment" {
  type        = string
  default     = "production"
  description = "Deployment environment name"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "Master password for Cloud SQL PostgreSQL"
}

variable "jwt_secret" {
  type        = string
  sensitive   = true
  description = "JWT Secret Key for microservices"
}

# ------------------------------------------------------------------------------
# 1. VPC Network Infrastructure
# ------------------------------------------------------------------------------
resource "google_compute_network" "vpc" {
  name                    = "sentinelvault-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "sentinelvault-subnet"
  ip_cidr_range = "10.0.0.0/20"
  region        = var.gcp_region
  network       = google_compute_network.vpc.id
}

# Private IP allocation for Cloud SQL
resource "google_compute_global_address" "private_ip_address" {
  name          = "sentinelvault-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

# ------------------------------------------------------------------------------
# 2. Artifact Registry for Container Images
# ------------------------------------------------------------------------------
resource "google_artifact_registry_repository" "repo" {
  location      = var.gcp_region
  repository_id = "sentinelvault"
  description   = "Docker repository for SentinelVault microservices"
  format        = "DOCKER"
}

# ------------------------------------------------------------------------------
# 3. Cloud SQL PostgreSQL 15 Instance
# ------------------------------------------------------------------------------
resource "google_sql_database_instance" "postgres" {
  name             = "sentinelvault-postgres"
  database_version = "POSTGRES_15"
  region           = var.gcp_region

  depends_on = [google_service_networking_connection.private_vpc_connection]

  settings {
    tier = "db-custom-2-7680" # 2 vCPU, 7.5 GB RAM

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
    }

    backup_configuration {
      enabled    = true
      start_time = "03:00"
    }
  }
}

resource "google_sql_database" "database" {
  name     = "sentinelvault"
  instance = google_sql_database_instance.postgres.name
}

resource "google_sql_user" "users" {
  name     = "sentinel_admin"
  instance = google_sql_database_instance.postgres.name
  password = var.db_password
}

# ------------------------------------------------------------------------------
# 4. Memorystore for Redis
# ------------------------------------------------------------------------------
resource "google_redis_instance" "cache" {
  name               = "sentinelvault-redis"
  tier               = "BASIC"
  memory_size_gb     = 2
  region             = var.gcp_region
  authorized_network = google_compute_network.vpc.id
  redis_version      = "REDIS_7_0"
}

# ------------------------------------------------------------------------------
# 5. VPC Connector for Cloud Run Services
# ------------------------------------------------------------------------------
resource "google_vpc_access_connector" "connector" {
  name          = "sentinelvault-vpc-conn"
  region        = var.gcp_region
  ip_cidr_range = "10.8.0.0/28"
  network       = google_compute_network.vpc.name
}

# ------------------------------------------------------------------------------
# 6. Cloud Run v2 Services (Microservices)
# ------------------------------------------------------------------------------

# Auth Service
resource "google_cloud_run_v2_service" "auth_service" {
  name     = "sentinelvault-auth"
  location = var.gcp_region

  template {
    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "ALL_TRAFFIC"
    }

    containers {
      image = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/sentinelvault/auth-service:latest"

      ports { container_port = 3001 }

      env {
        name  = "DATABASE_URL"
        value = "postgres://sentinel_admin:${var.db_password}@${google_sql_database_instance.postgres.private_ip_address}:5432/sentinelvault"
      }
      env {
        name  = "REDIS_URL"
        value = "redis://${google_redis_instance.cache.host}:${google_redis_instance.cache.port}"
      }
      env {
        name  = "JWT_SECRET"
        value = var.jwt_secret
      }
      env {
        name  = "AUTH_PORT"
        value = "3001"
      }
    }
  }
}

# Sync API Service
resource "google_cloud_run_v2_service" "sync_api" {
  name     = "sentinelvault-sync"
  location = var.gcp_region

  template {
    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "ALL_TRAFFIC"
    }

    containers {
      image = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/sentinelvault/sync-api:latest"

      ports { container_port = 3002 }

      env {
        name  = "DATABASE_URL"
        value = "postgres://sentinel_admin:${var.db_password}@${google_sql_database_instance.postgres.private_ip_address}:5432/sentinelvault"
      }
      env {
        name  = "REDIS_URL"
        value = "redis://${google_redis_instance.cache.host}:${google_redis_instance.cache.port}"
      }
      env {
        name  = "JWT_SECRET"
        value = var.jwt_secret
      }
      env {
        name  = "SYNC_PORT"
        value = "3002"
      }
    }
  }
}

# Sharing Service
resource "google_cloud_run_v2_service" "sharing_service" {
  name     = "sentinelvault-sharing"
  location = var.gcp_region

  template {
    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "ALL_TRAFFIC"
    }

    containers {
      image = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/sentinelvault/sharing-service:latest"

      ports { container_port = 3004 }

      env {
        name  = "DATABASE_URL"
        value = "postgres://sentinel_admin:${var.db_password}@${google_sql_database_instance.postgres.private_ip_address}:5432/sentinelvault"
      }
      env {
        name  = "REDIS_URL"
        value = "redis://${google_redis_instance.cache.host}:${google_redis_instance.cache.port}"
      }
      env {
        name  = "JWT_SECRET"
        value = var.jwt_secret
      }
      env {
        name  = "SHARING_PORT"
        value = "3004"
      }
    }
  }
}

# Security Analysis Service
resource "google_cloud_run_v2_service" "security_analysis" {
  name     = "sentinelvault-security"
  location = var.gcp_region

  template {
    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "ALL_TRAFFIC"
    }

    containers {
      image = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/sentinelvault/security-analysis-service:latest"

      ports { container_port = 3003 }

      env {
        name  = "DATABASE_URL"
        value = "postgres://sentinel_admin:${var.db_password}@${google_sql_database_instance.postgres.private_ip_address}:5432/sentinelvault"
      }
      env {
        name  = "REDIS_URL"
        value = "redis://${google_redis_instance.cache.host}:${google_redis_instance.cache.port}"
      }
      env {
        name  = "JWT_SECRET"
        value = var.jwt_secret
      }
      env {
        name  = "SECURITY_ANALYSIS_PORT"
        value = "3003"
      }
    }
  }
}

# Allow public invocations for Cloud Run services
resource "google_cloud_run_service_iam_binding" "public_auth" {
  location = var.gcp_region
  service  = google_cloud_run_v2_service.auth_service.name
  role     = "roles/run.invoker"
  members  = ["allUsers"]
}

resource "google_cloud_run_service_iam_binding" "public_sync" {
  location = var.gcp_region
  service  = google_cloud_run_v2_service.sync_api.name
  role     = "roles/run.invoker"
  members  = ["allUsers"]
}

# ------------------------------------------------------------------------------
# 7. Cloud Storage & Cloud CDN for Flutter Web Client
# ------------------------------------------------------------------------------
resource "google_storage_bucket" "frontend" {
  name                        = "sentinelvault-frontend-${var.gcp_project_id}"
  location                    = var.gcp_region
  uniform_bucket_level_access = true

  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html"
  }
}

resource "google_storage_bucket_iam_binding" "public_read" {
  bucket  = google_storage_bucket.frontend.name
  role    = "roles/storage.objectViewer"
  members = ["allUsers"]
}

# ------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------
output "cloud_sql_private_ip" {
  value       = google_sql_database_instance.postgres.private_ip_address
  description = "Private IP of Cloud SQL PostgreSQL instance"
}

output "redis_host" {
  value       = google_redis_instance.cache.host
  description = "Host IP of Memorystore Redis instance"
}

output "auth_service_url" {
  value       = google_cloud_run_v2_service.auth_service.uri
  description = "Public URL for Auth Microservice"
}

output "sync_service_url" {
  value       = google_cloud_run_v2_service.sync_api.uri
  description = "Public URL for Sync API Microservice"
}

output "frontend_gcs_url" {
  value       = "https://storage.googleapis.com/${google_storage_bucket.frontend.name}/index.html"
  description = "GCS Storage URL for Flutter Web Frontend"
}
