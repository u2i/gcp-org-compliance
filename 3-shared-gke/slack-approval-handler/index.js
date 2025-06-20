const crypto = require('crypto');
const { SecretManagerServiceClient } = require('@google-cloud/secret-manager');
const { Storage } = require('@google-cloud/storage');
const { Octokit } = require('@octokit/rest');

const secretManager = new SecretManagerServiceClient();

// Configuration for different projects
const PROJECT_CONFIGS = {
  'webapp-team-infrastructure': {
    owner: 'u2i',
    repo: 'webapp-team-infrastructure',
    workflow: 'terraform-apply.yml',
    approvers: ['platform-team', 'webapp-lead'],
    riskLevel: 'medium',
    slackChannel: '#webapp-approvals',
    description: 'WebApp Team Infrastructure'
  },
  'data-team-infrastructure': {
    owner: 'u2i', 
    repo: 'data-team-infrastructure',
    workflow: 'terraform-apply.yml',
    approvers: ['platform-team', 'data-lead'],
    riskLevel: 'high',
    slackChannel: '#data-approvals',
    description: 'Data Team Infrastructure'
  },
  'gcp-org-compliance': {
    owner: 'u2i',
    repo: 'gcp-org-compliance', 
    workflow: 'terraform-apply.yml',
    approvers: ['platform-team', 'security-team'],
    riskLevel: 'critical',
    slackChannel: '#infrastructure-approvals',
    description: 'Organization Infrastructure'
  }
};

/**
 * Get secret from Secret Manager
 */
async function getSecret(secretName) {
  const project = process.env.GCP_PROJECT;
  const name = `projects/${project}/secrets/${secretName}/versions/latest`;
  
  try {
    const [version] = await secretManager.accessSecretVersion({ name });
    return version.payload.data.toString();
  } catch (error) {
    console.error(`Failed to access secret ${secretName}:`, error);
    throw error;
  }
}

/**
 * Verify Slack request signature for security
 */
function verifySlackSignature(body, timestamp, signature, signingSecret) {
  const sigBasestring = 'v0:' + timestamp + ':' + body;
  const mySignature = 'v0=' + crypto
    .createHmac('sha256', signingSecret)
    .update(sigBasestring, 'utf8')
    .digest('hex');
  
  return signature === mySignature;
}

/**
 * Check if user is authorized to approve for this project
 */
function isAuthorizedApprover(user, projectConfig) {
  // In production, this would check against your user management system
  // For now, we'll allow any user but log the approval
  return true;
}

/**
 * Create audit log entry
 */
async function createAuditLog(action, projectName, runId, user, timestamp) {
  const logEntry = {
    timestamp: new Date(timestamp * 1000).toISOString(),
    action: action,
    project: projectName,
    workflow_run_id: runId,
    approver: user.name,
    approver_id: user.id,
    approver_email: user.profile?.email || 'unknown'
  };
  
  console.log('AUDIT LOG:', JSON.stringify(logEntry));
  
  // In production, you'd send this to your logging system:
  // - Google Cloud Logging
  // - Splunk
  // - DataDog
  // - Your compliance database
}

/**
 * Update workflow approval status - both GCS and GitHub
 */
async function updateWorkflowStatus(projectConfig, runId, approved, approver) {
  const storage = new Storage();
  const bucketName = process.env.APPROVAL_BUCKET;
  
  try {
    // 1. Write approval decision to GCS bucket (for audit trail)
    const approvalFile = storage.bucket(bucketName).file(`approvals/${runId}`);
    const metadataFile = storage.bucket(bucketName).file(`approvals/${runId}.json`);
    
    // Write simple approval status
    await approvalFile.save(approved.toString());
    
    // Write detailed metadata
    const metadata = {
      runId: runId,
      approved: approved,
      approver: approver.name,
      approver_id: approver.id,
      timestamp: new Date().toISOString(),
      project: projectConfig.repo,
      description: projectConfig.description
    };
    
    await metadataFile.save(JSON.stringify(metadata, null, 2));
    
    console.log(`Successfully wrote ${approved ? 'approval' : 'rejection'} for run ${runId} to GCS`);
    
    // 2. Try to send repository dispatch event to GitHub (optional)
    try {
      const githubToken = await getSecret('github-approval-token');
      const octokit = new Octokit({ auth: githubToken });
      
      await octokit.rest.repos.createDispatchEvent({
        owner: projectConfig.owner,
        repo: projectConfig.repo,
        event_type: 'slack-approval-received',
        client_payload: {
          run_id: runId,
          approved: approved,
          approver: approver.name,
          approver_id: approver.id,
          timestamp: new Date().toISOString()
        }
      });
      
      console.log(`Successfully sent repository dispatch event for ${projectConfig.repo}`);
    } catch (githubError) {
      console.error('Failed to send GitHub dispatch (non-fatal):', githubError.message);
      // Continue - approval is already written to GCS
    }
    
    return true;
  } catch (error) {
    console.error('Failed to update workflow status:', error);
    return false;
  }
}

