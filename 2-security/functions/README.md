# Cloud Functions for Security Phase

This directory contains Cloud Functions used in the security infrastructure.

## PAM Slack Notifier

Posts Google Cloud PAM (Privileged Access Manager) events to the `#audit-log` Slack channel as required by the GCP Break-Glass Policy v0.4.

### Features

- Processes PAM grant requests, approvals, denials, and revocations
- Posts color-coded messages to Slack for easy visibility
- Includes lane information and TTL details
- Provides audit trail for compliance

### Deployment

1. Build the function package:
   ```bash
   ./build.sh
   ```

2. Deploy via Terraform:
   ```bash
   cd ../..
   terraform apply
   ```

### Environment Variables

- `SLACK_WEBHOOK_URL`: Webhook URL for posting to Slack (required)
- `SLACK_CHANNEL`: Target channel (defaults to `#audit-log`)

### Message Types

- 🚨 **Orange**: PAM grant requested (pending approval)
- ✅ **Green**: PAM grant approved
- ❌ **Red**: PAM grant denied
- 🔒 **Grey**: PAM grant revoked
- ℹ️ **Blue**: Other PAM events

### Testing

To test locally:
```bash
cd pam-slack-notifier
npm install
# Set environment variables
export SLACK_WEBHOOK_URL="your-webhook-url"
# Run with test event
node -e "require('./index').handlePamEvent({data: Buffer.from(JSON.stringify({...})).toString('base64')})"
```