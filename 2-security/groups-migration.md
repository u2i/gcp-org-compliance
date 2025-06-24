# Groups Migration Guide - Policy v0.7

This guide documents the migration from the simplified 4-group structure to the comprehensive 5-group structure defined in GCP Break-Glass Policy v0.7.

## Group Structure Changes

### Old Groups (v0.4)
- `gcp-admins@u2i.com` - Combined admin/management group
- `gcp-approvers@u2i.com` - Deployment approvers
- `gcp-developers@u2i.com` - Developers
- `gcp-auditors@u2i.com` - Auditors/billing

### New Groups (v0.7)
1. **`gcp-developers@u2i.com`** - Feature branches, read prod logs
2. **`gcp-prodsupport@u2i.com`** - Merge & deploy lane #1, on-call rotation
3. **`gcp-techlead@u2i.com`** - Approve lanes #1-4, security reviewers (AppSec-trained)
4. **`gcp-techmgmt@u2i.com`** - Same as Tech Lead + org-level sign-off (CEO/COO)
5. **`gcp-billing@u2i.com`** - Read-only cost dashboards & invoice export

## Migration Steps

### 1. Create New Groups in Google Workspace

```bash
# As Google Workspace admin, create the new groups
# This must be done in the Google Admin Console
```

Groups to create:
- `gcp-prodsupport@u2i.com`
- `gcp-techlead@u2i.com`
- `gcp-techmgmt@u2i.com`
- `gcp-billing@u2i.com`

### 2. Migrate Group Memberships

#### From `gcp-admins@u2i.com`:
- Tech Leads → `gcp-techlead@u2i.com`
- CEO/COO → `gcp-techmgmt@u2i.com`
- Remove from `gcp-admins@u2i.com` after migration

#### From `gcp-approvers@u2i.com`:
- On-call engineers → `gcp-prodsupport@u2i.com`
- Remove from `gcp-approvers@u2i.com` after migration

#### From `gcp-auditors@u2i.com`:
- Finance team → `gcp-billing@u2i.com`
- Remove from `gcp-auditors@u2i.com` after migration

#### `gcp-developers@u2i.com`:
- Keep as-is, verify all developers are members

### 3. Update IAM Bindings

The Terraform configuration has been updated to use the new groups. After creating the groups:

```bash
cd 2-security
terraform plan
terraform apply
```

### 4. Update GitHub Teams

Create corresponding GitHub teams that match the Google groups:
- `@u2i/gcp-developers`
- `@u2i/gcp-prodsupport`
- `@u2i/gcp-techlead`
- `@u2i/gcp-techmgmt`
- `@u2i/gcp-billing`

### 5. Update CODEOWNERS

Update all `CODEOWNERS` files to use the new teams:
```
# Security-sensitive paths
/auth/** @u2i/gcp-techlead
/infra/secrets/** @u2i/gcp-techlead
/src/security/** @u2i/gcp-techlead

# Infrastructure
*.tf @u2i/gcp-techlead @u2i/gcp-techmgmt
```

### 6. Verify PAM Entitlements

Check that PAM entitlements are updated with new groups:
```bash
gcloud pam entitlements list --location=global --organization=981978971260
```

Expected entitlements:
- `jit-deploy` - Available to developers, prodsupport, techlead
- `jit-tf-admin` - Available to techlead, techmgmt
- `jit-project-bootstrap` - Available to techlead, techmgmt
- `break-glass-emergency` - Available to techmgmt

### 7. Test Access

For each group, verify:
1. PAM access requests work correctly
2. GitHub permissions are appropriate
3. GCP console access matches expectations

### 8. Decommission Old Groups

After 30 days of successful operation:
1. Remove all members from old groups
2. Keep groups inactive for 90 days (audit trail)
3. Delete old groups

## Rollback Plan

If issues arise:
1. Re-add users to old groups
2. Revert Terraform changes: `git checkout v0.4-groups`
3. Apply previous configuration
4. Document issues for resolution

## Approval Requirements by Lane

| Lane | Who Can Request | Who Must Approve |
|------|----------------|------------------|
| Lane 1 (App) | developers, prodsupport, techlead | prodsupport, techlead, techmgmt |
| Lane 2 (Infra) | techlead, techmgmt | techlead + techmgmt (2 approvers) |
| Lane 3 (Org) | techmgmt | 2x techmgmt |
| Lane 4 (Bootstrap) | techlead, techmgmt | 2x techmgmt |

## Timeline

- Week 1: Create new groups, update Terraform
- Week 2: Migrate users, test access
- Week 3-4: Monitor and adjust
- Week 5-8: Parallel operation
- Week 9: Decommission old groups