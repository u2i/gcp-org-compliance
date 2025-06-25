# Slack Setup Guide for PAM Notifications

This guide walks you through setting up a Slack app to receive PAM audit notifications.

## Step 1: Create the Slack App

1. Go to https://api.slack.com/apps
2. Click **Create New App**
3. Choose **From an app manifest**
4. Select your workspace
5. Paste this manifest:

```yaml
display_information:
  name: GCP PAM Audit Bot
  description: Posts PAM grant requests and decisions to audit channels
  background_color: "#1a73e8"
features:
  bot_user:
    display_name: PAM Audit Bot
    always_online: true
oauth_config:
  scopes:
    bot:
      - channels:join
      - channels:read
      - chat:write
      - chat:write.public
      - files:write
      - groups:read
      - groups:write
      - im:write
      - users:read
      - users:read.email
settings:
  org_deploy_enabled: false
  socket_mode_enabled: false
  token_rotation_enabled: false
```

6. Click **Next** → **Create**

## Step 2: Install the App

1. In your app settings, go to **OAuth & Permissions**
2. Click **Install to Workspace**
3. Review permissions and click **Allow**
4. Copy the **Bot User OAuth Token** (starts with `xoxb-`)

## Step 3: Store the Token in Secret Manager

```bash
# Create the secret
echo -n "xoxb-your-token-here" | gcloud secrets create slack-pam-bot-token \
  --project=u2i-security \
  --replication-policy="automatic" \
  --data-file=-

# Note: Cloud Function access is already configured via Terraform
```

## Step 4: Create the #audit-log Channel

1. In Slack, create a new channel named `#audit-log`
2. Make it **Private** (recommended)
3. **IMPORTANT**: Add the PAM Audit Bot to the channel:
   - Type `/invite @PAM Audit Bot` in the channel
   - Or click the channel name → Settings → Add apps → Search for "PAM Audit Bot"
   - The bot MUST be invited to see private channels

## Step 5: Deploy the Cloud Function

```bash
cd /Users/tom/dev/org-migrate-workdir/gcp-org-compliance/2-security
terraform apply -target=google_cloudfunctions_function.pam_slack_notifier
```

## Step 6: Test the Integration

1. **Test Bot Connection**:
   ```bash
   curl -X POST https://slack.com/api/chat.postMessage \
     -H "Authorization: Bearer xoxb-your-token" \
     -H "Content-type: application/json" \
     -d '{
       "channel": "#audit-log",
       "text": "✅ PAM Bot successfully connected!"
     }'
   ```

2. **Test PAM Integration**:
   ```bash
   # Create a test grant request
   gcloud pam grants create \
     --entitlement="jit-deploy" \
     --justification="Testing Slack integration" \
     --requested-duration="1800s" \
     --location="global" \
     --organization="981978971260"
   ```

3. Check `#audit-log` for the notification

## Troubleshooting

### Bot Not Posting Messages

1. Check Cloud Function logs:
   ```bash
   gcloud functions logs read pam-slack-notifier --limit=50
   ```

2. Verify bot is in channel:
   - In Slack, type `/who` in #audit-log
   - Should show PAM Audit Bot as a member

3. Test token directly:
   ```bash
   curl -H "Authorization: Bearer xoxb-your-token" \
     https://slack.com/api/auth.test
   ```

### Permission Errors

- Ensure bot was added to #audit-log channel
- Verify all OAuth scopes are granted
- Check Secret Manager permissions

## Security Notes

- Rotate the bot token quarterly
- Keep #audit-log channel private
- Never commit tokens to git
- Monitor bot activity in Slack audit logs