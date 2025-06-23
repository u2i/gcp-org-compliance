# Security Phase - PAM and Break Glass Implementation

This phase implements organization-wide Privileged Access Management (PAM) with break glass capabilities.

## Overview

The security phase establishes:
- Zero-standing-privilege architecture
- Just-in-time access elevation via PAM
- Emergency break glass procedures
- Centralized audit logging
- Security monitoring and alerting

## Break Glass Access

### Who Can Activate Break Glass
1. **Failsafe Account** (`gcp-failsafe@u2i.com`)
2. **Emergency Responders Group** (`gcp-emergency-responders@u2i.com`)

### What Break Glass Provides
- Organization-wide owner permissions
- 1-hour duration (automatic expiration)
- Self-approval (no waiting)
- Immediate alerts to security team

### How to Activate
```bash
gcloud pam grants create \
  --entitlement="break-glass-emergency" \
  --justification="EMERGENCY: [reason]" \
  --requested-duration="3600s" \
  --location="global" \
  --project="u2i-security"
```

## Standard PAM Entitlements

| Entitlement | Eligible Users | Permissions | Duration | Approvals |
|-------------|----------------|-------------|----------|-----------|
| Platform Engineer Prod | gcp-platform-engineers@ | Platform admin | 2 hours | 1 approval |
| Security Analyst | gcp-security-analysts@ | Org-wide read | 4 hours | 2 approvals |
| Incident Responder | gcp-incident-responders@ | Prod emergency | 1 hour | 1 approval |
| Compliance Auditor | gcp-compliance-auditors@ | Audit read-only | 4 hours | 1 approval |

## Prerequisites

Before deploying this phase:

1. **Create Google Groups** (in Workspace Admin):
   - `gcp-emergency-responders@u2i.com`
   - `gcp-platform-engineers@u2i.com`
   - `gcp-platform-leads@u2i.com`
   - `gcp-security-analysts@u2i.com`
   - `gcp-security-leads@u2i.com`
   - `gcp-incident-responders@u2i.com`
   - `gcp-incident-commanders@u2i.com`
   - `gcp-compliance-auditors@u2i.com`
   - `gcp-compliance-leads@u2i.com`

2. **Configure Notification Channels**:
   - Set up Slack webhook URL
   - Configure PagerDuty integration
   - Verify email addresses

## Deployment

```bash
cd gcp-org-compliance/2-security
terraform init
terraform plan -var-file=../terraform.tfvars
terraform apply -var-file=../terraform.tfvars
```

## Post-Deployment

1. **Test Break Glass**:
   ```bash
   # As failsafe account, test emergency access
   gcloud pam grants create \
     --entitlement="break-glass-emergency" \
     --justification="TEST: Testing break glass procedure" \
     --requested-duration="300s" \
     --location="global" \
     --project="u2i-security"
   ```

2. **Verify Alerts**:
   - Check that security team received email
   - Verify Slack notification
   - Confirm PagerDuty alert (if configured)

3. **Review Audit Logs**:
   ```sql
   -- In BigQuery
   SELECT 
     timestamp,
     protoPayload.authenticationInfo.principalEmail,
     protoPayload.request.justification.unstructuredJustification
   FROM `u2i-logging.audit_logs.pam_activities`
   WHERE DATE(timestamp) = CURRENT_DATE()
   ```

## Monitoring

- **Dashboard**: Cloud Console → Monitoring → "PAM Emergency Access"
- **Audit Logs**: BigQuery → `u2i-logging.audit_logs`
- **Alerts**: Configured via notification channels

## Compliance

This implementation satisfies:
- ISO 27001 A.9.2.3 - Management of privileged access rights
- SOC 2 CC6.1 - Logical access controls
- GDPR Article 32 - Security of processing