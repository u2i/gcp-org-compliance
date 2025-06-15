# GCP Organization Compliance Infrastructure

Zero-standing-privilege architecture for implementing compliance in existing Google Cloud Organizations with gradual project migration.

## 🏗️ Architecture Overview

This implementation follows a **zero-standing-privilege model** where:
- Service accounts have read-only baseline permissions
- Write operations require just-in-time privilege elevation (PAM)
- All infrastructure changes go through GitOps workflows
- Projects migrate gradually through compliance tiers

## 📁 Project Structure

```
gcp-org-compliance/
├── 0-bootstrap/       # Bootstrap project and Terraform state management
├── 1-organization/    # Organization-wide policies and folder structure  
├── scripts/           # Migration and assessment utilities
└── MIGRATION_PLAN.md  # Detailed migration strategy
```

## 🚀 Quick Start

### Prerequisites
- Google Cloud Organization with billing enabled
- `gcp-failsafe@yourdomain.com` user with Organization Admin role
- Terraform >= 1.6
- gcloud CLI authenticated

### 1. Bootstrap Infrastructure

```bash
# Clone repository
git clone https://github.com/u2i/gcp-org-compliance.git
cd gcp-org-compliance

# Deploy bootstrap project
cd 0-bootstrap
terraform init
terraform apply

# Configure remote state
terraform init -migrate-state
```

### 2. Deploy Organization Structure

```bash
# Deploy compliance folders and policies
cd ../1-organization  
terraform init
terraform apply
```

### 3. Migrate Existing Projects

```bash
# Move projects to legacy folder (with policy exceptions)
./scripts/move-projects-to-legacy.sh LEGACY_FOLDER_ID

# Assess project compliance
./scripts/assess-project-compliance.sh PROJECT_ID
```

## 📊 Compliance Tiers

### 🟡 Legacy Systems (Temporary Exceptions)
- **Purpose**: Existing projects during migration
- **Policies**: Exceptions for breaking changes
- **Timeline**: Gradual migration over 3-4 months

### 🟠 Migration In Progress (Partial Enforcement)
- **Purpose**: Projects being remediated
- **Policies**: Partial compliance requirements
- **Timeline**: 2-4 weeks per project batch

### 🟢 Compliant Systems (Full Enforcement)
- **Purpose**: Fully compliant projects
- **Policies**: Complete security policy enforcement
- **Timeline**: Ongoing operational state

## 🛠️ Tools and Scripts

### Project Migration
```bash
# Move all org-level projects to legacy folder
./scripts/move-projects-to-legacy.sh 933345237861

# Move specific project to migration folder
gcloud beta projects move PROJECT_ID --folder=MIGRATION_FOLDER_ID --quiet
```

### Compliance Assessment
```bash
# Assess single project (10-point scoring system)
./scripts/assess-project-compliance.sh my-project-id

# Bulk assessment
gcloud projects list --format="value(projectId)" --filter="parent.type=folder" | \
while read project; do ./scripts/assess-project-compliance.sh $project; done
```

### Assessment Scoring
- **80-100%**: Ready for compliant-systems folder
- **60-79%**: Ready for migration-in-progress folder  
- **0-59%**: Remains in legacy folder, needs remediation plan

## 🔒 Security Features

### Zero-Standing-Privilege Model
- **Bootstrap SA**: Read-only + state bucket access only
- **Organization SA**: Read-only + temporary PAM elevation
- **Manual Override**: Emergency access via break-glass procedures

### Policy Framework
- **Immediate Enforcement**: Critical security policies (audit logging, SSL)
- **Gradual Enforcement**: Breaking policies with legacy exceptions
- **Future Enforcement**: Advanced policies (Binary Authorization, etc.)

### Compliance Monitoring
- Real-time Security Command Center integration
- Automated IAM recommendation tracking
- Continuous policy violation detection

## 🔄 GitOps Workflow

### Pull Request Process
1. **Plan**: Terraform plan on PR creation (read-only)
2. **Review**: Required approvals from security team
3. **Apply**: PAM elevation + terraform apply on merge
4. **Audit**: All changes logged and monitored

### PAM Integration
```yaml
# GitHub Actions workflow example
- name: Request PAM Elevation
  run: |
    gcloud beta pam grants create \
      --entitlement="terraform-org-deploy" \
      --requested-duration="1800s" \
      --justification="GitHub Actions deployment"
```

## 📈 Migration Progress Tracking

### Success Metrics
| Metric | Current | Target |
|--------|---------|--------|
| Projects in Legacy | 130+ | 0% |
| Policy Compliance | Variable | 100% |
| Audit Coverage | Partial | 100% |
| Zero-Standing-Privilege | ✅ | 100% |

### Rollback Procedures
- Move projects back to legacy folder if issues arise
- Temporary policy exception adjustments
- Emergency break-glass access procedures

## 🚨 Emergency Procedures

### Break-Glass Access
```bash
# Emergency organization access (use sparingly)
gcloud auth login gcp-failsafe@u2i.com

# Emergency project access
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="user:gcp-failsafe@u2i.com" \
  --role="roles/owner"
```

### Issue Resolution
1. **Service Disruption**: Move project back to legacy folder
2. **Policy Conflicts**: Adjust exceptions in security baseline module
3. **Access Issues**: Use break-glass procedures with full audit trail

## 🤝 Contributing

### Development Workflow
1. Create feature branch
2. Test changes in development environment
3. Submit PR with compliance impact assessment
4. Security team review and approval
5. Automated deployment via GitOps

### Module Updates
- Uses pre-built modules from `terraform-google-compliance-modules`
- Version pinned to `v1.0.19` for stability
- Update process requires security review

## 📚 Documentation

- **[Migration Plan](MIGRATION_PLAN.md)**: Detailed implementation timeline
- **[Security Policies](1-organization/main.tf)**: Organization-wide compliance rules
- **[Assessment Guide](scripts/assess-project-compliance.sh)**: Project compliance scoring

## 🏷️ Tags and Labels

### Project Labels
- `compliance-status`: `legacy|migrating|compliant|exempt`
- `migration-date`: Date moved to migration folder
- `compliant-date`: Date achieved full compliance

### Resource Tags
- `compliance`: `legacy|migration|third_party`
- `environment`: `prod|stg|dev|shared`
- `cost-center`: For billing allocation

## 🎯 Roadmap

### Phase 1: Foundation (✅ Complete)
- [x] Bootstrap infrastructure
- [x] Folder structure
- [x] Migration tooling
- [x] Assessment framework

### Phase 2: Assessment (🔄 In Progress)
- [ ] Bulk project assessment
- [ ] Compliance scoring
- [ ] Migration prioritization
- [ ] Remediation planning

### Phase 3: Migration (📅 Planned)
- [ ] Quick wins (80%+ compliance)
- [ ] Systematic remediation
- [ ] Architectural changes
- [ ] Policy enforcement

### Phase 4: Operations (🎯 Target)
- [ ] Full policy enforcement
- [ ] Continuous monitoring
- [ ] Regular compliance audits
- [ ] Team training and documentation

---

## 📞 Support

- **Repository**: [github.com/u2i/gcp-org-compliance](https://github.com/u2i/gcp-org-compliance)
- **Issues**: GitHub Issues for bugs and feature requests
- **Security**: security@u2i.com for security-related concerns
- **Compliance**: compliance@u2i.com for compliance questions

**🤖 Generated with [Claude Code](https://claude.ai/code)**