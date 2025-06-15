# U2I Compliance Migration Plan

## Overview
This plan implements compliance gradually across the u2i organization following a zero-standing-privilege architecture.

## Current Status ✅
- **Bootstrap Project**: `u2i-bootstrap` (Created)
- **State Management**: Remote state in `gs://u2i-tfstate`
- **Folder Structure**: 
  - `legacy-systems` (933345237861) - For existing projects with policy exceptions
  - `migration-in-progress` (1003490002560) - Projects being remediated  
  - `compliant-systems` (914995929705) - Fully compliant projects
- **Projects**: 130+ projects identified for migration

## Folder Structure and Strategy

### Phase 1: Initial Setup ✅ COMPLETED
1. ✅ Deploy compliance infrastructure
2. ✅ Move all projects to legacy folder (in progress)
3. ✅ Enable audit logging framework  
4. ✅ Set up monitoring and alerting
5. ✅ Create assessment tools

### Phase 2: Assessment (Week 2-3) 📋 READY TO START
**Goal**: Categorize all 130+ projects by compliance score

**Actions**:
```bash
# Run assessment on all projects
for project in $(gcloud projects list --format="value(projectId)" --filter="parent.type=folder"); do
  ./scripts/assess-project-compliance.sh $project >> compliance-report.txt
done
```

**Expected Outcomes**:
- Projects with 80%+ compliance → Ready for `compliant-systems`
- Projects with 60-79% compliance → Ready for `migration-in-progress`  
- Projects with <60% compliance → Remain in `legacy-systems`

### Phase 3: Quick Wins (Week 4-6) ⚡ PLANNED
**Goal**: Migrate high-compliance projects first

**Typical Quick Wins**:
- Remove service account keys
- Enable CMEK encryption where possible
- Configure audit logging
- Update IAM policies

**Migration Process**:
```bash
# Move ready projects to migration folder
gcloud beta projects move PROJECT_ID --folder=1003490002560 --quiet

# After fixes, move to compliant folder  
gcloud beta projects move PROJECT_ID --folder=914995929705 --quiet
```

### Phase 4: Major Migrations (Month 2-3) 🔧 PLANNED
**Goal**: Handle projects requiring architectural changes

**Common Issues**:
- Network redesigns (remove default VPC, add Cloud NAT)
- GKE cluster migrations to private mode
- Cloud SQL public IP removal
- Application security updates

### Phase 5: Enforcement (Month 4+) 🛡️ PLANNED
**Goal**: Remove policy exceptions and enforce full compliance

**Actions**:
1. Remove legacy folder exceptions from org policies
2. Enforce all security policies organization-wide
3. Set up continuous compliance monitoring
4. Regular compliance audits

## Tools and Scripts

### Available Scripts
- `scripts/move-projects-to-legacy.sh FOLDER_ID` - Move projects to legacy folder
- `scripts/assess-project-compliance.sh PROJECT_ID` - Assess project compliance

### Usage Examples
```bash
# Move all org-level projects to legacy folder
./scripts/move-projects-to-legacy.sh 933345237861

# Assess a specific project
./scripts/assess-project-compliance.sh u2i-jenkins

# Assess all projects in legacy folder
gcloud projects list --filter="parent.id=933345237861" --format="value(projectId)" | \
while read project; do ./scripts/assess-project-compliance.sh $project; done
```

## Success Metrics

| Metric | Current | Target | Timeline |
|--------|---------|--------|----------|
| Projects in legacy folder | 130+ | 0% | Month 4 |
| Projects compliant | 0% | 100% | Month 4 |
| Policy violations | Unknown | 0 | Month 4 |
| Audit coverage | Partial | 100% | Month 1 |

## Next Steps (Immediate Actions)

1. **Run Full Assessment** (This Week):
   ```bash
   # Create assessment report for all projects
   for project in $(gcloud projects list --format="value(projectId)" --filter="parent.type!=organization"); do
     echo "=== $project ===" >> full-compliance-report.txt
     ./scripts/assess-project-compliance.sh $project >> full-compliance-report.txt
   done
   ```

2. **Prioritize Projects** (Next Week):
   - Identify projects with 80%+ compliance for immediate migration
   - Create remediation plans for 60-79% compliance projects
   - Plan architectural changes for <60% compliance projects

3. **Begin Quick Wins** (Week 3-4):
   - Start with highest-scoring projects
   - Move compliant projects to `compliant-systems` folder
   - Document migration patterns for reuse

4. **Set Up GitOps** (Week 2):
   - Configure GitHub Actions with Workload Identity Federation
   - Implement PAM (Privileged Access Management) for write operations
   - Enable pull request workflow for all infrastructure changes

## Risk Mitigation

### Rollback Plan
If issues arise during migration:
1. Move affected projects back to legacy folder
2. Adjust policy exceptions as needed
3. Fix issues in isolated environment
4. Re-attempt migration with lessons learned

### Communication Plan
- Weekly status updates to stakeholders
- Project-specific migration notices to owners
- Compliance training for development teams
- Emergency contact procedures for blocked projects

## Compliance Framework

### Zero-Standing-Privilege Model
- **Service Accounts**: Read-only baseline permissions
- **Write Operations**: Require just-in-time PAM elevation
- **Manual Changes**: Prohibited in production
- **All Changes**: Through GitOps workflow with approvals

### Policy Enforcement
- **Legacy Folder**: Temporary exceptions for gradual migration
- **Migration Folder**: Partial enforcement during remediation
- **Compliant Folder**: Full policy enforcement
- **Organization**: Gradual rollout to avoid breaking existing services

## Architecture Summary

```
Organization (981978971260)
├── bootstrap/
│   └── u2i-bootstrap (Terraform state, service accounts)
├── legacy-systems/ (933345237861)  
│   ├── external-apps/
│   ├── internal-tools/
│   └── experiments/
├── migration-in-progress/ (1003490002560)
│   ├── phase-1/
│   ├── phase-2/  
│   └── phase-3/
└── compliant-systems/ (914995929705)
    ├── production/
    ├── staging/
    ├── development/
    └── shared-services/
```

This structure enables gradual migration while maintaining operational stability and providing clear compliance tracking.