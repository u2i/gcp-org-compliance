# Config Connector Setup for GKE Clusters

## Overview
This adds Google Config Connector to both production and non-production GKE Autopilot clusters, enabling Kubernetes-native management of GCP resources.

## Changes Made

### 1. Enabled Config Connector Addon
Added `addons_config` block to both cluster definitions in `main.tf`:
- `google_container_cluster.prod_autopilot`
- `google_container_cluster.nonprod_autopilot`

### 2. Added Required APIs
Extended the API enablement list to include:
- `serviceusage.googleapis.com`
- `cloudresourcemanager.googleapis.com`

### 3. Created Service Accounts and IAM Setup
Created `config-connector-addon.tf` with:
- Service accounts for Config Connector in each project
- IAM bindings for resource management
- Workload Identity bindings

## Deployment Steps

1. **Review the changes**:
   ```bash
   cd gcp-org-compliance/2-shared-gke
   terraform plan
   ```

2. **Apply the changes**:
   ```bash
   terraform apply
   ```
   
   Note: This will update the GKE clusters, which may take 10-15 minutes.

3. **Verify Config Connector is running**:
   ```bash
   kubectl get pods -n cnrm-system
   ```

## Post-Deployment Configuration

After Config Connector is enabled, you'll need to:

1. **Configure Config Connector in each namespace**:
   ```yaml
   apiVersion: core.cnrm.cloud.google.com/v1beta1
   kind: ConfigConnectorContext
   metadata:
     name: configconnectorcontext.core.cnrm.cloud.google.com
     namespace: webapp-team
   spec:
     googleServiceAccount: "config-connector@u2i-gke-nonprod.iam.gserviceaccount.com"
   ```

2. **Grant permissions to tenant projects**:
   Config Connector in the GKE project needs permissions to create resources in tenant projects.

## Usage Example

Once configured, you can create GCP resources like this:

```yaml
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeAddress
metadata:
  name: webapp-static-ip
  namespace: webapp-team
spec:
  location: global
  project: u2i-tenant-webapp
```

## Security Considerations

- Config Connector service accounts currently have `roles/owner` for testing
- In production, reduce permissions to minimum required roles
- Use namespace-scoped ConfigConnectorContext for tenant isolation