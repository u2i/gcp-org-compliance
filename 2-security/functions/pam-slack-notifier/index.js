/**
 * PAM Slack Notifier Function
 * Posts PAM grant requests and decisions to #audit-log channel
 * Part of GCP Break-Glass Policy v0.4 implementation
 */

const { PubSub } = require('@google-cloud/pubsub');
const https = require('https');

/**
 * Process PAM event and post to Slack
 * @param {Object} message - PubSub message
 * @param {Object} context - Event context
 */
exports.handlePamEvent = async (message, context) => {
  const slackWebhookUrl = process.env.SLACK_WEBHOOK_URL;
  const slackChannel = process.env.SLACK_CHANNEL || '#audit-log';
  
  if (!slackWebhookUrl) {
    console.error('SLACK_WEBHOOK_URL environment variable not set');
    return;
  }

  try {
    // Decode the PubSub message
    const messageData = message.data
      ? Buffer.from(message.data, 'base64').toString()
      : '{}';
    
    const event = JSON.parse(messageData);
    console.log('Processing PAM event:', event);

    // Format the Slack message based on event type
    const slackMessage = formatSlackMessage(event);
    
    // Post to Slack
    await postToSlack(slackWebhookUrl, {
      channel: slackChannel,
      username: 'PAM Audit Bot',
      icon_emoji: ':shield:',
      ...slackMessage
    });

    console.log('Successfully posted to Slack');
  } catch (error) {
    console.error('Error processing PAM event:', error);
    throw error;
  }
};

/**
 * Format PAM event for Slack
 * @param {Object} event - PAM event data
 * @returns {Object} Formatted Slack message
 */
function formatSlackMessage(event) {
  const eventType = event.protoPayload?.methodName || 'Unknown';
  const requester = event.protoPayload?.authenticationInfo?.principalEmail || 'Unknown';
  const timestamp = new Date(event.timestamp).toLocaleString();
  
  // Determine event type and color
  let color, title, fields;
  
  if (eventType.includes('CreateGrant')) {
    // Grant request
    const entitlement = extractEntitlementName(event);
    const justification = event.protoPayload?.request?.justification?.unstructuredJustification || 'No justification provided';
    const duration = event.protoPayload?.request?.requestedDuration || 'Unknown';
    
    color = '#ff9800'; // Orange for pending
    title = ':rotating_light: PAM Grant Requested';
    fields = [
      { title: 'Requester', value: requester, short: true },
      { title: 'Entitlement', value: entitlement, short: true },
      { title: 'Duration', value: formatDuration(duration), short: true },
      { title: 'Time', value: timestamp, short: true },
      { title: 'Justification', value: justification, short: false }
    ];
    
    // Add lane information based on entitlement
    const laneInfo = getLaneInfo(entitlement);
    if (laneInfo) {
      fields.push({ title: 'Lane', value: laneInfo, short: false });
    }
  } else if (eventType.includes('ApproveGrant')) {
    // Grant approved
    const approver = event.protoPayload?.authenticationInfo?.principalEmail || 'Unknown';
    const reason = event.protoPayload?.request?.reason || 'No reason provided';
    
    color = '#4caf50'; // Green for approved
    title = ':white_check_mark: PAM Grant Approved';
    fields = [
      { title: 'Approver', value: approver, short: true },
      { title: 'Original Requester', value: extractRequester(event), short: true },
      { title: 'Reason', value: reason, short: false },
      { title: 'Time', value: timestamp, short: true }
    ];
  } else if (eventType.includes('DenyGrant')) {
    // Grant denied
    const denier = event.protoPayload?.authenticationInfo?.principalEmail || 'Unknown';
    const reason = event.protoPayload?.request?.reason || 'No reason provided';
    
    color = '#f44336'; // Red for denied
    title = ':x: PAM Grant Denied';
    fields = [
      { title: 'Denied By', value: denier, short: true },
      { title: 'Original Requester', value: extractRequester(event), short: true },
      { title: 'Reason', value: reason, short: false },
      { title: 'Time', value: timestamp, short: true }
    ];
  } else if (eventType.includes('RevokeGrant')) {
    // Grant revoked (manual or automatic)
    color = '#9e9e9e'; // Grey for revoked
    title = ':lock: PAM Grant Revoked';
    fields = [
      { title: 'Grant Holder', value: extractRequester(event), short: true },
      { title: 'Revoked By', value: requester, short: true },
      { title: 'Time', value: timestamp, short: true }
    ];
  } else {
    // Other PAM events
    color = '#2196f3'; // Blue for info
    title = 'PAM Event';
    fields = [
      { title: 'Event Type', value: eventType, short: true },
      { title: 'Principal', value: requester, short: true },
      { title: 'Time', value: timestamp, short: true }
    ];
  }

  return {
    attachments: [{
      color: color,
      title: title,
      fields: fields,
      footer: 'GCP PAM Audit',
      ts: Math.floor(Date.now() / 1000)
    }]
  };
}

/**
 * Extract entitlement name from event
 * @param {Object} event - PAM event
 * @returns {string} Entitlement name
 */
function extractEntitlementName(event) {
  const parent = event.protoPayload?.request?.parent || '';
  const match = parent.match(/entitlements\/([^\/]+)/);
  return match ? match[1] : 'Unknown';
}

/**
 * Extract original requester from approve/deny events
 * @param {Object} event - PAM event
 * @returns {string} Original requester email
 */
function extractRequester(event) {
  // This would need to be extracted from the grant details
  // For now, return a placeholder
  return event.protoPayload?.request?.grant?.requester || 'Unknown';
}

/**
 * Get lane information based on entitlement
 * @param {string} entitlement - Entitlement name
 * @returns {string} Lane description
 */
function getLaneInfo(entitlement) {
  const laneMap = {
    'jit-deploy': 'Lane 1: App Code + Manifests (30 min TTL, dual approval required)',
    'jit-tf-admin': 'Lane 2: Environment Infrastructure (60 min TTL, Tech Lead + Tech Mgmt approval)',
    'break-glass-emergency': 'Lane 3: Org-Level Infrastructure (30 min TTL, 2 Tech Mgmt approvers)'
  };
  return laneMap[entitlement] || null;
}

/**
 * Format duration string
 * @param {string} duration - Duration in seconds format (e.g., "1800s")
 * @returns {string} Human-readable duration
 */
function formatDuration(duration) {
  if (!duration || typeof duration !== 'string') return 'Unknown';
  
  const match = duration.match(/(\d+)s/);
  if (!match) return duration;
  
  const seconds = parseInt(match[1]);
  if (seconds < 60) return `${seconds} seconds`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)} minutes`;
  return `${Math.floor(seconds / 3600)} hours`;
}

/**
 * Post message to Slack
 * @param {string} webhookUrl - Slack webhook URL
 * @param {Object} message - Message payload
 */
async function postToSlack(webhookUrl, message) {
  return new Promise((resolve, reject) => {
    const url = new URL(webhookUrl);
    const options = {
      hostname: url.hostname,
      path: url.pathname,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      }
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        if (res.statusCode === 200) {
          resolve(data);
        } else {
          reject(new Error(`Slack API error: ${res.statusCode} - ${data}`));
        }
      });
    });

    req.on('error', reject);
    req.write(JSON.stringify(message));
    req.end();
  });
}