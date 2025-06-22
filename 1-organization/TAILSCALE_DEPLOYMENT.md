# Tailscale Organization Deployment Guide

## Overview

This deploys Tailscale subnet routers across your GCP organization, providing secure access to all private resources without traditional VPN.

## Prerequisites

1. **Tailscale Account**
   - Sign up at https://tailscale.com
   - Create or join your organization's tailnet

2. **Generate Auth Key**
   - Go to: https://login.tailscale.com/admin/settings/keys
   - Click "Generate auth key"
   - Settings:
     - Reusable: Yes (for multiple routers)
     - Expiration: 90 days
     - Tags: `tag:subnet-router` (if using ACLs)

## Deployment Steps

### 1. First-time Setup (with auth key)

```bash
# Export the auth key as environment variable
export TF_VAR_tailscale_auth_key="tskey-auth-XXXXXXXXXXXXXXXXXX"

# Initialize and plan
cd gcp-org-compliance/1-organization
terraform init
terraform plan -target=google_project.tailscale -target=google_secret_manager_secret.tailscale_auth_key

# Create the project and secret first
terraform apply -target=google_project.tailscale -target=google_secret_manager_secret.tailscale_auth_key

# Store the auth key in Secret Manager
echo -n "$TF_VAR_tailscale_auth_key" | gcloud secrets versions add tailscale-auth-key \
  --project=$(terraform output -raw tailscale_project_id) --data-file=-

# Now deploy the full infrastructure
terraform apply -target=module.tailscale_org_setup
```

### 2. Post-Deployment Configuration

#### Approve Routes in Tailscale Console

1. Go to: https://login.tailscale.com/admin/machines
2. Find machines named: `gcp-us-central1`, `gcp-europe-west1`, `gcp-europe-west4`
3. For each machine:
   - Click on the machine name
   - Find "Subnet routes" section
   - Click "Review" or "Edit route settings"
   - Enable all advertised routes:
     - `10.0.0.0/8`
     - `172.16.0.0/12`
     - `192.168.0.0/16`
     - `100.64.0.0/10`
   - Click "Save"

#### Configure ACLs (Optional but Recommended)

Edit your Tailscale ACL policy:

```json
{
  "tagOwners": {
    "tag:subnet-router": ["your-email@company.com"],
    "tag:gcp-access": ["group:engineering@company.com"]
  },
  "acls": [
    // Allow subnet routers to advertise routes
    {
      "action": "accept",
      "src": ["tag:subnet-router"],
      "dst": ["*:*"]
    },
    // Allow tagged users to access GCP resources
    {
      "action": "accept", 
      "src": ["tag:gcp-access"],
      "dst": ["10.0.0.0/8:*", "172.16.0.0/12:*", "100.64.0.0/10:*"]
    }
  ],
  "autoApprovers": {
    "routes": {
      "10.0.0.0/8": ["tag:subnet-router"],
      "172.16.0.0/12": ["tag:subnet-router"],
      "192.168.0.0/16": ["tag:subnet-router"],
      "100.64.0.0/10": ["tag:subnet-router"]
    }
  }
}
```

### 3. Test Connectivity

```bash
# Install Tailscale on your machine
# macOS: brew install tailscale
# Linux: curl -fsSL https://tailscale.com/install.sh | sh

# Connect to Tailscale
tailscale up

# Test access to GCP resources
# Example: Access a GKE NodePort service
curl http://10.128.0.5:30080

# Example: SSH to a Compute Engine instance
ssh user@10.132.0.2

# Example: Access Cloud SQL
psql -h 10.20.30.40 -U postgres -d mydb
```

## Managing Auth Keys

### Rotate Auth Key

```bash
# Generate new key at https://login.tailscale.com/admin/settings/keys

# Update in Secret Manager
echo -n "tskey-auth-NEWKEY" | gcloud secrets versions add tailscale-auth-key \
  --project=$(terraform output -raw tailscale_project_id) --data-file=-

# Restart instances to pick up new key
gcloud compute instances reset tailscale-router-us-central1 --zone=us-central1-a
gcloud compute instances reset tailscale-router-europe-west1 --zone=europe-west1-a
gcloud compute instances reset tailscale-router-europe-west4 --zone=europe-west4-a
```

### View Current Key (Emergency Only)

```bash
gcloud secrets versions access latest --secret=tailscale-auth-key \
  --project=$(terraform output -raw tailscale_project_id)
```

## Troubleshooting

### Router Not Appearing in Admin Console

```bash
# SSH to router instance
gcloud compute ssh tailscale-router-europe-west1 --zone=europe-west1-a \
  --project=$(terraform output -raw tailscale_project_id)

# Check Tailscale status
sudo tailscale status
sudo journalctl -u tailscaled -n 100

# Check if auth key was retrieved
sudo journalctl -t tailscale-setup
```

### Routes Not Working

1. Verify routes are approved in admin console
2. Check firewall rules allow traffic
3. Test with `tailscale ping` to router:
   ```bash
   tailscale ping gcp-europe-west1
   ```

### Access Denied

1. Check ACLs in Tailscale admin
2. Verify your user/device has appropriate tags
3. Test with `tailscale netcheck`

## Cost Optimization

Current setup uses e2-micro instances (~$8/month each). For production consider:

1. **Preemptible instances** for 80% cost reduction
2. **Autoscaling** based on traffic
3. **Regional distribution** - only deploy where needed

## Security Best Practices

1. **Use ACL tags** instead of allowing all access
2. **Enable MFA** on Tailscale account
3. **Rotate auth keys** every 90 days
4. **Monitor access logs** in both Tailscale and GCP
5. **Use device authorization** for additional security

## Next Steps

1. Install Tailscale on developer machines
2. Create team-specific ACL policies
3. Document access procedures for your team
4. Set up monitoring alerts for router health
5. Plan auth key rotation schedule