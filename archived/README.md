# Archived Infrastructure

This directory contains archived infrastructure code that is no longer in use.

## 2-shared-gke

This directory previously contained the configuration for shared GKE clusters (u2i-gke-nonprod and u2i-gke-prod) that were used by multiple teams.

**Archived on**: June 22, 2025
**Reason**: Migrated from shared clusters to project-specific clusters. Each team now manages their own GKE clusters within their project boundaries.

The shared clusters have been destroyed, and all workloads have been migrated to dedicated clusters.

**Note**: The GKE projects (u2i-gke-network, u2i-gke-nonprod, u2i-gke-prod) still exist but are empty. They have deletion protection enabled and can be manually deleted if needed.

## 3-shared-gke

This directory contained the configuration for accessing the shared GKE clusters from tenant projects. It provided remote state access and namespace creation.

**Archived on**: June 22, 2025
**Reason**: No longer needed since shared clusters have been removed and teams now use project-specific clusters.