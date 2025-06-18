#!/bin/bash

# U2I Slack Approval Handler Deployment Script

set -e

echo "🚀 Deploying U2I Slack Approval Handler..."

# Check if required environment variables are set
if [ -z "$SLACK_SIGNING_SECRET" ]; then
    echo "❌ Error: SLACK_SIGNING_SECRET environment variable not set"
    echo "Get this from: https://api.slack.com/apps/YOUR_APP_ID/general"
    exit 1
fi

if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Error: GITHUB_TOKEN environment variable not set"
    echo "Create a personal access token with 'actions:write' scope"
    exit 1
fi

if [ -z "$GCP_PROJECT" ]; then
    echo "❌ Error: GCP_PROJECT environment variable not set"
    exit 1
fi

echo "📦 Installing dependencies..."
npm install

echo "☁️ Deploying to Google Cloud Functions..."
gcloud functions deploy slack-approval-handler \
  --runtime nodejs18 \
  --trigger-http \
  --allow-unauthenticated \
  --source . \
  --entry-point handleSlackInteraction \
  --memory 256MB \
  --timeout 60s \
  --project $GCP_PROJECT \
  --region us-central1 \
  --set-env-vars "SLACK_SIGNING_SECRET=$SLACK_SIGNING_SECRET,GITHUB_TOKEN=$GITHUB_TOKEN"

echo "🎯 Getting function URL..."
FUNCTION_URL=$(gcloud functions describe slack-approval-handler --region us-central1 --project $GCP_PROJECT --format="value(httpsTrigger.url)")

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📋 Next steps:"
echo "1. Configure Slack app Interactive Components:"
echo "   URL: $FUNCTION_URL"
echo ""
echo "2. Test the health endpoint:"
echo "   curl $FUNCTION_URL/health"
echo ""
echo "3. Update your GitHub workflows to use the new action values:"
echo "   approve:webapp-team-infrastructure:\${{ github.run_id }}"
echo ""