/**
 * Main Cloud Function entry point
 */
exports.handleSlackInteraction = async (req, res) => {
  console.log('Received Slack interaction request');
  
  try {
    // Verify this is actually from Slack
    const timestamp = req.headers['x-slack-request-timestamp'];
    const signature = req.headers['x-slack-signature'];
    
    // Get the raw body string - this is crucial for signature verification
    let rawBody;
    if (typeof req.body === 'string') {
      rawBody = req.body;
    } else if (req.rawBody) {
      rawBody = req.rawBody.toString('utf8');
    } else {
      // If body is already parsed, we need to reconstruct it
      rawBody = Object.keys(req.body).map(key => `${key}=${encodeURIComponent(req.body[key])}`).join('&');
    }
    
    // Check for replay attacks (timestamp more than 5 minutes old)
    const currentTime = Math.floor(Date.now() / 1000);
    if (Math.abs(currentTime - timestamp) > 300) {
      console.error('Request timestamp too old');
      return res.status(400).send('Request timestamp too old');
    }
    
    // Get Slack signing secret and verify signature
    const slackSigningSecret = await getSecret('slack-signing-secret');
    if (!verifySlackSignature(rawBody, timestamp, signature, slackSigningSecret)) {
      console.error('Invalid Slack signature');
      return res.status(401).send('Unauthorized - Invalid signature');
    }
    
    // Parse Slack payload
    const payload = JSON.parse(decodeURIComponent(rawBody.split('payload=')[1]));
    console.log('Parsed payload:', JSON.stringify(payload, null, 2));
    
    const action = payload.actions[0];
    const user = payload.user;
    
    // Parse action value: "approve:webapp-team-infrastructure:15723208863"
    const [actionType, projectName, runId] = action.value.split(':');
    
    // Get project configuration
    const projectConfig = PROJECT_CONFIGS[projectName];
    if (!projectConfig) {
      console.error(`Unknown project: ${projectName}`);
      return res.status(400).json({
        text: `❌ Unknown project: ${projectName}`,
        replace_original: true
      });
    }
    
    // Check authorization
    if (!isAuthorizedApprover(user, projectConfig)) {
      console.error(`User ${user.name} not authorized for ${projectName}`);
      return res.status(403).json({
        text: `❌ You are not authorized to approve changes for ${projectConfig.description}`,
        replace_original: true
      });
    }
    
    // Create audit log
    await createAuditLog(actionType, projectName, runId, user, timestamp);
    
    const approved = actionType === 'approve';
    
    // Update GitHub workflow
    const success = await updateWorkflowStatus(projectConfig, runId, approved, user);
    
    if (!success) {
      return res.status(500).json({
        text: `❌ Failed to process ${approved ? 'approval' : 'rejection'}. Please try again or contact the platform team.`,
        replace_original: true
      });
    }
    
    // Return updated Slack message
    const responseMessage = approved 
      ? `✅ ${projectConfig.description} changes **APPROVED** by ${user.name}\n\nWorkflow Run: ${runId}\nTimestamp: ${new Date().toISOString()}`
      : `❌ ${projectConfig.description} changes **REJECTED** by ${user.name}\n\nWorkflow Run: ${runId}\nTimestamp: ${new Date().toISOString()}`;
    
    res.status(200).json({
      text: responseMessage,
      replace_original: true,
      blocks: [
        {
          type: "section", 
          text: {
            type: "mrkdwn",
            text: responseMessage
          }
        },
        {
          type: "context",
          elements: [
            {
              type: "mrkdwn",
              text: `Project: ${projectConfig.description} | Risk Level: ${projectConfig.riskLevel.toUpperCase()}`
            }
          ]
        }
      ]
    });
    
  } catch (error) {
    console.error('Error processing Slack interaction:', error);
    res.status(500).json({
      text: '❌ Internal error processing approval. Please contact the platform team.',
      replace_original: true
    });
  }
};

/**
 * Health check endpoint
 */
exports.healthCheck = (req, res) => {
  res.status(200).json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    projects: Object.keys(PROJECT_CONFIGS)
  });
};