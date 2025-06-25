# PAM Break-Glass Runbook

**Last Updated:** 24 June 2025  
**Owner:** Head of Engineering & Security Lead

## Purpose

Step-by-step procedure for requesting and approving break-glass access via Google Cloud PAM during incidents.

## Prerequisites

- Active PagerDuty incident (SEV-1 or SEV-2)
- Member of appropriate group:
  - Lane 1: `gcp-developers@u2i.com` or `gcp-approvers@u2i.com`
  - Lane 2/3: `gcp-admins@u2i.com` (Tech Mgmt)
- `gcloud` CLI installed and authenticated

## Break-Glass Procedures by Lane

### Lane 1: App Code Emergency (30 min TTL)

**When to use:** Production outage requiring immediate code deployment or rollback.

1. **Create PAM Grant Request**
   ```bash
   gcloud pam grants create \
     --entitlement="developer-prod-access" \
     --justification="SEV-1 #[INCIDENT_ID]: [Brief description]" \
     --requested-duration="1800s" \
     --location="global" \
     --organization="981978971260"
   ```

2. **Request Approval in Slack**
   - Post in `#incidents`: `@oncall Need PAM approval for SEV-1 #[INCIDENT_ID]`
   - Share grant ID from step 1

3. **Approver Actions** (any Tech Lead)
   ```bash
   gcloud pam grants approve [GRANT_ID] \
     --reason="Approved for SEV-1 response" \
     --entitlement="developer-prod-access" \
     --location="global" \
     --organization="981978971260"
   ```

4. **Perform Emergency Actions**
   - Deploy fix via Cloud Deploy
   - Or rollback to previous version
   - Document all actions in incident channel

### Lane 2: Infrastructure Emergency (60 min TTL)

**When to use:** Infrastructure issues requiring Terraform changes.

1. **Create PAM Grant Request**
   ```bash
   gcloud pam grants create \
     --entitlement="admin-elevation" \
     --justification="SEV-1 #[INCIDENT_ID]: Infrastructure emergency" \
     --requested-duration="3600s" \
     --location="global" \
     --organization="981978971260"
   ```

2. **Get Dual Approval**
   - Requires: 1 Tech Lead + 1 Tech Mgmt
   - Post in `#incidents` and tag both approvers
   - Share grant ID

3. **First Approver** (Tech Lead)
   ```bash
   gcloud pam grants approve [GRANT_ID] \
     --reason="Tech Lead approval for infrastructure emergency" \
     --entitlement="admin-elevation" \
     --location="global" \
     --organization="981978971260"
   ```

4. **Second Approver** (Tech Mgmt)
   ```bash
   gcloud pam grants approve [GRANT_ID] \
     --reason="Tech Mgmt approval for infrastructure emergency" \
     --entitlement="admin-elevation" \
     --location="global" \
     --organization="981978971260"
   ```

### Lane 3: Organization Emergency (30 min TTL)

**When to use:** Organization-wide issues (IAM, policies, billing).

1. **Create PAM Grant Request**
   ```bash
   gcloud pam grants create \
     --entitlement="break-glass-emergency" \
     --justification="SEV-1 #[INCIDENT_ID]: Org-wide emergency" \
     --requested-duration="1800s" \
     --location="global" \
     --organization="981978971260"
   ```

2. **Get Dual Tech Mgmt Approval**
   - Requires: 2 Tech Mgmt members
   - Call/Slack both immediately
   - Share grant ID

3. **Both Approvers Execute**
   ```bash
   gcloud pam grants approve [GRANT_ID] \
     --reason="Tech Mgmt approval for org emergency" \
     --entitlement="break-glass-emergency" \
     --location="global" \
     --organization="981978971260"
   ```

## Post-Incident Requirements

Within 24 hours of break-glass usage:

1. **Create Retro-PR**
   - Title: `retro: [INCIDENT_ID] Emergency changes`
   - Document all manual changes made
   - Include incident timeline

2. **Get Security Review**
   - Add label: `security-review-needed`
   - Assign to Tech Lead for review
   - Must receive `SECURITY LGTM`

3. **Update Documentation**
   - Add to incident post-mortem
   - Update runbooks if needed
   - Share learnings in engineering meeting

## Monitoring & Alerts

Break-glass usage triggers:
- Email to `gcp-admins@u2i.com`
- Slack post to `#audit-log`
- Cloud Monitoring alert
- BigQuery audit entry

## Common Issues

### "Permission Denied" on Approval
- Verify you're in the correct group
- Check if incident is properly declared
- Ensure you're using correct entitlement name

### Grant Request Fails
- Check if previous grant is still active
- Verify justification includes incident ID
- Ensure duration is within limits

### Access Not Working After Approval
- Allow 30-60 seconds for propagation
- Run `gcloud auth application-default login`
- Check if accessing correct project/resource

## Emergency Contacts

- **On-Call Engineer:** Check PagerDuty
- **Tech Mgmt:** See internal contact list
- **Security Team:** security@u2i.com
- **Google Cloud Support:** [Premium support number]

## Related Documents

- [GCP Break-Glass & Change-Management Policy](../policies/gcp-break-glass-change-management-policy.md)
- [Incident Response Procedures](incident-response.md)
- [PAM Entitlement Definitions](../2-security/README.md)