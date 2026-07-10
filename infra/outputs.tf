output "artifact_registry_repo" {
  description = "The URI of the Docker repository in Artifact Registry"
  value       = google_artifact_registry_repository.repo.name
}

output "postgres_connection_name" {
  description = "The Connection Name of the Cloud SQL PostgreSQL instance"
  value       = google_sql_database_instance.postgres.connection_name
}

output "postgres_public_ip" {
  description = "The public IP address of the Cloud SQL PostgreSQL instance"
  value       = google_sql_database_instance.postgres.public_ip_address
}

output "redis_host" {
  description = "The host of the Memorystore Redis instance"
  value       = google_redis_instance.redis.host
}

output "gcs_bucket_name" {
  description = "The name of the GCS bucket used for object storage"
  value       = google_storage_bucket.object_store.name
}

output "auth_service_url" {
  description = "The URL of the deployed Auth Service Cloud Run instance"
  value       = google_cloud_run_v2_service.auth_service.uri
}

output "security_service_url" {
  description = "The URL of the deployed Security Analysis Service Cloud Run instance"
  value       = google_cloud_run_v2_service.security_service.uri
}

output "sync_service_url" {
  description = "The URL of the deployed Sync API Service Cloud Run instance"
  value       = google_cloud_run_v2_service.sync_service.uri
}
