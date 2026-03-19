# checkout-platform-assessment
Cloud Platform Engineering - Technical Assessment (Azure)

## Project Description
This project is for satisfying a technical assessment for a Cloud Platform Engineering position at Checkout.com. It contains the infrastructure-as-code (IaC) configuration and related documentation to deploy a robust, secure, and scalable cloud platform on Microsoft Azure.

For a detailed view of the system design, see the **[Architecture Diagram](docs/architecture.md)**.

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

---

## Estimated Azure Costs

The following is an estimate for running this infrastructure in the **UK South** region. Costs are based on standard retail pricing and assume a single environment (Dev or Prod) with minimal initial traffic.

| Component | SKU | Estimated Monthly Cost | Notes |
|---|---|---|---|
| **Application Gateway** | `WAF_v2` | ~£137.00 | Fixed cost for 1 capacity unit / instance. |
| **Function App** | `Premium EP1` | ~£127.00 | Minimum monthly cost for 1 instance. |
| **Private Endpoints** | 5x Endpoints | ~£27.00 | £7.30/month per endpoint (KV, Blob, Queue, Table, Func). |
| **Observability** | Log Analytics | ~£5.00 | Pay-as-you-go based on low ingestion volume. |
| **Other** | Storage/IP/KV | ~£6.00 | Nominal costs for storage and static public IPs. |
| **Total** | | **~£302.00 / month** | |

> [!NOTE]
> These are estimates. Actual costs will vary based on traffic, log ingestion volume, and regional availability.

---

## CI/CD Pipeline

This project uses **GitHub Actions** to automate Terraform validation, planning, and deployment. There are three workflows:

| Workflow | Trigger | What it does |
|---|---|---|
| [terraform-pr.yml](.github/workflows/terraform-pr.yml) | Pull request → `main` | Validates all modules, runs `terraform fmt` check, and runs `terraform plan` + **`terraform apply`** for **dev**. Posts the plan output as a PR comment. |
| [terraform-prod.yml](.github/workflows/terraform-prod.yml) | Merge to `main` | Runs `terraform plan` + **`terraform apply`** for **prod**. Uploads plan as a versioned artifact for audit trail. |
| [function-deploy.yml](.github/workflows/function-deploy.yml) | **(DISABLED)** Push to `main` (`src/function/**`) | Builds versioned function zip, uploads to private blob storage, updates `WEBSITE_RUN_FROM_PACKAGE`, restarts function runtime. |

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

Because the Terraform state storage account uses `network_default_action = Deny`, you must temporarily allowlist your public IP before running `terraform apply` locally. Key Vault and Function Package Storage have public access fully disabled — they are accessible only via private endpoints.

### Option A — Use the helper script (recommended)

```bash
# Defaults to dev environment
python scripts/local-tf-apply.py

# Or specify environment
python scripts/local-tf-apply.py --tf-dir environments/prod
```

The script detects your IP automatically, adds it to the TF state storage allowlist, runs `terraform apply -auto-approve`, and removes the IP in a `finally` block — even if apply fails.

### Option B — Manual steps

```bash
# 1. Get your public IP
curl https://api.ipify.org

# 2. Add your IP to TF state storage allowlist
az storage account network-rule add --account-name stckoassignmenttfs001 --ip-address <YOUR_IP>

# 3. Wait for propagation (~15s)
sleep 15

# 4. Run terraform apply
cd environments/dev
terraform apply

# 5. Remove your IP (always do this, even on failure)
az storage account network-rule remove --account-name stckoassignmenttfs001 --ip-address <YOUR_IP>
```

---

## Helper Scripts

The `scripts/` directory contains Python utility scripts for local development and testing:

| Script | Purpose | Usage |
|---|---|---|
| [`local-tf-apply.py`](scripts/local-tf-apply.py) | Runs `terraform apply` locally — automatically allowlists your IP on the TF state storage account, applies, and cleans up. | `python scripts/local-tf-apply.py [--tf-dir environments/prod]` |
| [`deploy-function.py`](scripts/deploy-function.py) | Builds a versioned function zip, uploads it to private blob storage, generates a SAS URL, updates the Function App's `WEBSITE_RUN_FROM_PACKAGE` setting, and restarts the runtime. | `python scripts/deploy-function.py [--env prod --storage-account ... --function-app ...]` |
| [`validate-all.py`](scripts/validate-all.py) | Runs `terraform fmt` and `terraform validate` across all modules and environments (no backend required). | `python scripts/validate-all.py` |
| [`test-appgw-mtls.py`](scripts/test-appgw-mtls.py) | Sends POST requests through the App Gateway with and without a client certificate to verify mTLS enforcement. | `python scripts/test-appgw-mtls.py` |

