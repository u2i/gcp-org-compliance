# GCP Break-Glass & Change-Management Policy

**Version 0.7 — 24 June 2025**

## 1. Purpose

Provide engineers with a lightweight, auditable path to perform **planned** and **emergency (break-glass)** changes on Google Cloud Platform (GCP) while satisfying **SOC 2 Type II** and **ISO 27001**—including explicit **secure code review** requirements.

## 2. Scope

- All GCP projects, organisation-level resources, GitHub repositories, and Continuous-Deployment pipelines managed by **U2i**.
- **Project Bootstrap Workflow** for creating new GCP projects under the organisation **and their companion Terraform & application repositories**.
- Applies to application code, Kubernetes & Config Connector manifests, Terraform Infrastructure-as-Code, and one-off console actions.

## 3. Roles & Responsibilities

*All Tech Leads receive AppSec training†, so they can perform security reviews.* Every engineer is a member of exactly one Google Workspace **group** (below) which controls GitHub permissions, GCP IAM bindings, and approval rights.

| Role | Group (email) | Primary Privileges | May Approve Code Review | May Approve **Security Review** | May Approve JIT | Notes |
|------|---------------|-------------------|------------------------|---------------------------|-----------------|-------|
| Developer | gcp-developers@u2i.com | Feature branches, read prod logs | ✅ (non-prod) | — | — | |
| Prod Support | gcp-prodsupport@u2i.com | Merge & deploy lane #1 | ✅ | — | ✅ (lane #1) | On-call rotation |
| **Tech Lead** (AppSec-trained) | gcp-techlead@u2i.com | Approve lanes #1-4 | ✅ | **✅** | ✅ | Acts as Security Reviewer |
| Tech Mgmt | gcp-techmgmt@u2i.com | Same as Tech Lead plus org-level sign-off | ✅ | ✅ | ✅ | CEO/COO |
| Billing / Finance | gcp-billing@u2i.com | Read-only cost dashboards & invoice export | — | — | — | Replaces former Non-Tech Mgmt row |

† *Tech Leads complete the internal **AppSec-101** course and annual refresher; records are stored in the LMS for auditor sampling.*

### 3.1 Failsafe Google Account

- **u2i-failsafe@google.com** – A privileged workforce account with Org Admin, Project Creator, and Billing Admin roles.
- Credentials: strong password + U2F hardware key held by *Head of Engineering* and *Security Lead* in separate sealed envelopes stored in the company safe.
- **Activation criteria**: simultaneous loss of Google Cloud PAM *and* Workspace SSO (e.g., IdP outage) that blocks incident response.
- **Procedure**: Tech Mgmt quorum (CEO + one Tech Lead) retrieve envelopes, perform action, then rotate credentials and record incident in `#audit-log` and PagerDuty. Retro-PR required within **24 h**.

## 4. Change Lanes & Approval Matrix

