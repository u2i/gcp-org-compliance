# Tailscale Without Manual Key Rotation

## Overview

There are three main approaches to avoid manual auth key rotation every 90 days:

### 1. **OAuth Application** (Fully Automated)
- Create OAuth app in Tailscale
- Cloud Function auto-generates keys monthly
- Zero manual intervention

### 2. **Device Authorization** (Semi-Automated)
- Each VM authorizes itself
- One-time manual approval per device
- No keys to rotate

### 3. **Tailscale Operator** (For Kubernetes)
- Uses OAuth for K8s workloads
- Automatic service exposure
- No manual key management

## Option 1: OAuth Application (Recommended)

### Setup Steps

1. **Create OAuth Application**
   ```
   https://login.tailscale.com/admin/settings/oauth
   ```
   - Click "Generate OAuth client"
   - Name: "GCP Subnet Routers"
   - Add scope: `devices:write`
   - Save Client ID and Secret

2. **Enable in Terraform**
   ```hcl
   # terraform.tfvars
   enable_auto_key_rotation = true
   tailscale_tailnet = "your-org.com"  # or tailnet ID
   tailscale_oauth_client_id = "k8FqZ..."
   tailscale_oauth_client_secret = "ts_oauth_client_secret_..."
   ```

3. **Deploy**
   ```bash
   terraform apply
   ```

4. **Store OAuth Credentials**
   ```bash
   # Store in Secret Manager
   echo -n "k8FqZ..." | gcloud secrets versions add tailscale-oauth-client-id \
     --project=$(terraform output -raw tailscale_project_id) --data-file=-
   
   echo -n "ts_oauth_client_secret_..." | gcloud secrets versions add tailscale-oauth-client-secret \
     --project=$(terraform output -raw tailscale_project_id) --data-file=-
   ```

### How It Works

- Cloud Scheduler runs monthly
- Cloud Function uses OAuth to generate new key
- Updates Secret Manager automatically
- Routers pick up new key on restart

## Option 2: Device Authorization (Simplest)

### Setup Steps

1. **Enable Device Auth Mode**
   ```hcl
   # terraform.tfvars
   use_device_authorization = true
   tailscale_tailnet = "your-org.com"
   ```

2. **Deploy Routers**
   ```bash
   terraform apply
   ```

3. **Authorize Each Router** (One-time)
   ```bash
   # Get auth URLs from each instance
   gcloud compute ssh tailscale-router-us-central1 --command="cat /var/log/tailscale-auth-url.txt"
   # Visit the URL and click "Authorize"
   ```

### Monitoring Auth Requests

Set up log-based alert:
```bash
gcloud logging metrics create tailscale-auth-required \
  --log-filter='resource.type="gce_instance"
  jsonPayload.message="Tailscale device authorization required"' \
  --project=$(terraform output -raw tailscale_project_id)
```

## Option 3: Hybrid Approach

Use OAuth for automated key generation but with longer-lived keys:

```python
# In the Cloud Function, modify expiry:
"expirySeconds": 365 * 24 * 60 * 60,  # 1 year instead of 90 days
```

## Comparison

| Method | Pros | Cons | Best For |
|--------|------|------|----------|
| **OAuth** | Fully automated, no manual work | Requires OAuth setup | Production environments |
| **Device Auth** | Simple, no keys needed | Manual approval per device | Small deployments |
| **Long-lived Keys** | Less frequent rotation | Still needs eventual rotation | Intermediate option |

## Security Considerations

### OAuth Method
- Store OAuth credentials in Secret Manager
- Limit OAuth app permissions to minimum needed
- Monitor OAuth token usage

### Device Authorization
- Devices appear as "Awaiting approval" in admin
- Can bulk-approve with Tailscale API
- Set up alerts for new devices

## Troubleshooting

### OAuth Issues
```bash
# Test OAuth token generation
curl -X POST https://api.tailscale.com/api/v2/oauth/token \
  -u "CLIENT_ID:CLIENT_SECRET" \
  -d "grant_type=client_credentials&scope=devices"

# Check Cloud Function logs
gcloud functions logs read tailscale-key-generator --limit=50
```

### Device Auth Issues
```bash
# Check if device is waiting for auth
tailscale status

# Re-trigger authorization
tailscale up --force-reauth
```

## Migration Path

1. Start with manual keys (quickest setup)
2. Set up OAuth application
3. Enable auto-rotation
4. Monitor for a cycle
5. Disable manual key usage

## Example: Full OAuth Setup

```bash
# 1. Create OAuth app at tailscale.com
# 2. Export credentials
export TF_VAR_tailscale_oauth_client_id="k8FqZ..."
export TF_VAR_tailscale_oauth_client_secret="ts_oauth_client_secret_..."

# 3. Update terraform.tfvars
cat >> terraform.tfvars <<EOF
enable_auto_key_rotation = true
tailscale_tailnet = "example.com"
EOF

# 4. Apply changes
terraform apply

# 5. Verify Cloud Function
gcloud functions describe tailscale-key-generator

# 6. Test key generation
gcloud functions call tailscale-key-generator

# 7. Check new key in Secret Manager
gcloud secrets versions list tailscale-auth-key
```

No more manual key rotation! 🎉