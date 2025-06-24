# Slack App Setup Guide for GCP PAM Integration

This guide walks you through creating a proper Slack App for PAM notifications, which is more secure and feature-rich than simple webhooks.

## Why Use a Slack App?

- **Better Security**: OAuth tokens instead of webhook URLs
- **Richer Formatting**: Blocks, buttons, and interactive messages
- **Event Subscriptions**: Can listen to reactions/threads for approval workflows
- **Audit Trail**: App activity is logged in Slack's audit logs
- **Scalability**: Can post to multiple channels, DM users

## Step 1: Create the Slack App

1. Go to https://api.slack.com/apps
2. Click **Create New App**
3. Choose **From an app manifest** (faster setup)
4. Select your workspace
5. Paste this manifest:

```yaml
display_information:
  name: GCP PAM Audit Bot
  description: Posts PAM grant requests and decisions to audit channels
  background_color: "#1a73e8"
  long_description: This bot integrates with Google Cloud Privileged Access Manager (PAM) to post real-time notifications about access requests, approvals, denials, and revocations. It's part of the GCP Break-Glass Policy v0.7 compliance requirements.
features:
  bot_user:
    display_name: PAM Audit Bot
    always_online: true
  app_home:
    home_tab_enabled: false
    messages_tab_enabled: true
    messages_tab_read_only_enabled: false
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
  event_subscriptions:
    request_url: https://europe-west1-u2i-security.cloudfunctions.net/pam-slack-handler
    bot_events:
      - app_mention
      - message.channels
      - reaction_added
  interactivity:
    is_enabled: true
    request_url: https://europe-west1-u2i-security.cloudfunctions.net/pam-slack-handler
  org_deploy_enabled: false
  socket_mode_enabled: false
  token_rotation_enabled: false
```

6. Click **Next**
7. Review and click **Create**

## Step 2: Configure OAuth & Permissions

1. In your app settings, go to **OAuth & Permissions**
2. Under **Bot Token Scopes**, verify these scopes are added:
   - `channels:join` - Join public channels
   - `channels:read` - View basic channel info
   - `chat:write` - Post messages
   - `chat:write.public` - Post to channels bot isn't member of
   - `files:write` - Upload reports/logs
   - `groups:read` - Access private channels
   - `groups:write` - Join private channels
   - `im:write` - DM users for critical alerts
   - `users:read` - Look up user info
   - `users:read.email` - Match GCP emails to Slack users

3. Click **Install to Workspace**
4. Review permissions and click **Allow**
5. Copy the **Bot User OAuth Token** (starts with `xoxb-`)

## Step 3: Store Token Securely

### Option A: Google Secret Manager (Recommended)

```bash
# Create the secret
echo -n "xoxb-your-token-here" | gcloud secrets create slack-pam-bot-token \
  --project=u2i-security \
  --replication-policy="automatic" \
  --data-file=-

# Grant Cloud Function access
gcloud secrets add-iam-policy-binding slack-pam-bot-token \
  --project=u2i-security \
  --member="serviceAccount:u2i-security@appspot.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

### Option B: Environment Variable (Less Secure)

```bash
export TF_VAR_slack_bot_token="xoxb-your-token-here"
```

## Step 4: Update Cloud Function

We need to update the Cloud Function to use the Slack SDK instead of webhooks:

```javascript
// Updated index.js for Slack App
const { WebClient } = require('@slack/web-api');
const { SecretManagerServiceClient } = require('@google-cloud/secret-manager');

let slackClient;

async function initializeSlack() {
  if (!slackClient) {
    const token = await getSlackToken();
    slackClient = new WebClient(token);
  }
  return slackClient;
}

async function getSlackToken() {
  if (process.env.SLACK_BOT_TOKEN) {
    return process.env.SLACK_BOT_TOKEN;
  }
  
  // Fetch from Secret Manager
  const client = new SecretManagerServiceClient();
  const [version] = await client.accessSecretVersion({
    name: 'projects/u2i-security/secrets/slack-pam-bot-token/versions/latest',
  });
  
  return version.payload.data.toString();
}