| # | Lane | Normal Path & Approvals | **When Security Review Required** | Break-Glass Path (+ TTL) |
|---|------|------------------------|------------------------|------------------------------|
| 1 | **App Code + Manifests** | • GitHub PR → **1 Prod-Support+ reviewer** → GitHub Actions deploy → Cloud Deploy gate (1 approver)<br>• **Rollback**: same gate—PR with `revert:` prefix merges, triggering redeploy. | **Triggers**: paths **`/auth/**`**, **`/infra/secrets/**`**, **`/src/security/**`**; label `security-review-needed`; SAST/SCA ≥High. | PagerDuty SEV-1 → **JIT-Deploy (30 min)** role → peer approval in Slack. Retro-PR + security review within **24 h**. |
| 2 | **Env Infra (Terraform)** | PR → **2 Tech-Lead** reviews → CI plan/apply. | Same triggers as lane #1 **plus** any IAM or network change. | **JIT-tf-admin (60 min)** with 2 approvers (Tech-Lead + Tech Mgmt); retro-PR + security review within **24 h**. |
| 3 | **Org-Level Infra (Terraform)** | PR → **2 Tech-Lead** reviews **+ Tech Mgmt sign-off** → **Cloud Build `org-apply` pipeline** executes Terraform `modules/org-root` under Service Account `sa-org-apply@org` (least-priv) → plan artifact published as GitHub Actions artifact and gated by an **Environment "org-prod"** manual *Apply* approval. | Always (contains IAM/org-policy). | **JIT-org-admin (30 min)** with 2 Tech Mgmt approvers; retro-PR + security review within **24 h**. |
| 4 | **Everything-as-Code Project Bootstrap** | GitHub **workflow dispatch** (`project-bootstrap.yml`) with project name & owners → Cloud Build runs *Project Factory* Terraform in **two stages**:<br>  1. **Org-prep** module – sets/updates Org Policy, VPC-SC perimeter, logging sinks.<br>  2. **Project Factory** – creates new GCP project, billing link, baseline IAM, logging, and service enablement.<br>Cloud Build then:<br>  • uses **Terraform GitHub provider** to create two new repos:<br>    * `terraform-<project>` — seeds TF state backend and CI pipeline<br>    * `<project>-service` — application repo with starter Dockerfile & K8s manifest<br>  • pushes repo skeletons from templates (`.github/workflows`, CODEOWNERS, branch-protection via GitHub API)<br>  • opens onboarding PR tagging requester.<br>**Approvals**: 2 Tech-Lead reviews **+ Tech Mgmt sign-off** on the bootstrap PR. | Always (creates new IAM perimeter and logging sinks). | **JIT-org-admin (30 min)** with 2 Tech Mgmt approvers; manual fallback runs `gcloud projects create`, attaches billing, and initialises repos via GitHub CLI; retro-PR to Project Factory within **24 h**. |

> **Everything-as-Code Goal** – A single button (workflow dispatch) boots an auditable trail that covers *org config → project → infra repos → app repo → CI/CD hooks*. The requester owns the first onboarding PR in each new repo.

### 4.1 Project Bootstrap Workflow Steps (Detail)

1. **Workflow Trigger** – Engineer runs `gh workflow run project-bootstrap.yml --ref main -F name=myproj -F owners=@u2i/tech-leads`.
2. **Stage A: Org Update** – Terraform `modules/org-prep` applies VPC-SC config, logging sinks, and Org Policy exceptions scoped **only** to the new project ID.
3. **Stage B: Project Creation** – Terraform `modules/project-factory` creates the project, links to **u2i-billing**, enables APIs, sets baseline IAM (groups from §3).
4. **Stage C: Repo & CI Bootstrapping** – Terraform GitHub provider creates two repos using cookie-cutter templates, pushes branch protection, CODEOWNERS, OIDC secrets.
5. **Stage D: Pull-Request Hand-off** – Workflow opens PR "✨ bootstrap myproj infrastructure" in `terraform-myproj` tagging `@u2i/tech-leads`.
6. **Evidence** – Cloud Build logs & Terraform plan files → GCS bucket `gs://project-bootstrap-logs` (**400-day** lifecycle).

### 4.2 Org-Level Infra Workflow Steps (Detail)

**Source of truth** – Monorepo **`terraform-org`**.  All organisation-level IaC lives here; the default branch is **`main`** and is protected as per Lane #3.

0. **Author Workflow**
   * Engineer checks out a feature branch, edits `*.tf`, `*.tfvars`, or module source code inside `modules/org-root` or its children.
   * Pre-commit hooks run `terraform fmt`, `tflint`, and `checkov`.
   * The change is pushed; a GitHub **Pull Request** to `main` is opened.
   * **Renovate Bot** also raises provider/module version-bump PRs following the same workflow.

1. **Plan Stage (`org-plan`)**
   * Cloud Build is triggered on PR open / update.
   * Commands executed:
     ```bash
     terraform init -backend-config=bucket=tf-state-org-root -upgrade
     terraform plan -lock=true -lock-timeout=60s -out=org-plan.binary
     terraform show -json org-plan.binary > org-plan.json
     ```
   * Outputs: human-readable **`org-plan.txt`** and machine JSON.
   * Artifacts are attached to the PR via GitHub Checks.

