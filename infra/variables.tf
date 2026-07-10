variable "gcp_project_id" {
  description = "GCP Project ID to deploy SentinelVault resources"
  type        = string
  default     = "sentinelvault-placeholder-id"
}

variable "gcp_region" {
  description = "GCP Region for SentinelVault resources"
  type        = string
  default     = "us-central1"
}

variable "db_password" {
  description = "Administrator password for Cloud SQL PostgreSQL instance"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "Secret key used for signing session tokens / JWTs"
  type        = string
  sensitive   = true
}

variable "gemini_api_key" {
  description = "API key for Google Gemini model access"
  type        = string
  sensitive   = true
}

variable "virustotal_api_key" {
  description = "API key for VirusTotal reputation lookups"
  type        = string
  sensitive   = true
}

variable "hibp_api_key" {
  description = "API key for Have I Been Pwned checks"
  type        = string
  sensitive   = true
}

variable "vpc_connector_cidr" {
  description = "IP CIDR range for the Serverless VPC Connector"
  type        = string
  default     = "10.8.0.0/28"
}
