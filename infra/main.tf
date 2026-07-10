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

# ── Enable GCP Services ────────────────────────────────────────────────────
resource "google_project_service" "services" {
  for_each = toset([
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "redis.googleapis.com",
    "secretmanager.googleapis.com",
    "vpcaccess.googleapis.com",
    "artifactregistry.googleapis.com",
    "compute.googleapis.com",
  ])
  service            = each.key
  disable_on_destroy = false
}

# ── Networking & Serverless VPC Connector ─────────────────────────────────
resource "google_compute_network" "vpc_network" {
  name                    = "sentinelvault-vpc"
  auto_create_subnetworks = true
  depends_on              = [google_project_service.services]
}

resource "google_vpc_access_connector" "vpc_connector" {
  name          = "sentinelvault-conn"
  region        = var.gcp_region
  ip_cidr_range = var.vpc_connector_cidr
  network       = google_compute_network.vpc_network.name
  depends_on    = [google_project_service.services]
}

# ── GCP Secrets Manager Configuration ─────────────────────────────────────
resource "google_secret_manager_secret" "db_password" {
  secret_id  = "sentinelvault-db-password"
  depends_on = [google_project_service.services]
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret = google_secret_manager_secret.db_password.id
  secret_data = var.db_password
}

resource "google_secret_manager_secret" "jwt_secret" {
  secret_id  = "sentinelvault-jwt-secret"
  depends_on = [google_project_service.services]
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "jwt_secret" {
  secret = google_secret_manager_secret.jwt_secret.id
  secret_data = var.jwt_secret
}

resource "google_secret_manager_secret" "gemini_key" {
  secret_id  = "sentinelvault-gemini-key"
  depends_on = [google_project_service.services]
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "gemini_key" {
  secret = google_secret_manager_secret.gemini_key.id
  secret_data = var.gemini_api_key
}

resource "google_secret_manager_secret" "virustotal_key" {
  secret_id  = "sentinelvault-virustotal-key"
  depends_on = [google_project_service.services]
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "virustotal_key" {
  secret = google_secret_manager_secret.virustotal_key.id
  secret_data = var.virustotal_api_key
}

resource "google_secret_manager_secret" "hibp_key" {
  secret_id  = "sentinelvault-hibp-key"
  depends_on = [google_project_service.services]
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "hibp_key" {
  secret = google_secret_manager_secret.hibp_key.id
  secret_data = var.hibp_api_key
}

# ── Artifact Registry for Docker Images ────────────────────────────────────
resource "google_artifact_registry_repository" "repo" {
  location      = var.gcp_region
  repository_id = "sentinelvault-images"
  description   = "Docker repository for SentinelVault microservices"
  format        = "DOCKER"
  depends_on    = [google_project_service.services]
}

# ── Cloud SQL PostgreSQL Instance ──────────────────────────────────────────
resource "google_sql_database_instance" "postgres" {
  name             = "sentinelvault-postgres"
  database_version = "POSTGRES_15"
  region           = var.gcp_region
  depends_on       = [google_project_service.services]

  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled = true # Enabled for demos; production would use private IP VPC peering
    }
  }
  deletion_protection = false
}

resource "google_sql_user" "db_user" {
  name     = "sentinel_admin"
  instance = google_sql_database_instance.postgres.name
  password = var.db_password
}

# ── Cloud Memorystore Redis ───────────────────────────────────────────────
resource "google_redis_instance" "redis" {
  name               = "sentinelvault-redis"
  tier               = "BASIC"
  memory_size_gb     = 1
  region             = var.gcp_region
  authorized_network = google_compute_network.vpc_network.id
  connect_mode       = "DIRECT_PEERING"
  depends_on         = [google_project_service.services]
}

# ── Cloud Storage (Object Storage) ─────────────────────────────────────────
resource "google_storage_bucket" "object_store" {
  name                        = "${var.gcp_project_id}-vault-storage"
  location                    = var.gcp_region
  uniform_bucket_level_access = true
  force_destroy               = true
  depends_on                  = [google_project_service.services]
}

# ── Cloud Run Services ─────────────────────────────────────────────────────

# 1. Auth Service
resource "google_cloud_run_v2_service" "auth_service" {
  name     = "auth-service"
  location = var.gcp_region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    vpc_access {
      connector = google_vpc_access_connector.vpc_connector.id
      egress    = "ALL_TRAFFIC"
    }

    containers {
      image = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/sentinelvault-images/auth-service:latest"

      ports {
        container_port = 3001
      }

      env {
        name  = "PORT"
        value = "3001"
      }

      env {
        name  = "DATABASE_URL"
        value = "postgresql://${google_sql_user.db_user.name}:${var.db_password}@${google_sql_database_instance.postgres.public_ip_address}:5432/sentinelvault"
      }

      env {
        name  = "REDIS_URL"
        value = "redis://${google_redis_instance.redis.host}:${google_redis_instance.redis.port}"
      }

      env {
        name = "JWT_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.jwt_secret.secret_id
            version = "latest"
          }
        }
      }
    }
  }
}