exports.handlePamEvent = async (message, context) => {
  const slack = await initializeSlack();
  const event = JSON.parse(Buffer.from(message.data, 'base64').toString());
  
  try {
    // Post to audit channel
    await slack.chat.postMessage({
      channel: '#audit-log',
      blocks: formatPamEventBlocks(event),
      text: formatPamEventText(event), // Fallback
    });
    
    // For critical events, also DM tech management
    if (isCriticalEvent(event)) {
      await notifyTechManagement(slack, event);
    }
    
  } catch (error) {
    console.error('Error posting to Slack:', error);
    throw error;
  }
};

function formatPamEventBlocks(event) {
  // Rich Block Kit formatting
  const eventType = detectEventType(event);
  
  return [
    {
      type: "header",
      text: {
        type: "plain_text",
        text: getEventTitle(eventType),
        emoji: true
      }
    },
    {
      type: "section",
      fields: getEventFields(event, eventType)
    },
    {
      type: "section",
      text: {
        type: "mrkdwn",
        text: `*Justification:* ${event.justification || 'None provided'}`
      }
    },
    {
      type: "context",
      elements: [
        {
          type: "mrkdwn",
          text: `Lane: ${getLaneInfo(event)} | Policy: v0.7`
        }
      ]
    },
    // Add approve/deny buttons for pending requests
    ...(eventType === 'request' ? [getActionButtons(event)] : [])
  ];
}

function getActionButtons(event) {
  return {
    type: "actions",
    elements: [
      {
        type: "button",
        text: {
          type: "plain_text",
          text: "View in Console"
        },
        url: `https://console.cloud.google.com/iam-admin/pam/grants?project=u2i-security&grant=${event.grantId}`,
        style: "primary"
      },
      {
        type: "button",
        text: {
          type: "plain_text",
          text: "View Runbook"
        },
        url: "https://github.com/u2i/gcp-org-compliance/blob/main/runbooks/pam-break-glass.md"
      }
    ]
  };
}
```

## Step 5: Update Terraform

```hcl
# In 2-security/variables.tf
variable "slack_bot_token" {
  description = "Slack bot token for PAM notifications"
  type        = string
  sensitive   = true
  default     = ""
}

# In 2-security/pam.tf - update the Cloud Function
resource "google_cloudfunctions_function" "pam_slack_notifier" {
  # ... existing config ...
  
  environment_variables = {
    SLACK_CHANNEL = "#audit-log"
    # Remove SLACK_WEBHOOK_URL
  }
  
  # Use Secret Manager
  secret_environment_variables {
    key        = "SLACK_BOT_TOKEN"
    project_id = google_project.security.project_id
    secret     = google_secret_manager_secret.slack_bot_token.secret_id
    version    = "latest"
  }
}

resource "google_secret_manager_secret" "slack_bot_token" {
  project   = google_project.security.project_id
  secret_id = "slack-pam-bot-token"
  
  replication {
    automatic = true
  }
}
```

## Step 6: Enhanced Features

### A. Interactive Approvals (Future Enhancement)

```javascript
// Handle button clicks
exports.handleSlackInteraction = async (req, res) => {
  const payload = JSON.parse(req.body.payload);
  
  if (payload.type === 'block_actions') {
    const action = payload.actions[0];
    
    if (action.action_id === 'approve_grant') {
      // Trigger PAM approval via API
      await approveGrant(payload.user.email, action.value);
      
      // Update message
      await slack.chat.update({
        channel: payload.channel.id,
        ts: payload.message.ts,
        text: 'Grant approved!',
        blocks: updateBlocksWithApproval(payload.message.blocks, payload.user)
      });
    }
  }
  
  res.status(200).send();
};
```

### B. User Lookup Integration

```javascript
async function notifyTechManagement(slack, event) {
  // Look up tech management users
  const users = await slack.users.list();
  const techMgmt = users.members.filter(user => 
    user.profile.email?.endsWith('@u2i.com') &&
    user.groups?.includes('gcp-techmgmt')
  );
  
  // DM each tech mgmt member
  for (const user of techMgmt) {
    await slack.chat.postMessage({
      channel: user.id,
      text: `🚨 Critical PAM Event: ${getEventTitle(event)}`,
      blocks: formatPamEventBlocks(event)
    });
  }
}
```

### C. Incident Integration

```javascript
// Auto-create incident channel for break-glass usage
if (event.entitlement === 'break-glass-emergency') {
  const channel = await slack.conversations.create({
    name: `incident-${Date.now()}`,
    is_private: true
  });
  
  await slack.chat.postMessage({
    channel: channel.id,
    text: 'Break-glass access activated! This channel will track all actions.'
  });
}
```

## Step 7: Configure App Home

1. Go to **App Home** in your app settings
2. Add a Home Tab with instructions:

```
Welcome to PAM Audit Bot! 👋

