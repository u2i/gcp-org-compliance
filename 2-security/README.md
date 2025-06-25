# Security Phase - Centralized Security Infrastructure

This phase implements organization-wide security controls including Privileged Access Manager (PAM), centralized logging, and monitoring infrastructure aligned with the [GCP Break-Glass & Change-Management Policy](../policies/gcp-break-glass-change-management-policy.md).

## Overview

The security phase provides:
- **PAM (Privileged Access Manager)** - Just-in-time access with proper approvals
- **Centralized Audit Logging** - All security events logged to BigQuery
- **Security Monitoring** - Real-time alerts for critical events

## JIT Access Implementation

Per the organization policy, we use a dual-approval system for privileged access:

### Change Lanes

| Lane | Normal Approval | Break-Glass Duration | Break-Glass Approval |
|------|----------------|---------------------|---------------------|
| App Code (Lane 1) | 1 Prod Support reviewer | 30 min | Peer approval via Slack |
| Env Infra (Lane 2) | 2 Tech Lead reviews | 1 hour | Tech Lead + Tech Mgmt |
| Org Infra (Lane 3) | 2 Tech Lead + Tech Mgmt | 30 min | 2 Tech Mgmt approvers |

### PAM Entitlements

| Entitlement | Duration | Approval Required | Use Case |
|------------|----------|------------------|----------|
| admin-elevation | 2 hours | 1 Tech Lead peer | Infrastructure changes |
| deployment-approver-access | 2 hours | 1 peer approver | Production deployments |
| developer-prod-access | 2 hours | 1 Tech Lead | Production debugging |
| billing-access | 4 hours | 1 Tech Lead | Financial reports |
| break-glass-emergency | 1 hour | 2 Tech Mgmt | True emergencies |

**Note**: The policy requires dual approval (no self-approval), enforced by Google PAM.

## Requesting JIT Access

### Standard Access Request
```bash
# Request production access for debugging
gcloud pam grants create \
  --entitlement="developer-prod-access" \
  --justification="Debug customer issue #1234" \
  --requested-duration="7200s" \
  --location="global" \
  --organization="[ORG_ID]"
```

### Emergency Break-Glass
For SEV-1 incidents requiring immediate access:

```bash
# Request break-glass access (requires 2 Tech Mgmt approvals)
gcloud pam grants create \
  --entitlement="break-glass-emergency" \
  --justification="SEV-1: Production outage affecting all users" \
  --requested-duration="3600s" \
  --location="global" \
  --organization="[ORG_ID]"
```

**Important**: Break-glass requests require approval from 2 Tech Management members and trigger immediate alerts to the security team.

## Deployment

### Prerequisites
- Terraform 1.6+
- Organization admin permissions
- Groups created in Google Workspace:
  - `gcp-admins@[domain]` - Tech Management
  - `gcp-developers@[domain]` - Development team
  - `gcp-approvers@[domain]` - Production approvers (Prod Support+)
  - `@u2i/tech-leads` - GitHub team for security reviews

### Deploy Security Infrastructure
```bash
cd 2-security
terraform init
terraform plan
terraform apply
```

### Resources Created
- **Projects**: `[prefix]-security`, `[prefix]-logging`
- **PAM Entitlements**: 5 standard + 1 break-glass
- **Monitoring**: Break-glass alerts, audit dashboards
- **BigQuery**: Centralized audit log dataset

## Monitoring & Alerts

### Break-Glass Usage Alert
Any use of break-glass access triggers:
- Email to Tech Management team
- Cloud Monitoring alert
- Audit log entry
- Requirement for post-incident review

### Audit Queries
```sql
-- Recent PAM activities
SELECT 
  timestamp,
  protoPayload.authenticationInfo.principalEmail as requester,
  protoPayload.request.justification.unstructuredJustification as reason,
  protoPayload.response.state as status
FROM `[project].audit_logs.cloudaudit_logs_*`
WHERE protoPayload.serviceName = 'privilegedaccessmanager.googleapis.com'
  AND DATE(timestamp) >= CURRENT_DATE()
ORDER BY timestamp DESC
```

## Post-Incident Requirements

Per policy section 5, after any break-glass usage:
1. Create retro-PR within 24 hours
2. Obtain Tech Lead security review
3. Document in incident report
4. Update runbooks if needed

## Compliance Alignment

This implementation satisfies:
- **ISO 27001**: A.9.2.3 (Privileged access), A.12.4.1 (Event logging)
- **SOC 2**: CC6.1 (Logical access), CC7.2 (System monitoring)
- **GDPR**: Article 32 (Security measures)

## Integration with Audit Systems

Per policy section 6, PAM events are:
- Published to Pub/Sub for real-time processing
- Posted to `#audit-log` Slack channel via Cloud Function
- Exported to BigQuery with 400-day retention
- Integrated with Cloud Monitoring for alerting

The organization uses Google PAM as the primary JIT platform, with Cloud Functions providing Slack integration for approval notifications.

## Next Steps

1. Configure notification channels in Google Workspace
2. Set up Opal/Sym integration for Slack approvals
3. Train Tech Leads on security review process
4. Schedule semi-annual policy review

For detailed procedures, see:
- [GCP Break-Glass & Change-Management Policy](../policies/gcp-break-glass-change-management-policy.md)
- [Security Review Process](../policies/security-review-process.md)