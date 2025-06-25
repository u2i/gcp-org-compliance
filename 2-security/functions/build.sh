#!/bin/bash
# Build script for Cloud Functions
# Creates deployment packages for all functions

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Build PAM Slack Notifier
echo "Building PAM Slack Notifier..."
cd "$SCRIPT_DIR/pam-slack-notifier"

# Install dependencies
npm install --production

# Create deployment package
zip -r ../pam-slack-notifier.zip . -x "*.git*" -x "*node_modules/.bin/*" -x "*.DS_Store"

echo "Build complete: pam-slack-notifier.zip"