2. **Review & Approvals**
   * Required: **2 Tech-Lead** + **1 Tech Mgmt** (enforced by GitHub Environment `org-prod`).
   * Reviewers must confirm the SHA matches the latest successful plan.

3. **Apply Stage (`org-apply`)**
   * Upon manual *Apply* approval, Cloud Build re-executes `terraform apply -input=false -auto-approve org-plan.binary` under Service Account **`sa-org-apply@org`** (least-priv).
   * Backend state `gs://tf-state-org-root` is versioned and uses GCS object-level locking to prevent concurrent writers.

4. **Post-Apply Hooks**
   * Cloud Function **`notify-org-apply`** posts a summary (diff link, outputs) to **`#audit-log`** Slack and emits a Change Event to Cloud Deploy for SLO dashboards.
   * If drift is detected on subsequent runs, CI fails and opens a **drift-alert** issue.

5. **Evidence & Retention**
   * Cloud Build logs, `org-plan.*`, and GitHub PR are retained **400 days**.
   * IAM Audit log entries (`google.cloud.audit`) type `SYSTEM_POLICY_CHANGED` retained **400 days**.

## 5. Secure Code Review Process

1. **Automated Detection** – GitHub Action runs Dependabot, trivy, custom linters; ≥High findings add `security-review-needed`.
2. **Manual Review by Tech Lead (AppSec-trained)** – Focus on auth, secrets, encryption, new deps, IAM, network rules.
3. **Approval** – SECURITY LGTM comment with summary; merge gated until present.
4. **Break-Glass Follow-up** – Retro-PRs require Tech-Lead security review within 24 h.

## 6. JIT / Break-Glass Controls

- **Platform** – Google Cloud **Privileged Access Manager (PAM)**; Cloud Function posts request & decision messages to `#audit-log` and stores in BigQuery (**400-day** retention).
- **TTL by lane** – 1️⃣ 30 min · 2️⃣ 60 min · 3️⃣ 30 min · 4️⃣ 30 min.
- **Dual approval** – Requestor + one peer; lanes 3-4 require two Tech Mgmt approvers.
- **Runbook** – `runbooks/pam-break-glass.md`.
- **Failsafe monitoring** – Alert if **u2i-failsafe@google.com** logs in.

## 7. Audit Artifacts & Retention

| Control | Evidence | Retention |
|---------|----------|-----------|
| Code & security reviews | GitHub PRs, reviews, CI checks | **400 days** |
| Deploy approvals | Cloud Deploy release history | **400 days** |
| JIT/PAM grants | IAM logs + PAM grant export | **400 days** |
| **Project bootstrap** | Cloud Build logs + Terraform state + repo-creation PRs | **400 days** |
| SAST/SCA reports | GitHub Action artifacts | 90 days |
| Failsafe account usage | IAM login log + Safe access record | **400 days** |

## 8. Policy Maintenance

- *Owner*: Head of Engineering & Security Lead.
- *Review cadence*: Semi-annual **or** after any SEV-1 involving break-glass **or** material change to GCP PAM/failsafe or bootstrap workflow.
- Changes tracked via PRs to this doc in `compliance/policies` repo.

## 9. Glossary

- **Lane** – Category of change with its own approval flow.
- **TTL** – Time-to-live for JIT role before automatic revocation.
- **JIT** – Just-In-Time privilege elevation via GCP PAM.
- **Retro-PR** – Pull Request created post-incident to codify manual changes.
- **SECURITY LGTM** – GitHub comment by Tech Lead affirming secure review.
- **Failsafe Account** – Last-resort privileged Google account.
- **Project-Factory** – Terraform modules and workflow automating org-prep, project creation, repo bootstrap, and CI hooks.

---

**Last approved**: 24 June 2025  
**Next review due**: 24 December 2025