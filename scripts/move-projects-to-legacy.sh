#!/bin/bash

# Script to move projects from organization root to legacy folder
# Usage: ./scripts/move-projects-to-legacy.sh LEGACY_FOLDER_ID

if [ -z "$1" ]; then
  echo "Usage: $0 LEGACY_FOLDER_ID"
  echo "Example: $0 933345237861"
  exit 1
fi

LEGACY_FOLDER="$1"
ORG_ID="981978971260"
BOOTSTRAP_PROJECT="u2i-bootstrap"

echo "=== Moving Projects to Legacy Folder ==="
echo "Legacy Folder ID: $LEGACY_FOLDER"
echo "Organization ID: $ORG_ID"
echo ""

# Get all projects directly under the organization (excluding bootstrap)
PROJECTS=$(gcloud projects list --format="value(projectId)" --filter="parent.type=organization AND parent.id=$ORG_ID AND projectId!=$BOOTSTRAP_PROJECT")
COUNT=$(echo "$PROJECTS" | wc -l)

echo "Found $COUNT projects to move to legacy folder"
echo ""

# Move each project to legacy folder
MOVED=0
FAILED=0

for PROJECT in $PROJECTS; do
  echo "Moving $PROJECT..."
  if gcloud beta projects move $PROJECT --folder=$LEGACY_FOLDER --quiet 2>/dev/null; then
    echo "✅ Successfully moved $PROJECT"
    MOVED=$((MOVED + 1))
    
    # Add compliance status label
    gcloud projects update $PROJECT \
      --update-labels=compliance-status=legacy,migration-date=$(date +%Y%m%d) \
      2>/dev/null || echo "⚠️  Warning: Could not update labels for $PROJECT"
  else
    echo "❌ Failed to move $PROJECT (may already be in a folder)"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "=== Migration Summary ==="
echo "Successfully moved: $MOVED projects"
echo "Failed to move: $FAILED projects" 
echo "Total processed: $((MOVED + FAILED)) projects"
echo ""
echo "Next steps:"
echo "1. Run compliance assessment: ./scripts/assess-project-compliance.sh PROJECT_ID"
echo "2. Review projects for migration planning"
echo "3. Move ready projects to migration-in-progress folder"