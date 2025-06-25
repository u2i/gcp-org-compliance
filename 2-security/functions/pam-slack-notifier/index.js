/**
 * PAM Slack Notifier Function
 * Posts PAM grant requests and decisions to #audit-log channel
 * Part of GCP Break-Glass Policy v0.7 implementation
 */

const { WebClient } = require('@slack/web-api');
const { SecretManagerServiceClient } = require('@google-cloud/secret-manager');

let slackClient;

/**
 * Initialize Slack client with token from Secret Manager
 */
async function initializeSlack() {
  if (!slackClient) {
    const token = await getSlackToken();
    slackClient = new WebClient(token);
  }
  return slackClient;
}

/**
 * Get Slack bot token from environment or Secret Manager
 */
async function getSlackToken() {
  // First try environment variable
  if (process.env.SLACK_BOT_TOKEN) {
    return process.env.SLACK_BOT_TOKEN;
  }
  
  // Otherwise fetch from Secret Manager
  const client = new SecretManagerServiceClient();
  const projectId = process.env.GCP_PROJECT || 'u2i-security';
  const [version] = await client.accessSecretVersion({
    name: `projects/${projectId}/secrets/slack-pam-bot-token/versions/latest`,
  });
  
  return version.payload.data.toString();
}

/**
 * Main function - handles PAM events from Pub/Sub
 */
exports.handlePamEvent = async (message, context) => {
  const slack = await initializeSlack();
  const channel = process.env.SLACK_CHANNEL || '#audit-log';
  
  try {
    // Decode the PubSub message
    const messageData = message.data
      ? Buffer.from(message.data, 'base64').toString()
      : '{}';
    
    const event = JSON.parse(messageData);
    console.log('Processing PAM event:', JSON.stringify(event));

    // Format and post to Slack
    const slackMessage = formatSlackMessage(event);
    
    const result = await slack.chat.postMessage({
      channel: channel,
      ...slackMessage
    });

    console.log('Successfully posted to Slack:', result.ts);
  } catch (error) {
    console.error('Error processing PAM event:', error);
    // Log error details for debugging
    if (error.data) {
      console.error('Slack API error:', error.data);
    }
    throw error;
  }
};

/**
 * Format PAM event for Slack using Block Kit
 */
function formatSlackMessage(event) {
  const eventType = detectEventType(event);
  const { emoji, color, title } = getEventDisplay(eventType);
  
  // Extract key information
  const principal = event.protoPayload?.authenticationInfo?.principalEmail || 'Unknown';
  const timestamp = new Date(event.timestamp).toLocaleString();
  const entitlement = extractEntitlementName(event);
  const justification = extractJustification(event);
  
  // Build blocks for rich formatting
  const blocks = [
    {
      type: "header",
      text: {
        type: "plain_text",
        text: `${emoji} ${title}`,
        emoji: true
      }
    },
    {
      type: "section",
      fields: [
        {
          type: "mrkdwn",
          text: `*Requester:*\n${principal}`
        },
        {
          type: "mrkdwn",
          text: `*Time:*\n${timestamp}`
        }
      ]
    }
  ];

  // Add event-specific fields
  if (eventType === 'request') {
    const duration = extractDuration(event);
    const laneInfo = getLaneInfo(entitlement);
    
    blocks.push({
      type: "section",
      fields: [
        {
          type: "mrkdwn",
          text: `*Entitlement:*\n${entitlement}`
        },
        {
          type: "mrkdwn",
          text: `*Duration:*\n${duration}`
        }
      ]
    });
    
    if (justification) {
      blocks.push({
        type: "section",
        text: {
          type: "mrkdwn",
          text: `*Justification:*\n${justification}`
        }
      });
    }
    
    if (laneInfo) {
      blocks.push({
        type: "context",
        elements: [
          {
            type: "mrkdwn",
            text: laneInfo
          }
        ]
      });
    }
  } else if (eventType === 'approve' || eventType === 'deny') {
    const actor = event.protoPayload?.authenticationInfo?.principalEmail || 'Unknown';
    const reason = extractReason(event);
    const originalRequester = extractOriginalRequester(event);
    
    blocks.push({
      type: "section",
      fields: [
        {
          type: "mrkdwn",
          text: `*${eventType === 'approve' ? 'Approver' : 'Denied by'}:*\n${actor}`
        },
        {
          type: "mrkdwn",
          text: `*Original requester:*\n${originalRequester}`
        }
      ]
    });
    
    if (reason) {
      blocks.push({
        type: "section",
        text: {
          type: "mrkdwn",
          text: `*Reason:*\n${reason}`
        }
      });
    }
  }

  // Add action buttons for requests
  if (eventType === 'request' && entitlement) {
    blocks.push({
      type: "actions",
      elements: [
        {
          type: "button",
          text: {
            type: "plain_text",
            text: "View in Console"
          },
          url: `https://console.cloud.google.com/iam-admin/pam?project=u2i-security`,
          style: "primary"
        },
        {
          type: "button",
          text: {
            type: "plain_text",
            text: "PAM Runbook"
          },
          url: "https://github.com/u2i/gcp-org-compliance/blob/main/runbooks/pam-break-glass.md"
        }
      ]
    });
  }

  // Add footer
  blocks.push({
    type: "context",
    elements: [
      {
        type: "mrkdwn",
        text: `GCP PAM Audit | Policy v0.7 | ${eventType === 'request' ? 'Requires approval' : 'Logged'}`
      }
    ]
  });

  return {
    text: `${emoji} ${title}: ${principal} - ${entitlement || eventType}`, // Fallback text
    blocks: blocks,
    attachments: [{
      color: color
    }]
  };
}

