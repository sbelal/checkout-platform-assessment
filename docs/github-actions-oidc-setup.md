# GitHub Actions OIDC Setup for Azure

This guide covers the one-time setup required to allow the GitHub Actions workflows to authenticate with Azure using **OIDC (Workload Identity Federation)** — no client secrets stored in GitHub. It assumes the Service Principal `github-actions-checkout-assessment` has already been created as described in the [README](../README.md).

## Why OIDC?

- ✅ No long-lived credentials in GitHub Secrets
- ✅ Short-lived tokens issued per workflow run
- ✅ Compliant with zero-trust / least-privilege principles

---

## Prerequisites

- The **`github-actions-checkout-assessment`** Service Principal (created in README step 7)
- Owner or equivalent permissions on the Azure subscription
- Admin access to the GitHub repository

---

## Step 1 — Add GitHub Secrets

In your GitHub repository go to: **Settings → Secrets and variables → Actions → New repository secret**

Add these three secrets:

| Secret Name              | Value                                        |
|--------------------------|----------------------------------------------|
| `AZURE_CLIENT_ID`        | The App (Client) ID of your Service Principal |
| `AZURE_TENANT_ID`        | Your Azure Active Directory Tenant ID         |
| `AZURE_SUBSCRIPTION_ID`  | Your Azure Subscription ID                   |

> ⚠️ Do **not** add `AZURE_CLIENT_SECRET` — OIDC does not use it.

---

## Step 2 — Add Federated Credentials to the Service Principal

You need two federated credentials: one for PR workflows and one for pushes to `main`.

### Option A — Azure Portal

1. Go to **Azure Active Directory → App registrations → `github-actions-checkout-assessment`**
2. Click **Certificates & secrets → Federated credentials → Add credential**
3. Choose **GitHub Actions deploying Azure resources**
4. Fill in:

| Field | PR Credential | Main Credential |
|-------|--------------|-----------------|
| Organisation | `YOUR_GITHUB_ORG` | `YOUR_GITHUB_ORG` |
| Repository | `YOUR_REPO_NAME` | `YOUR_REPO_NAME` |
| Entity type | **Pull request** | **Branch** |
| Branch name | *(n/a for PR)* | `main` |
| Name | `gh-actions-pr` | `gh-actions-main` |

### Option B — Azure CLI

Replace `YOUR_ORG` and `YOUR_REPO` with your values.

**PR credential:**
```bash
SP_OBJECT_ID=$(az ad sp show --display-name "github-actions-checkout-assessment" --query id -o tsv)
az ad app federated-credential create \
  --id $SP_OBJECT_ID \
  --parameters '{
    "name": "gh-actions-pr",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:YOUR_ORG/YOUR_REPO:pull_request",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

**Main branch credential:**
```bash
SP_OBJECT_ID=$(az ad sp show --display-name "github-actions-checkout-assessment" --query id -o tsv)
az ad app federated-credential create \
  --id $SP_OBJECT_ID \
  --parameters '{
    "name": "gh-actions-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

---

## Step 3 — Verify SP Permissions

The Service Principal needs the following Azure RBAC assignments:

| Scope | Role | Purpose |
|-------|------|---------|
| Subscription | `Contributor` | Create/manage infrastructure resources (assign to `github-actions-checkout-assessment`) |
| Terraform state Storage Account (`stckoassignmenttfs001`) | `Storage Blob Data Contributor` | Read/write Terraform state files |

To check:
```bash
az role assignment list --assignee $(az ad sp show --display-name "github-actions-checkout-assessment" --query id -o tsv) --all -o table
```

---

## Step 4 — Set Up GitHub Environments (Recommended)

The workflows use GitHub **Environments** (`dev` and `prod`) which allows you to add:
- **Protection rules** (e.g., require manual approval before prod plan runs)
- **Environment-specific secrets** if needed in future

Go to: **Settings → Environments → New environment**

Create `dev` and `prod` environments. For `prod`, consider adding a **required reviewer** protection rule.

---

## Verification

Once set up, open a PR targeting `main`. The `Terraform — PR Validation (Dev)` check should appear and go green. After merge, the `Terraform — Plan Prod (Post-Merge)` workflow should run automatically on the **Actions** tab.
