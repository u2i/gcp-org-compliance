# U2I Centralized Slack Approval Handler

This Cloud Function handles Slack approval interactions for all U2I infrastructure changes across multiple projects.

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Slack User    │    │   Cloud Function │    │  GitHub Actions │
│   Clicks Button │───▶│  Approval Handler│───▶│   Workflows     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌──────────────────┐
                       │   GCS Bucket     │
                       │ (Approval Store) │
                       └──────────────────┘
```

## Supported Projects

- **webapp-team-infrastructure** - WebApp team tenant infrastructure
- **data-team-infrastructure** - Data team tenant infrastructure  
- **gcp-org-compliance** - Organization-level infrastructure

## Deployment

### Prerequisites

1. **Slack App Configuration**
   - Go to [Slack API Apps](https://api.slack.com/apps)
   - Enable "Interactive Components"
   - Get your signing secret from "Basic Information" → "App Credentials"

2. **GitHub Personal Access Token**
   - Create token with `actions:write` scope
   - Used to trigger approval workflows

3. **GCP Project Access**
   - `Cloud Functions Developer` role
   - `Storage Admin` role (for approval storage)

### Deploy

```bash
# Set required environment variables
export SLACK_SIGNING_SECRET="your_slack_signing_secret"
export GITHUB_TOKEN="your_github_token"  
export GCP_PROJECT="your-gcp-project"

# Deploy the function
./deploy.sh
```

### Configure Slack App

After deployment, update your Slack app:

1. Go to **Features** → **Interactive Components**
2. Set **Request URL** to: `https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/slack-approval-handler`
3. Save changes

## Usage

### Workflow Integration

In your GitHub workflows, use these button values:

```yaml
# For webapp-team-infrastructure
"value": "approve:webapp-team-infrastructure:${{ github.run_id }}"
"value": "reject:webapp-team-infrastructure:${{ github.run_id }}"

# For data-team-infrastructure  
"value": "approve:data-team-infrastructure:${{ github.run_id }}"
"value": "reject:data-team-infrastructure:${{ github.run_id }}"

# For gcp-org-compliance
"value": "approve:gcp-org-compliance:${{ github.run_id }}"
"value": "reject:gcp-org-compliance:${{ github.run_id }}"
```

### Approval Flow

1. **Workflow triggers** infrastructure change
2. **Slack message sent** with approval buttons
3. **User clicks** Approve/Reject
4. **Function processes** click and stores decision in GCS
5. **Workflow polls** GCS bucket and proceeds/fails accordingly

## Security Features

- **Request signature verification** - Ensures requests come from Slack
- **Timestamp validation** - Prevents replay attacks
- **Project-based authorization** - Different approvers per project
- **Complete audit trail** - All decisions logged to Google Cloud Logging
- **Secure credential handling** - Environment variables for secrets

## Monitoring

### Health Check

```bash
curl https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/slack-approval-handler/health
```

### Logs

```bash
# View function logs
gcloud functions logs read slack-approval-handler --region us-central1

# View audit logs
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=slack-approval-handler"
```

### Approval Status

```bash
# Check approval for specific run
gsutil cat gs://u2i-terraform-approvals/approvals/RUN_ID
gsutil cat gs://u2i-terraform-approvals/approvals/RUN_ID.json
```

## Adding New Projects

To add a new project, update `PROJECT_CONFIGS` in `index.js`:

```javascript
'new-team-infrastructure': {
  owner: 'u2i',
  repo: 'new-team-infrastructure',
  workflow: 'terraform-apply.yml',
  approvers: ['platform-team', 'new-team-lead'],
  riskLevel: 'medium',
  slackChannel: '#new-team-approvals',
  description: 'New Team Infrastructure'
}
```

Then redeploy:

```bash
./deploy.sh
```

## Troubleshooting

### Common Issues

1. **"Invalid signature" errors**
   - Check `SLACK_SIGNING_SECRET` is correct
   - Verify request is coming from your Slack workspace

2. **"Unknown project" errors**
   - Ensure button value format: `action:project-name:run-id`
   - Check project exists in `PROJECT_CONFIGS`

3. **GitHub API errors**
   - Verify `GITHUB_TOKEN` has `actions:write` scope
   - Check repository names in config match actual repos

4. **Timeout issues**
   - Workflow waits up to 1 hour for approval
   - Check GCS bucket permissions for approval storage

### Debug Mode

Set environment variable `DEBUG=true` when deploying for verbose logging.

## Compliance Notes

This system provides:
- ✅ **Audit Trail** - All approvals logged with user identity
- ✅ **Separation of Duties** - Approvers vs. implementers
- ✅ **Authorization Control** - Project-specific approvers
- ✅ **Tamper Evidence** - Cryptographic signature verification
- ✅ **Time-bound Approvals** - Automatic timeouts prevent stale approvals

For ISO 27001/SOC 2 compliance, ensure:
- Regular review of approver lists
- Monitoring of approval patterns
- Backup approval processes for emergencies
- Documentation of approval workflows