> [!TIP]
> All scripts are designed to be run from the **repository root**.

---

## Teardown

To destroy all provisioned infrastructure:

```bash
# 1. Add your IP to TF state storage (required for state access)
az storage account network-rule add --account-name stckoassignmenttfs001 --ip-address $(curl -s https://api.ipify.org)
sleep 15

# 2. Destroy dev environment
cd environments/dev
terraform destroy

# 3. Destroy prod environment (if provisioned)
cd ../prod
terraform destroy

# 4. Remove your IP from TF state storage
az storage account network-rule remove --account-name stckoassignmenttfs001 --ip-address $(curl -s https://api.ipify.org)

# 5. Delete the Terraform state storage (manual)
az storage account delete --name stckoassignmenttfs001 --resource-group rg-terraform-state --yes
az group delete --name rg-terraform-state --yes

# 6. Delete the Service Principal (optional)
az ad app delete --id $(az ad app list --display-name "github-actions-checkout-assessment" --query "[0].appId" -o tsv)
```

> [!WARNING]
> Key Vault has **purge protection enabled** — it will enter a soft-deleted state and cannot be permanently purged for 90 days. A new Key Vault with the same name cannot be created until the retention period expires or the vault is manually purged.

---

## Future Improvements

### Remove Public IP from DEV App Gateway

The DEV environment currently uses a public IP on the Application Gateway (`enable_public_access = true`) for ease of testing. In production, public access is disabled and the App Gateway listens only on its private frontend IP.

For DEV, the public IP should also be removed in the future in favour of alternatives such as:
- **VPN Gateway / Point-to-Site VPN** — connect developer machines directly to the VNet
- **Azure Bastion** — jump-box access to test from within the VNet
- **Self-hosted runners inside the VNet** — CI/CD tests can reach the private endpoint directly

### Self-Hosted Runners inside the VNet

All three CI/CD workflows currently use **dynamic IP injection** to access network-restricted Azure resources (Terraform state storage, Key Vault, function package storage). A runner IP is temporarily allowlisted at the start of each run and removed by an `if: always()` cleanup step.

The recommended long-term evolution is to replace GitHub-hosted runners with **self-hosted runners deployed inside the VNet** (e.g., on an Azure Container Instances group or a VM scale set). This would:
- Eliminate all dynamic IP management from workflows
- Remove public internet from the CI/CD path entirely
- Align the CI/CD environment with the same private network as the deployed resources
- Reduce the ~15s propagation wait added to every workflow run

Another possible improvement is to use Azure DevOps instead of GitHub Actions, but that is not a requirement for this project.

We can also look into using VPN to access the resources instead of dynamic IP injection.

See **ADR 6** in [`docs/project_ADR.md`](docs/project_ADR.md) for the full decision record.

---

## AI Usage & Critique

This project made extensive use of AI-assisted coding (via Gemini / Antigravity). While AI significantly accelerated development, the following areas required human intervention to correct or improve:

1. **NSG rules were not initially suggested.** The AI did not flag the absence of Network Security Groups on any of the three subnets (`snet-appgw`, `snet-private-endpoints`, `snet-func-outbound`) during the initial infrastructure design. This was identified manually during a security review and added later.

2. **Key Vault naming used random suffixes.** The AI suggested appending random characters to the Key Vault name on every deployment to work around Azure's soft-delete retention. This was changed to a **static suffix** to ensure idempotent, predictable deployments — randomly-named resources would accumulate soft-deleted vaults and make the infrastructure non-reproducible.

3. **Incomplete private endpoints for Storage Account.** The AI initially created only a **blob** private endpoint for the function package storage account, omitting the **queue** and **table** private endpoints that are also required by the Azure Functions runtime. These were added manually after observing connectivity issues.