/**
 * Detect the type of PAM event
 */
function detectEventType(event) {
  const methodName = event.protoPayload?.methodName || '';
  
  if (methodName.includes('CreateGrant')) return 'request';
  if (methodName.includes('ApproveGrant')) return 'approve';
  if (methodName.includes('DenyGrant')) return 'deny';
  if (methodName.includes('RevokeGrant')) return 'revoke';
  
  return 'other';
}

/**
 * Get display properties for event type
 */
function getEventDisplay(eventType) {
  const displays = {
    request: { emoji: '🚨', color: '#ff9800', title: 'PAM Grant Requested' },
    approve: { emoji: '✅', color: '#4caf50', title: 'PAM Grant Approved' },
    deny: { emoji: '❌', color: '#f44336', title: 'PAM Grant Denied' },
    revoke: { emoji: '🔒', color: '#9e9e9e', title: 'PAM Grant Revoked' },
    other: { emoji: 'ℹ️', color: '#2196f3', title: 'PAM Event' }
  };
  
  return displays[eventType] || displays.other;
}

/**
 * Extract entitlement name from event
 */
function extractEntitlementName(event) {
  const parent = event.protoPayload?.request?.parent || '';
  const match = parent.match(/entitlements\/([^\/]+)/);
  return match ? match[1] : null;
}

/**
 * Extract justification from event
 */
function extractJustification(event) {
  return event.protoPayload?.request?.justification?.unstructuredJustification || 
         event.protoPayload?.request?.grant?.justification?.unstructuredJustification ||
         null;
}

/**
 * Extract reason from approval/denial
 */
function extractReason(event) {
  return event.protoPayload?.request?.reason || 
         event.protoPayload?.request?.grant?.reason ||
         'No reason provided';
}

/**
 * Extract original requester from approval/denial events
 */
function extractOriginalRequester(event) {
  // Try various paths where the original requester might be stored
  return event.protoPayload?.request?.grant?.requester ||
         event.protoPayload?.response?.requester ||
         event.labels?.requester ||
         'Unknown';
}

/**
 * Extract and format duration
 */
function extractDuration(event) {
  const duration = event.protoPayload?.request?.requestedDuration || 
                  event.protoPayload?.request?.grant?.requestedDuration ||
                  null;
  
  if (!duration) return 'Unknown';
  
  // Convert from seconds format (e.g., "1800s") to human readable
  const match = duration.match(/(\d+)s/);
  if (!match) return duration;
  
  const seconds = parseInt(match[1]);
  if (seconds < 60) return `${seconds} seconds`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)} minutes`;
  return `${Math.floor(seconds / 3600)} hours`;
}

/**
 * Get lane information based on entitlement
 */
function getLaneInfo(entitlement) {
  const laneMap = {
    'jit-deploy': '🚀 *Lane 1:* App Code + Manifests (30 min TTL, requires Prod Support+ approval)',
    'jit-tf-admin': '🏗️ *Lane 2:* Environment Infrastructure (60 min TTL, requires Tech Lead + Tech Mgmt)',
    'break-glass-emergency': '🚨 *Lane 3:* Org-Level Infrastructure (30 min TTL, requires 2 Tech Mgmt)',
    'jit-project-bootstrap': '🎯 *Lane 4:* Project Bootstrap (30 min TTL, requires 2 Tech Mgmt)',
    'deployment-approver-access': '✅ *Deployment Approver Access* (2 hour TTL)',
    'billing-access': '💰 *Billing Access* (4 hour TTL)'
  };
  
  return laneMap[entitlement] || null;
}