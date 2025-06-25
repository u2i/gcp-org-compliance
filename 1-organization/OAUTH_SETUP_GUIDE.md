# Tailscale OAuth Setup Guide

## Step 1: Create OAuth Application in Tailscale

1. **Go to Tailscale Admin Console**
   ```
   https://login.tailscale.com/admin/settings/oauth
   ```

2. **Click "Generate OAuth client"**

3. **Configure the OAuth Application:**
   - **Description**: `GCP Subnet Router Automation`
   - **Scopes**: Check only `devices:write`
   - Click "Generate client"

4. **Save the Credentials** (you'll see these only once!)
   - **Client ID**: Looks like `k8FqZ...` (short string)
   - **Client Secret**: Looks like `tskey-client-kYFqZ...` (longer string)

## Step 2: Configure Terraform

1. **Set OAuth credentials as environment variables:**
   ```bash
   export TF_VAR_tailscale_oauth_client_id="k8FqZ..."
   export TF_VAR_tailscale_oauth_client_secret="tskey-client-kYFqZ..."
   ```

2. **Update your tailnet name in terraform.tfvars:**
   ```hcl
   # Already set to u2i.com, but verify this matches your Tailscale organization
   tailscale_tailnet = "u2i.com"
   ```

   To find your tailnet name:
   - Go to https://login.tailscale.com/admin/settings/general
   - Look for "Tailnet name" - it's usually your domain or a unique ID

## Step 3: Deploy OAuth Infrastructure

```bash
cd gcp-org-compliance/1-organization

# First, let's create the project and OAuth infrastructure
terraform plan -target=google_project.tailscale \
  -target=google_secret_manager_secret.tailscale_oauth_client_id \
  -target=google_secret_manager_secret.tailscale_oauth_client_secret \
  -target=module.tailscale_oauth

terraform apply -target=google_project.tailscale \
  -target=google_secret_manager_secret.tailscale_oauth_client_id \
  -target=google_secret_manager_secret.tailscale_oauth_client_secret \
  -target=module.tailscale_oauth
```

## Step 4: Store OAuth Credentials in Secret Manager

```bash
# Get the project ID
PROJECT_ID=$(terraform output -raw tailscale_project_id)

# Store OAuth credentials
echo -n "${TF_VAR_tailscale_oauth_client_id}" | \
  gcloud secrets versions add tailscale-oauth-client-id \
  --project=${PROJECT_ID} --data-file=-

echo -n "${TF_VAR_tailscale_oauth_client_secret}" | \
  gcloud secrets versions add tailscale-oauth-client-secret \
  --project=${PROJECT_ID} --data-file=-
```

## Step 5: Create Initial Auth Key (One-Time)

Since the OAuth automation generates keys going forward, we need one initial key:

1. **Generate a temporary auth key:**
   - Go to: https://login.tailscale.com/admin/settings/keys
   - Click "Generate auth key"
   - Settings:
     - Reusable: ✓ Yes
     - Ephemeral: ✗ No  
     - Expiration: 90 days
     - Tags: `tag:subnet-router`
   - Click "Generate key"

2. **Store the initial key:**
   ```bash
   export INITIAL_KEY="tskey-auth-..."
   echo -n "${INITIAL_KEY}" | \
     gcloud secrets versions add tailscale-auth-key \
     --project=${PROJECT_ID} --data-file=-
   ```

## Step 6: Deploy Tailscale Routers

```bash
# Now deploy the actual routers
terraform apply
```

## Step 7: Verify OAuth Automation

1. **Check Cloud Function deployment:**
   ```bash
   gcloud functions describe tailscale-key-generator \
     --region=us-central1 \
     --project=${PROJECT_ID}
   ```

2. **Check Cloud Scheduler job:**
   ```bash
   gcloud scheduler jobs describe tailscale-key-rotation \
     --location=us-central1 \
     --project=${PROJECT_ID}
   ```

3. **Test key generation manually:**
   ```bash
   gcloud functions call tailscale-key-generator \
     --region=us-central1 \
     --project=${PROJECT_ID}
   ```

4. **Verify new key was created:**
   ```bash
   gcloud secrets versions list tailscale-auth-key \
     --project=${PROJECT_ID}
   ```

## Step 8: Approve Routes (One-Time)

1. Go to: https://login.tailscale.com/admin/machines
2. Find machines: `gcp-us-central1`, `gcp-europe-west1`, `gcp-europe-west4`
3. Approve advertised routes for each machine

## How It Works

1. **Monthly Rotation**: Cloud Scheduler triggers on the 1st of each month at 2 AM UTC
2. **OAuth Flow**: Cloud Function uses OAuth to authenticate with Tailscale API
3. **Key Generation**: Creates new 90-day auth key with appropriate tags
4. **Secret Update**: Stores new key in Secret Manager
5. **Router Updates**: Routers pick up new key on next restart/refresh

## Monitoring

Set up alerts for failed rotations:

```bash
gcloud alpha monitoring policies create \
  --notification-channels=YOUR_CHANNEL_ID \
  --display-name="Tailscale Key Rotation Failure" \
  --condition-display-name="Function Error" \
  --condition-filter='resource.type="cloud_function"
    resource.labels.function_name="tailscale-key-generator"
    severity>="ERROR"' \
  --project=${PROJECT_ID}
```

## Troubleshooting

### OAuth Token Issues
```bash
# Test OAuth manually
curl -X POST https://api.tailscale.com/api/v2/oauth/token \
  -u "${TF_VAR_tailscale_oauth_client_id}:${TF_VAR_tailscale_oauth_client_secret}" \
  -d "grant_type=client_credentials&scope=devices"
```

### Function Logs
```bash
gcloud functions logs read tailscale-key-generator \
  --region=us-central1 \
  --project=${PROJECT_ID} \
  --limit=50
```

### Force Key Rotation
```bash
# Manually trigger rotation
gcloud scheduler jobs run tailscale-key-rotation \
  --location=us-central1 \
  --project=${PROJECT_ID}
```

## Security Notes

- OAuth credentials are stored encrypted in Secret Manager
- Only the Cloud Function service account can access them
- Auth keys are automatically rotated monthly
- Old keys expire after 90 days
- All access is logged for audit

## Next Steps

1. ✅ OAuth automation is now active
2. 🔄 Keys will rotate automatically every month
3. 📊 Monitor the Cloud Function for any issues
4. 🔐 No more manual key management!

Your Tailscale infrastructure is now fully automated! 🎉