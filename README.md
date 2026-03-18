# checkout-platform-assessment
Cloud Platform Engineering - Technical Assessment (Azure)

## Project Description
This project is for satisfying a technical assessment for a Cloud Platform Engineering position at Checkout.com. It contains the infrastructure-as-code (IaC) configuration and related documentation to deploy a robust, secure, and scalable cloud platform on Microsoft Azure.

## Prerequisites
Before you begin, ensure you have the following tools installed and configured:
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (Logged in using `az login`)
- [Terraform](https://developer.hashicorp.com/terraform/downloads) (latest recommended version)
- [Git](https://git-scm.com/downloads)

## Manual Setup Steps (Initialization)

**Assumption:** For the purposes of this project and the steps below, we assume the primary deployment region is `uksouth`.

Before Terraform can calculate and apply the infrastructure changes via GitHub Actions, and to securely manage our Terraform state remotely without hardcoded secrets, the following manual steps must be carried out. **(DO NOT IMPLEMENT THESE STEPS IN CODE, they are executed via Azure CLI or Portal manually)**.

1. **Login to Azure CLI**
   Authenticate your local terminal session with Azure to manage your resources:
   ```bash
   az login
   ```

2. **Select Active Subscription**
   Ensure you are working within the correct Azure subscription. List your subscriptions and set the active one:
   ```bash
   # List all subscriptions to find your SubscriptionId
   az account list --output table

   # Set the active subscription
   az account set --subscription <your-subscription-id>
   ```

3. **Register Storage Provider** (Mandatory for new subscriptions)
   Sometimes new subscriptions don't have the Storage provider registered. Run this to ensure it's available:
   ```bash
   # Register the provider
   az provider register --namespace Microsoft.Storage

   # Check registration status (wait until it says 'Registered')
   az provider show --namespace Microsoft.Storage --query "registrationState"
   ```

4. **Create the Terraform State Resource Group**
   Create a resource group dedicated to holding the Terraform remote state storage:
   ```bash
   az group create --name rg-terraform-state --location uksouth
   ```

5. **Create the Storage Account**
   Create a storage account to host the blob containers. Storage account names must be globally unique *(Note: If `stckoassignmenttfs001` is already taken, simply change the `001` suffix to another random number)*.

   Public network access is disabled from the outset — all access requires Entra ID authentication and IP allowlisting (see **Manual `terraform apply`** section below):
   ```bash
   az storage account create \
     --name stckoassignmenttfs001 \
     --resource-group rg-terraform-state \
     --location uksouth \
     --sku Standard_LRS \
     --encryption-services blob \
     --allow-shared-key-access false \
     --allow-blob-public-access false \
     --public-network-access Disabled
   ```

6. **Create Blob Containers for Terraform State**
   Create two private blob containers within the storage account to isolate the state for the `dev` and `prod` environments securely. Ensure the containers are private and cannot be accessed from the internet.
   *(See `docs/project_ADR.md` for the architectural decision regarding this environment isolation).*
   ```bash
   # Create container for DEV state (Private)
   az storage container create --name tfstate-dev --account-name stckoassignmenttfs001 --public-access off --auth-mode login

   # Create container for PROD state (Private)
   az storage container create --name tfstate-prod --account-name stckoassignmenttfs001 --public-access off --auth-mode login
   ```

7. **Create a Microsoft Entra ID App Registration / Service Principal**
   Create a Service Principal that GitHub Actions will use to authenticate with Azure and deploy the infrastructure seamlessly.
   ```bash
   az ad app create --display-name "github-actions-checkout-assessment"
   ```

8. **Link GitHub Repo with Azure AD via OIDC**
   To avoid hardcoded secrets, configure OpenID Connect (OIDC) Workload Identity Federation between the GitHub repository and the newly created Service Principal. **Two federated credentials are required** — one for PR workflows and one for pushes to `main`.

   For full step-by-step instructions (Portal and CLI), see: **[`docs/github-actions-oidc-setup.md`](docs/github-actions-oidc-setup.md)**.

9. **Assign Permissions to Service Principal**
   GitHub Actions runs `terraform plan`, `terraform apply`, and the function deploy workflow. The Service Principal requires multiple role assignments.

   ```bash
   # Get the App ID and Object ID of the Service Principal
   SUBSCRIPTION_ID=$(az account show --query id --output tsv)
   APP_ID=$(az ad app list --display-name "github-actions-checkout-assessment" --query "[0].appId" --output tsv)
   SP_OBJECT_ID=$(az ad sp create --id $APP_ID --query "id" --output tsv)

   # ── Subscription-level: deploy infrastructure ────────────────────────────
   az role assignment create \
     --assignee $SP_OBJECT_ID \
     --role "Contributor" \
     --scope "/subscriptions/$SUBSCRIPTION_ID"

   # Required to assign RBAC roles to managed identities during terraform apply
   az role assignment create \
     --assignee $SP_OBJECT_ID \
     --role "User Access Administrator" \
     --scope "/subscriptions/$SUBSCRIPTION_ID"

   # ── TF state storage account ─────────────────────────────────────────────
   TF_STATE_SA_ID=$(az storage account show --name stckoassignmenttfs001 --resource-group rg-terraform-state --query "id" --output tsv)
   az role assignment create \
     --assignee $SP_OBJECT_ID \
     --role "Storage Blob Data Contributor" \
     --scope $TF_STATE_SA_ID

   # ── Key Vault (created by terraform apply — run after first apply) ───────
   KV_ID=$(az keyvault show --name kv-checkout-dev-001 --query id --output tsv)
   az role assignment create \
     --assignee $SP_OBJECT_ID \
     --role "Key Vault Secrets Officer" \
     --scope $KV_ID
   ```

   - *Note: Role assignments can only be done via Azure CLI — the Service Principal cannot be found or assigned via the Azure Portal UI.*
   - *Note: The Key Vault role assignment must be run **after** the first `terraform apply` creates the Key Vault. Re-run the last block once the Key Vault exists.*
   - *Note: `User Access Administrator` is required because Terraform creates RBAC assignments for the Function App and App Gateway managed identities during apply.*

10. **Assign Storage Permissions to Your User Account (For Local Execution)**
    If you intend to run `terraform init` and `terraform plan` locally from your development machine, your Azure CLI user also needs data-plane access to the storage account, as shared key access is explicitly disabled.
    
    Execute the following Azure CLI commands to assign the **Storage Blob Data Contributor** role to your currently signed-in user:

    ```bash
    # Get the Object ID of your currently signed-in user
    USER_ID=$(az ad signed-in-user show --query id --output tsv)

    # Get the Resource ID of the Storage Account (if not already set)
    STORAGE_ACCOUNT_ID=$(az storage account show --name stckoassignmenttfs001 --resource-group rg-terraform-state --query "id" --output tsv)

    # Assign the Storage Blob Data Contributor role
    az role assignment create --assignee $USER_ID --role "Storage Blob Data Contributor" --scope $STORAGE_ACCOUNT_ID
    ```
    
    - *Note: Azure role assignments may take a few minutes to fully propagate.*

## CI/CD Pipeline

This project uses **GitHub Actions** to automate Terraform validation, planning, and deployment. There are three workflows:

| Workflow | Trigger | What it does |
|---|---|---|
| [terraform-pr.yml](.github/workflows/terraform-pr.yml) | Pull request → `main` | Validates all modules, runs `terraform fmt` check, and runs `terraform plan` + **`terraform apply`** for **dev**. Posts the plan output as a PR comment. |
| [terraform-prod.yml](.github/workflows/terraform-prod.yml) | Merge to `main` | Runs `terraform plan` + **`terraform apply`** for **prod**. Uploads plan as a versioned artifact for audit trail. |
| [function-deploy.yml](.github/workflows/function-deploy.yml) | Push to `main` (`src/function/**`) | Builds versioned function zip, uploads to private blob storage, updates `WEBSITE_RUN_FROM_PACKAGE`, restarts function runtime. |

All workflows use **dynamic IP injection**: the runner's current public IP is temporarily added to the allowlists for the Terraform state storage, Key Vault, and function package storage — and removed via an `if: always()` cleanup step at the end.

### Setting Up the Pipeline

**Step 1 — OIDC setup** (one-time): configure the Service Principal and federated credentials:

👉 **[`docs/github-actions-oidc-setup.md`](docs/github-actions-oidc-setup.md)**

This covers:
- GitHub Secrets to add (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`)
- Azure AD Federated Credentials (CLI + Portal instructions)
- GitHub Environments configuration for `dev` and `prod`

**Step 2 — GitHub Variables**: the workflows read resource names from GitHub Environment Variables (not secrets — these are not sensitive). Set them in **Settings → Environments → dev (and prod) → Variables**:

| Variable | Dev value | Prod value |
|---|---|---|
| `ENVIRONMENT` | `dev` | `prod` |
| `KEY_VAULT_NAME` | `kv-checkout-dev-001` | `kv-checkout-prod-001` |
| `FUNC_PKG_STORAGE_ACCOUNT` | `stckofuncpkgdev001` | `stckofuncpkgprod001` |

---

## Manual `terraform apply` (Local Development)

Because Key Vault, function package storage, and TF state storage all use `network_default_action = Deny`, you must temporarily allowlist your public IP before running `terraform apply` locally.

### Option A — Use the helper scripts (recommended)

**PowerShell:**
```powershell
.\scripts\local-tf-apply.ps1 `
    -TfStateSa  stckoassignmenttfs001 `
    -KeyVault   kv-checkout-dev-001 `
    -FuncPkgSa  stckofuncpkgdev001 `
    -TfDir      environments/dev
```

**Bash:**
```bash
./scripts/local-tf-apply.sh \
  --tf-state-sa stckoassignmenttfs001 \
  --key-vault   kv-checkout-dev-001 \
  --func-pkg-sa stckofuncpkgdev001 \
  --tf-dir      environments/dev
```

The scripts detect your IP automatically, add it to all three allowlists, run `terraform apply`, and remove the IP via `trap`/`finally` — even if apply fails.

### Option B — Manual steps

```powershell
# 1. Get your public IP
$IP = Invoke-RestMethod https://api.ipify.org

# 2. Add your IP to all allowlists (Note: KV and Func Pkg SA commands will error if they don't exist yet - you can ignore those errors on your first run)
az storage account network-rule add --account-name stckoassignmenttfs001 --ip-address $IP
az keyvault network-rule add        --name kv-checkout-dev-001           --ip-address $IP 2>$null
az storage account network-rule add --account-name stckofuncpkgdev001       --ip-address $IP 2>$null

# 3. Wait for propagation
Start-Sleep -Seconds 15

# 4. Set your IP in dev.auto.tfvars
Copy-Item environments/dev/dev.auto.tfvars.example environments/dev/dev.auto.tfvars
# Edit the file: allowed_ips = ["$IP/32"]

# 5. Run terraform apply
Set-Location environments/dev
terraform apply

# 6. Remove your IP (always do this, even on failure)
az storage account network-rule remove --account-name stckoassignmenttfs001 --ip-address $IP
az keyvault network-rule remove        --name kv-checkout-dev-001           --ip-address $IP
az storage account network-rule remove --account-name stckofuncpkgdev001       --ip-address $IP
```

> 📝 `dev.auto.tfvars` is gitignored — it will never be committed. Use `dev.auto.tfvars.example` as the template.

---

## Future Improvements

### Self-Hosted Runners inside the VNet

All three CI/CD workflows currently use **dynamic IP injection** to access network-restricted Azure resources (Terraform state storage, Key Vault, function package storage). A runner IP is temporarily allowlisted at the start of each run and removed by an `if: always()` cleanup step.

The recommended long-term evolution is to replace GitHub-hosted runners with **self-hosted runners deployed inside the VNet** (e.g., on an Azure Container Instances group or a VM scale set). This would:
- Eliminate all dynamic IP management from workflows
- Remove public internet from the CI/CD path entirely
- Align the CI/CD environment with the same private network as the deployed resources
- Reduce the ~15s propagation wait added to every workflow run

Another possible improvement is to use Azure DevOps instead of GitHub Actions, but that is not a requirement for this project.

We can also look into using VPN to access the resources instead of dynamic IP injection

See **ADR 6** in [`docs/project_ADR.md`](docs/project_ADR.md) for the full decision record.
