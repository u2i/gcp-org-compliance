# Shared GKE Resources

This directory manages cross-project resources for tenant teams that they cannot manage themselves.

## Structure

```
3-shared-gke/
├── tenant-namespaces/
│   ├── webapp-team.tf    # WebApp team namespaces and permissions
│   └── other-team.tf     # Add more teams here
├── main.tf               # Providers and backend
├── variables.tf          # Common variables
└── outputs.tf            # Exported values
```

## What This Manages

For each tenant team:
- Kubernetes namespaces in shared GKE clusters
- Resource quotas and limits
- Network policies for namespace isolation
- RBAC roles and bindings
- Cross-project IAM (e.g., Cloud Deploy SA access to GKE projects)

## Adding a New Tenant

1. Create a new file in `tenant-namespaces/` named `<team-name>.tf`
2. Copy the structure from `webapp-team.tf` and adjust:
   - Local variables (project ID, team name)
   - Resource quotas based on team needs
   - Any specific RBAC requirements
3. Run `terraform plan` to verify
4. Apply changes

## Why This Exists

Tenant teams cannot grant permissions on resources outside their project. This includes:
- Creating namespaces in shared GKE clusters
- Granting their service accounts access to GKE projects
- Setting up cross-project networking or IAM

By managing these resources centrally, we maintain security while enabling tenant autonomy for their own resources.