I post Google Cloud PAM events to #audit-log to maintain compliance with GCP Break-Glass Policy v0.7.

*What I do:*
• Post grant requests with full context
• Notify on approvals/denials
• Track break-glass usage
• Maintain 400-day audit trail

*Channels I monitor:*
• #audit-log - All PAM events
• #incidents - Critical alerts

*Commands:*
• `/pam-status` - Check my health
• `/pam-report weekly` - Generate access report

*Need help?*
• Runbook: /pam-break-glass.md
• Policy: /gcp-break-glass-policy.md
• Support: #gcp-support
```

## Step 8: Test the Integration

1. **Test Direct Message**:
   ```bash
   curl -X POST https://slack.com/api/chat.postMessage \
     -H "Authorization: Bearer xoxb-your-token" \
     -H "Content-type: application/json" \
     -d '{
       "channel": "#audit-log",
       "text": "PAM Bot test message",
       "blocks": [{
         "type": "section",
         "text": {
           "type": "mrkdwn",
           "text": "✅ PAM Bot successfully connected!"
         }
       }]
     }'
   ```

2. **Test PAM Integration**:
   ```bash
   # Create a test grant
   gcloud pam grants create \
     --entitlement="jit-deploy" \
     --justification="Testing Slack app integration" \
     --requested-duration="1800s" \
     --location="global" \
     --organization="981978971260"
   ```

## Step 9: Monitoring & Maintenance

### Health Checks

Add a slash command `/pam-status`:
```javascript
exports.handleSlashCommand = async (req, res) => {
  if (req.body.command === '/pam-status') {
    const status = await checkSystemHealth();
    
    res.json({
      response_type: 'ephemeral',
      blocks: [{
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: `*PAM Bot Status*\n${formatStatus(status)}`
        }
      }]
    });
  }
};
```

### Rate Limiting

Implement rate limiting to prevent spam:
```javascript
const rateLimiter = new Map();

function checkRateLimit(userId) {
  const now = Date.now();
  const userLimits = rateLimiter.get(userId) || [];
  const recentRequests = userLimits.filter(t => now - t < 60000); // 1 minute
  
  if (recentRequests.length >= 10) {
    throw new Error('Rate limit exceeded');
  }
  
  rateLimiter.set(userId, [...recentRequests, now]);
}
```

## Security Best Practices

1. **Token Rotation**
   - Rotate bot token quarterly
   - Use Secret Manager versioning
   - Update via Terraform

2. **Least Privilege**
   - Only grant necessary scopes
   - Restrict to specific channels
   - Regular permission audits

3. **Audit Logging**
   - All bot actions logged
   - Export to BigQuery
   - 400-day retention

4. **Error Handling**
   - Never expose tokens in logs
   - Sanitize error messages
   - Alert on failures

## Troubleshooting

### Bot Not Responding
```bash
# Check Cloud Function logs
gcloud functions logs read pam-slack-notifier --limit=50

# Verify bot is in channel
curl -X POST https://slack.com/api/conversations.list \
  -H "Authorization: Bearer xoxb-token" | jq '.channels[] | select(.name=="audit-log")'
```

### Permission Errors
- Ensure bot is invited to private channels
- Check OAuth scopes match requirements
- Verify Secret Manager permissions

### Message Formatting Issues
- Test with Slack Block Kit Builder
- Validate JSON structure
- Check for special characters

## Compliance Notes

This implementation satisfies GCP Break-Glass Policy v0.7:
- ✅ Real-time PAM event notifications
- ✅ Posts to #audit-log channel
- ✅ Maintains audit trail
- ✅ Integrates with monitoring
- ✅ Supports incident response

## Next Steps

1. Create Slack app using manifest
2. Install to workspace
3. Store bot token in Secret Manager
4. Update Cloud Function code
5. Deploy and test
6. Configure team notifications
7. Document in runbooks