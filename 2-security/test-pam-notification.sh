#!/bin/bash
# Test PAM notification manually

TOKEN=$(gcloud secrets versions access latest --secret=slack-pam-bot-token --project=u2i-security)

# Post test notification
curl -X POST https://slack.com/api/chat.postMessage \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json; charset=utf-8" \
  --data '{
    "channel": "C093JRNSHG8",
    "text": "🚨 PAM Grant Requested: deployment-approver-access",
    "blocks": [
      {
        "type": "header",
        "text": {
          "type": "plain_text",
          "text": "🚨 PAM Grant Requested",
          "emoji": true
        }
      },
      {
        "type": "section",
        "fields": [
          {
            "type": "mrkdwn",
            "text": "*Requester:*\ngcp-failsafe@u2i.com"
          },
          {
            "type": "mrkdwn",
            "text": "*Time:*\n'"$(date)"'"
          }
        ]
      },
      {
        "type": "section",
        "fields": [
          {
            "type": "mrkdwn",
            "text": "*Entitlement:*\ndeployment-approver-access"
          },
          {
            "type": "mrkdwn",
            "text": "*Duration:*\n2 hours"
          }
        ]
      },
      {
        "type": "section",
        "text": {
          "type": "mrkdwn",
          "text": "*Justification:*\nTesting Slack notification integration - deployment approver access"
        }
      },
      {
        "type": "context",
        "elements": [
          {
            "type": "mrkdwn",
            "text": "✅ *Deployment Approver Access* (2 hour TTL)"
          }
        ]
      },
      {
        "type": "actions",
        "elements": [
          {
            "type": "button",
            "text": {
              "type": "plain_text",
              "text": "View in Console"
            },
            "url": "https://console.cloud.google.com/iam-admin/pam?project=u2i-security",
            "style": "primary"
          },
          {
            "type": "button",
            "text": {
              "type": "plain_text",
              "text": "PAM Runbook"
            },
            "url": "https://github.com/u2i/gcp-org-compliance/blob/main/runbooks/pam-break-glass.md"
          }
        ]
      },
      {
        "type": "context",
        "elements": [
          {
            "type": "mrkdwn",
            "text": "GCP PAM Audit | Policy v0.7 | Requires approval"
          }
        ]
      }
    ]
  }'