# 2. Security Analysis Service
resource "google_cloud_run_v2_service" "security_service" {
  name     = "security-analysis-service"
  location = var.gcp_region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    vpc_access {
      connector = google_vpc_access_connector.vpc_connector.id
      egress    = "ALL_TRAFFIC"
    }

    containers {
      image = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/sentinelvault-images/security-analysis-service:latest"

      ports {
        container_port = 3003
      }

      env {
        name  = "PORT"
        value = "3003"
      }

      env {
        name  = "REDIS_URL"
        value = "redis://${google_redis_instance.redis.host}:${google_redis_instance.redis.port}"
      }

      env {
        name = "GEMINI_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.gemini_key.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "VIRUSTOTAL_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.virustotal_key.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "HIBP_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.hibp_key.secret_id
            version = "latest"
          }
        }
      }
    }
  }
}

# 3. Sync API Service
resource "google_cloud_run_v2_service" "sync_service" {
  name     = "sync-api"
  location = var.gcp_region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    vpc_access {
      connector = google_vpc_access_connector.vpc_connector.id
      egress    = "ALL_TRAFFIC"
    }

    containers {
      image = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/sentinelvault-images/sync-api:latest"

      ports {
        container_port = 3002
      }

      env {
        name  = "PORT"
        value = "3002"
      }

      env {
        name  = "DATABASE_URL"
        value = "postgresql://${google_sql_user.db_user.name}:${var.db_password}@${google_sql_database_instance.postgres.public_ip_address}:5432/sentinelvault"
      }

      env {
        name  = "REDIS_URL"
        value = "redis://${google_redis_instance.redis.host}:${google_redis_instance.redis.port}"
      }

      env {
        name = "JWT_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.jwt_secret.secret_id
            version = "latest"
          }
        }
      }
    }
  }
}

# ── IAM Permissions to read Secret Manager ─────────────────────────────────
resource "google_secret_manager_secret_iam_member" "auth_jwt_secret_access" {
  secret_id  = google_secret_manager_secret.jwt_secret.secret_id
  role       = "roles/secretmanager.secretAccessor"
  member     = "serviceAccount:${google_cloud_run_v2_service.auth_service.template[0].service_account}"
}

resource "google_secret_manager_secret_iam_member" "sync_jwt_secret_access" {
  secret_id  = google_secret_manager_secret.jwt_secret.secret_id
  role       = "roles/secretmanager.secretAccessor"
  member     = "serviceAccount:${google_cloud_run_v2_service.sync_service.template[0].service_account}"
}

resource "google_secret_manager_secret_iam_member" "security_gemini_access" {
  secret_id  = google_secret_manager_secret.gemini_key.secret_id
  role       = "roles/secretmanager.secretAccessor"
  member     = "serviceAccount:${google_cloud_run_v2_service.security_service.template[0].service_account}"
}

resource "google_secret_manager_secret_iam_member" "security_vt_access" {
  secret_id  = google_secret_manager_secret.virustotal_key.secret_id
  role       = "roles/secretmanager.secretAccessor"
  member     = "serviceAccount:${google_cloud_run_v2_service.security_service.template[0].service_account}"
}

resource "google_secret_manager_secret_iam_member" "security_hibp_access" {
  secret_id  = google_secret_manager_secret.hibp_key.secret_id
  role       = "roles/secretmanager.secretAccessor"
  member     = "serviceAccount:${google_cloud_run_v2_service.security_service.template[0].service_account}"
}
