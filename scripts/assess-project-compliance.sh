#!/bin/bash

# Compliance assessment script for existing projects
# Usage: ./scripts/assess-project-compliance.sh PROJECT_ID

if [ -z "$1" ]; then
  echo "Usage: $0 PROJECT_ID"
  echo "Example: $0 my-existing-project"
  exit 1
fi

PROJECT_ID="$1"

echo "=== Compliance Assessment for $PROJECT_ID ==="
echo ""

# Check if project exists and is accessible
if ! gcloud projects describe $PROJECT_ID &>/dev/null; then
  echo "❌ Project $PROJECT_ID not found or not accessible"
  exit 1
fi

COMPLIANCE_SCORE=0
TOTAL_CHECKS=10
ISSUES=()

# 1. Check for service account keys
echo "🔑 Checking service account keys..."
SA_KEYS=0
if gcloud iam service-accounts list --project=$PROJECT_ID --format="value(email)" 2>/dev/null | while read SA; do
  [ -n "$SA" ] && gcloud iam service-accounts keys list --iam-account=$SA --project=$PROJECT_ID --filter="keyType=USER_MANAGED" --format="value(name)" 2>/dev/null
done | grep -q "projects/"; then
  echo "❌ User-managed service account keys found"
  ISSUES+=("Has user-managed service account keys")
else
  echo "✅ No user-managed service account keys"
  COMPLIANCE_SCORE=$((COMPLIANCE_SCORE + 1))
fi

# 2. Check for external IPs
echo "🌐 Checking external IPs..."
EXT_IPS=$(gcloud compute instances list --project=$PROJECT_ID --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null | grep -v "^$" | wc -l)
if [ "$EXT_IPS" -gt 0 ]; then
  echo "❌ Found $EXT_IPS instances with external IPs"
  ISSUES+=("$EXT_IPS instances have external IPs")
else
  echo "✅ No instances with external IPs"
  COMPLIANCE_SCORE=$((COMPLIANCE_SCORE + 1))
fi

# 3. Check for default network
echo "🕸️  Checking default network..."
if gcloud compute networks describe default --project=$PROJECT_ID &>/dev/null; then
  echo "❌ Default network exists"
  ISSUES+=("Default network exists")
else
  echo "✅ Default network not found"
  COMPLIANCE_SCORE=$((COMPLIANCE_SCORE + 1))
fi

# 4. Check bucket encryption
echo "🔒 Checking bucket encryption..."
BUCKET_ISSUES=0
if gsutil ls -p $PROJECT_ID 2>/dev/null | while read bucket; do
  if ! gsutil defencryption get $bucket 2>/dev/null | grep -q "default_kms_key_name"; then
    echo "⚠️  $bucket lacks CMEK encryption"
    BUCKET_ISSUES=$((BUCKET_ISSUES + 1))
  fi
done; then
  if [ "$BUCKET_ISSUES" -gt 0 ]; then
    ISSUES+=("$BUCKET_ISSUES buckets lack CMEK encryption")
  else
    echo "✅ All buckets have CMEK encryption (or no buckets)"
    COMPLIANCE_SCORE=$((COMPLIANCE_SCORE + 1))
  fi
else
  echo "✅ No buckets found or all encrypted"
  COMPLIANCE_SCORE=$((COMPLIANCE_SCORE + 1))
fi

# 5. Check Cloud SQL SSL requirement
echo "🛡️  Checking Cloud SQL SSL..."
SQL_ISSUES=0
if gcloud sql instances list --project=$PROJECT_ID --format="value(name)" 2>/dev/null | while read INSTANCE; do
  [ -n "$INSTANCE" ] || continue
  SSL_REQUIRED=$(gcloud sql instances describe $INSTANCE --project=$PROJECT_ID --format="value(settings.ipConfiguration.requireSsl)" 2>/dev/null)
  if [ "$SSL_REQUIRED" != "True" ]; then
    echo "❌ $INSTANCE does not require SSL"
    SQL_ISSUES=$((SQL_ISSUES + 1))
  fi
done; then
  if [ "$SQL_ISSUES" -gt 0 ]; then
    ISSUES+=("$SQL_ISSUES SQL instances don't require SSL")
  else
    echo "✅ All SQL instances require SSL (or no instances)"
    COMPLIANCE_SCORE=$((COMPLIANCE_SCORE + 1))
  fi
else
  echo "✅ No SQL instances found"
  COMPLIANCE_SCORE=$((COMPLIANCE_SCORE + 1))
fi

# 6. Check Cloud SQL public IP
echo "🌍 Checking Cloud SQL public access..."
SQL_PUBLIC=0
if gcloud sql instances list --project=$PROJECT_ID --format="value(name)" 2>/dev/null | while read INSTANCE; do
  [ -n "$INSTANCE" ] || continue
  PUBLIC_IP=$(gcloud sql instances describe $INSTANCE --project=$PROJECT_ID --format="value(settings.ipConfiguration.ipv4Enabled)" 2>/dev/null)
  if [ "$PUBLIC_IP" = "True" ]; then
    echo "⚠️  $INSTANCE has public IP enabled"
    SQL_PUBLIC=$((SQL_PUBLIC + 1))
  fi
