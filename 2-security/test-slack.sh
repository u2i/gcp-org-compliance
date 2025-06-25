#!/bin/bash
# Test Slack integration

TOKEN=$(gcloud secrets versions access latest --secret=slack-pam-bot-token --project=u2i-security)

# Test message
curl -X POST https://slack.com/api/chat.postMessage \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json; charset=utf-8" \
  --data '{
    "channel": "C093JRNSHG8",
    "text": "✅ PAM Slack integration test successful!",
    "blocks": [
      {
        "type": "section",
        "text": {
          "type": "mrkdwn",
          "text": "✅ *PAM Slack Integration Test*\n\nThe PAM audit bot is successfully connected to the #audit-log channel."
        }
      }
    ]
  }'