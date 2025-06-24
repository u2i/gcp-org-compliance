# GCP Break-Glass & Change-Management Policy

**Version 0.3 — 24 June 2025**

## 1. Purpose

Provide engineers with a lightweight, auditable path to perform planned and emergency (break-glass) changes on Google Cloud Platform (GCP) while satisfying SOC 2 Type II and ISO 27001—including explicit secure code review requirements.

## 2. Scope

All GCP projects, organisation-level resources, GitHub repositories, and Continuous-Deployment pipelines managed by U2i.

Applies to application code, Kubernetes & Config Connector manifests, Terraform IaC, and one-off console actions.

## 3. Roles & Responsibilities

All Tech Leads receive AppSec training, so they can perform security reviews.

| Role | Primary Privileges | May Approve Code Review | May Approve Security Review | May Approve JIT | Notes |
|------|-------------------|------------------------|---------------------------|-----------------|-------|
| Developer | Feature branches, read prod logs | ✅ (non-prod) | — | — | |
| Prod Support | Merge & deploy lane #1 | ✅ | — | ✅ (lane #1) | On-call rotation |
| Tech Lead (AppSec-trained) | Approve lanes #1-3 | ✅ | ✅ | ✅ | Acts as Security Reviewer |
| Tech Mgmt | Same as Tech Lead plus org-level sign-off | ✅ | ✅ | ✅ | CEO/COO |
| Non-Tech Mgmt | Read-only dashboards | — | — | — | |

## 4. Change Lanes & Approval Matrix

| # | Lane | Normal Path & Approvals | Security Review Trigger | Break-Glass Path (any lane) |
|---|------|------------------------|------------------------|---------------------------|
| 1 | App Code + Manifests | GitHub PR → 1 Prod-Support+ reviewer → GitHub Actions deploy → Cloud Deploy gate (1 approver) | Required when:<br>• files match `/auth/**`, `/infra/secrets/**`, or `/src/security/**`<br>• Label `security-review-needed` added<br>• SAST/Dependency scanner flags ≥High severity | PagerDuty SEV-1 → JIT-Deploy role (30 min) → peer approval in Slack. Retro-PR must be security-reviewed (Tech Lead) within 24 h. |
| 2 | Env Infra (Terraform) | PR → 2 Tech-Lead reviews → CI plan/apply | Same triggers as lane #1 plus any IAM or network changes | JIT-tf-admin (1 h) with 2 approvers (Tech-Lead + Tech Mgmt); retro-PR + security review within 24 h |
| 3 | Org-Level Infra (Terraform) | PR → 2 Tech-Lead reviews + Tech Mgmt sign-off → CI apply | Always (contains IAM/org-policy) | JIT-org-admin (30 min) with 2 Tech Mgmt approvers; retro-PR + security review within 24 h |

**How security review is enforced:** CODEOWNERS lists `@u2i/tech-leads` for security-sensitive paths. Branch-protection rule "Require review from Code Owners" ensures at least one Tech Lead approves when triggers fire. A GitHub Actions check fails if SCA/SAST reports unsuppressed High/Critical issues.

## 5. Secure Code Review Process

**Automated Detection**
• GitHub Action runs Dependabot, trivy, and custom Go/TS linters on every PR.
• On ≥High findings the action adds label `security-review-needed`.

**Manual Security Review**
• Performed by any Tech Lead (all AppSec-trained).
• Focus areas: auth flows, secret handling, encryption, external package changes, RBAC/ACLs, egress rules.

**Approval & Documentation**
• Reviewer leaves `SECURITY LGTM` comment summarising findings/mitigations.
• Merge is gated until at least one `SECURITY LGTM` is present when triggers apply.

**Break-Glass Follow-up**
• Retro-PRs created after incident must obtain a Tech-Lead security review within 24 hours.

## 6. JIT / Break-Glass Controls

**Platform:** Opal (or Sym/ConductorOne) for Slack-native role elevation.

**TTL:** 15–60 minutes depending on lane.

**Dual Approval:** Requestor + one peer (cannot self-approve); org-level requires Tech Mgmt.

**Evidence:** IAM activity log, Opal audit record, PagerDuty incident note, retro-PR.

## 7. Audit Artifacts & Retention

| Control | Evidence | Retention |
|---------|----------|-----------|
| Code review (functional & security) | GitHub PR, reviews, CI checks | 1 year |
| Deploy approvals | Cloud Deploy release history | 1 year |
| JIT grants | IAM logs + Opal export | 1 year |
| SAST/SCA reports | GitHub Action artifacts | 90 days |

## 8. Policy Maintenance

**Owner:** Head of Engineering & Security Lead.

**Review cadence:** Semi-annual or after any SEV-1 involving break-glass.

**Changes tracked via:** PRs to this doc in `compliance/policies` repo.

**Last approved:** 24 June 2025  
**Next review due:** 24 December 2025