done; then
  if [ "$SQL_PUBLIC" -gt 0 ]; then
    ISSUES+=("$SQL_PUBLIC SQL instances have public IPs")
  else
    echo "✅ No SQL instances have public IPs"
    COMPLIANCE_SCORE=$((COMPLIANCE_SCORE + 1))
  fi
else
  echo "✅ No SQL instances found"
  COMPLIANCE_SCORE=$((COMPLIANCE_SCORE + 1))
fi

# 7. Check GKE private clusters
echo "⚙️  Checking GKE clusters..."
GKE_ISSUES=0
if gcloud container clusters list --project=$PROJECT_ID --format="value(name)" 2>/dev/null | while read CLUSTER; do
  [ -n "$CLUSTER" ] || continue
  PRIVATE=$(gcloud container clusters describe $CLUSTER --project=$PROJECT_ID --format="value(privateClusterConfig.enablePrivateNodes)" 2>/dev/null)
  if [ "$PRIVATE" != "True" ]; then
    echo "❌ $CLUSTER is not a private cluster"
    GKE_ISSUES=$((GKE_ISSUES + 1))
  fi
done; then
  if [ "$GKE_ISSUES" -gt 0 ]; then
    ISSUES+=("$GKE_ISSUES GKE clusters are not private")
  else
    echo "✅ All GKE clusters are private (or no clusters)"
    COMPLIANCE_SCORE=$((COMPLIANCE_SCORE + 1))
  fi
else
  echo "✅ No GKE clusters found"
  COMPLIANCE_SCORE=$((COMPLIANCE_SCORE + 1))
fi

# 8. Check audit logging
echo "📋 Checking audit logging..."
if gcloud logging sinks list --project=$PROJECT_ID --filter="name:audit" 2>/dev/null | grep -q "audit"; then
  echo "✅ Audit logging sink found"
  COMPLIANCE_SCORE=$((COMPLIANCE_SCORE + 1))
else
  echo "⚠️  No audit logging sink found"
  ISSUES+=("No audit logging sink configured")
fi

# 9. Check IAM recommendations
echo "👤 Checking IAM..."
IAM_ISSUES=$(gcloud recommender recommendations list --project=$PROJECT_ID --recommender=google.iam.policy.Recommender --format="value(name)" 2>/dev/null | wc -l)
if [ "$IAM_ISSUES" -gt 0 ]; then
  echo "⚠️  $IAM_ISSUES IAM recommendations found"
  ISSUES+=("$IAM_ISSUES IAM security recommendations")
else
  echo "✅ No IAM security recommendations"
  COMPLIANCE_SCORE=$((COMPLIANCE_SCORE + 1))
fi

# 10. Check security command center findings
echo "🛡️  Checking Security Command Center..."
if gcloud scc findings list --organization=981978971260 --filter="resourceName.project=$PROJECT_ID AND category=WEAK_PASSWORD_POLICY OR category=OPEN_FIREWALL" 2>/dev/null | grep -q "findings"; then
  echo "⚠️  Security findings detected"
  ISSUES+=("Security Command Center findings exist")
else
  echo "✅ No critical security findings"
  COMPLIANCE_SCORE=$((COMPLIANCE_SCORE + 1))
fi

# Calculate compliance percentage
COMPLIANCE_PERCENTAGE=$((COMPLIANCE_SCORE * 100 / TOTAL_CHECKS))

echo ""
echo "=== Compliance Summary for $PROJECT_ID ==="
echo "Score: $COMPLIANCE_SCORE/$TOTAL_CHECKS ($COMPLIANCE_PERCENTAGE%)"
echo ""

if [ "$COMPLIANCE_PERCENTAGE" -ge 80 ]; then
  echo "🎉 HIGH COMPLIANCE - Ready for compliant-systems folder"
  echo "Recommendation: Move to compliant-systems folder"
elif [ "$COMPLIANCE_PERCENTAGE" -ge 60 ]; then
  echo "⚡ MEDIUM COMPLIANCE - Ready for migration"  
  echo "Recommendation: Move to migration-in-progress folder"
else
  echo "🚨 LOW COMPLIANCE - Requires significant work"
  echo "Recommendation: Keep in legacy folder, create remediation plan"
fi

echo ""
if [ ${#ISSUES[@]} -gt 0 ]; then
  echo "Issues to address:"
  for issue in "${ISSUES[@]}"; do
    echo "  - $issue"
  done
else
  echo "No issues found - project is compliant!"
fi

echo ""
echo "Next steps:"
echo "1. Address the issues listed above"
echo "2. Re-run this assessment after fixes"
echo "3. Move project to appropriate folder based on compliance level"
echo ""

# Output machine-readable summary
echo "COMPLIANCE_SCORE=$COMPLIANCE_SCORE"
echo "COMPLIANCE_PERCENTAGE=$COMPLIANCE_PERCENTAGE"
echo "TOTAL_ISSUES=${#ISSUES[@]}"