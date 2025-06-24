# GCP Break-Glass & Change-Management Policy

**Version 0.4 — 24 June 2025**

## 1. Purpose

Provide engineers with a lightweight, auditable path to perform planned and emergency (break-glass) changes on Google Cloud Platform (GCP) while satisfying SOC 2 Type II and ISO 27001—including explicit secure code review requirements.

## 2. Scope

All GCP projects, organisation-level resources, GitHub repositories, and Continuous-Deployment pipelines managed by U2i.

Applies to application code, Kubernetes & Config Connector manifests, Terraform IaC, and one-off console actions.

## 3. Roles & Responsibilities

All Tech Leads receive AppSec training†, so they can perform security reviews.

| Role | Primary Privileges | May Approve Code Review | May Approve Security Review | May Approve JIT | Notes |
|------|-------------------|------------------------|---------------------------|-----------------|-------|
| Developer | Feature branches, read prod logs | ✅ (non-prod) | — | — | |
| Prod Support | Merge & deploy lane #1 | ✅ | — | ✅ (lane #1) | On-call rotation |
| Tech Lead (AppSec-trained) | Approve lanes #1-3 | ✅ | ✅ | ✅ | Acts as Security Reviewer |
| Tech Mgmt | Same as Tech Lead plus org-level sign-off | ✅ | ✅ | ✅ | CEO/COO |
| Non-Tech Mgmt | Read-only dashboards | — | — | — | |

† Tech Leads complete the internal AppSec-101 course and annual refresher; records are stored in the LMS for auditor sampling.

## 4. Change Lanes & Approval Matrix

| # | Lane | Normal Path & Approvals | When Security Review Required | Break-Glass Path<br>(includes TTL) |
|---|------|------------------------|------------------------|---------------------------|
| 1 | App Code + Manifests | • GitHub PR → 1 Prod-Support+ reviewer → GitHub Actions deploy → Cloud Deploy gate (1 approver)<br>• Rollback: same gate—PR with `revert:` prefix merges, triggering redeploy. | Triggers: paths `/auth/**`, `/infra/secrets/**`, `/src/security/**`; label `security-review-needed`; SAST/SCA ≥High. | PagerDuty SEV-1 → JIT-Deploy (30 min) role → peer approval in Slack. Retro-PR + security review within 24 h. |
| 2 | Env Infra (Terraform) | PR → 2 Tech-Lead reviews → CI plan/apply. | Same triggers as lane #1 plus any IAM or network change. | JIT-tf-admin (60 min) with 2 approvers (Tech-Lead + Tech Mgmt); retro-PR + security review within 24 h. |
| 3 | Org-Level Infra (Terraform) | PR → 2 Tech-Lead reviews + Tech Mgmt sign-off → CI apply. | Always (contains IAM/org-policy). | JIT-org-admin (30 min) with 2 Tech Mgmt approvers; retro-PR + security review within 24 h. |

CODEOWNERS lists `@u2i/tech-leads` for security-sensitive paths. Branch-protection rule "Require review from Code Owners" ensures at least one Tech Lead approves when triggers fire. A GitHub Actions check fails if SCA/SAST reports unsuppressed High/Critical issues.

## 5. Secure Code Review Process

**Automated Detection**  
• GitHub Action runs Dependabot, trivy, and custom Go/TS linters on every PR.  
• ≥High findings add label `security-review-needed`.

**Manual Security Review**  
• Performed by any Tech Lead (AppSec-trained).  
• Focus areas: auth flows, secret handling, encryption, external package changes, RBAC/ACLs, egress rules.  
• Dependency lock-file bump (e.g., `package-lock.json`, `go.sum`) requires reviewer to verify no new high-risk transitive deps.

**Approval & Documentation**  
• Reviewer leaves `SECURITY LGTM` comment summarising findings/mitigations.  
• Merge is gated until at least one `SECURITY LGTM` is present when triggers apply.

**Break-Glass Follow-up**  
• Retro-PRs created after incident must obtain a Tech-Lead security review within 24 hours.

## 6. JIT / Break-Glass Controls

**Platform** – Google Cloud Privileged Access Manager (PAM); Cloud Function listens to PAM Pub/Sub events and posts request & decision messages to #audit-log. Messages and grant logs are exported to BigQuery with 400-day retention.

**TTL by lane** – Lane 1: 30 min · Lane 2: 60 min · Lane 3: 30 min.

**Dual approval** – Requestor + one peer (cannot self-approve); org-level requires two Tech Mgmt approvers.

**Runbook** – `runbooks/pam-break-glass.md` defines step-by-step procedure.

**Evidence** – IAM activity log, PAM grant log, Slack approval archive, PagerDuty incident note, retro-PR.

## 7. Audit Artifacts & Retention

| Control | Evidence | Retention |
|---------|----------|-----------|
| Code & security reviews | GitHub PR, reviews, CI checks | 400 days |
| Deploy approvals | Cloud Deploy release history | 400 days |
| JIT/PAM grants | IAM logs + PAM grant export | 400 days |
| SAST/SCA reports | GitHub Action artifacts | 90 days |

## 8. Policy Maintenance

**Owner:** Head of Engineering & Security Lead.

**Review cadence:** Semi-annual or after any SEV-1 involving break-glass or material change to GCP PAM.

**Changes tracked via:** PRs to this doc in `compliance/policies` repo.

## 9. Glossary

**Lane** – A category of change with its own approval flow (see §4).

**TTL** – Time-to-live for JIT role before automatic revocation.

**JIT** – Just-In-Time privilege elevation via GCP PAM.

**Retro-PR** – Pull Request created post-incident to codify manual changes made under break-glass.

**SECURITY LGTM** – GitHub comment by Tech Lead affirming secure code review completion.

**Last approved:** 24 June 2025  
**Next review due:** 24 December 2025