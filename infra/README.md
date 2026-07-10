# Infrastructure for SentinelVault

This directory contains the Infrastructure as Code (IaC) configuration for deploying SentinelVault.

## Directory Structure
- `main.tf`: Provider and primary resource configuration.
- `variables.tf`: Configuration variables (regions, instance sizes, project names).

## Deployment Goals
- Provision virtual networks and secure subnets on the cloud platform.
- Deploy managed relational database instances (PostgreSQL) and managed cache engines (Redis).
- Setup secure container runtimes (such as GCP Cloud Run or AWS ECS Fargate) for backend services.
- Configure secure object storage for encrypted attachments.
