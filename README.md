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
   Create a storage account to host the blob containers. Storage account names must be globally unique *(Note: If `stckoassignmenttfs001` is already taken, simply change the `001` suffix to another random number)*:
   ```bash
   az storage account create --name stckoassignmenttfs001 --resource-group rg-terraform-state --location uksouth --sku Standard_LRS --encryption-services blob --allow-shared-key-access false --allow-blob-public-access false
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
   To avoid hardcoded secrets, configure OpenID Connect (OIDC) federation between the GitHub repository and the newly created Service Principal:
   - Go to the **Azure Portal** -> **Microsoft Entra ID** -> **App registrations** -> `github-actions-checkout-assessment` -> **Certificates & secrets** -> **Federated credentials**.
   - Click "Add credential" and select "GitHub Actions deploying Azure resources".
   - Enter your **GitHub Organization** and **Repository name**, Entity Type (e.g., `Branch`), and the corresponding branch name (e.g., `main`).
   - Fill in an identifying name and description, then click "Add".

9. **Assign Storage Permissions to Service Principal**
   GitHub Actions requires permission to read and write the Terraform state files in the `stckoassignmenttfs001` storage account.
   
   Execute the following Azure CLI commands to assign the **Storage Blob Data Contributor** role dynamically, scoped directly to the storage account:

   ```bash
   
   # Get the App ID of the Service Principal
   APP_ID=$(az ad app list --display-name "github-actions-checkout-assessment" --query "[0].appId" --output tsv)
   
   # Create the service principal and get the Object ID of the Service Principal
   SP_OBJECT_ID=$(az ad sp create --id $APP_ID --query "id" --output tsv)
   
   # Get the Resource ID of the Storage Account
   STORAGE_ACCOUNT_ID=$(az storage account show --name stckoassignmenttfs001 --resource-group rg-terraform-state --query "id" --output tsv)

   # Assign the Storage Blob Data Contributor role
   az role assignment create --assignee $SP_OBJECT_ID --role "Storage Blob Data Contributor" --scope $STORAGE_ACCOUNT_ID
   ```
   
   - *Note: The above operation to assign a Service Principal a role to blob storage can only be done using the Azure CLI, as this Service Principal cannot be found or added using the Azure Portal UI.*
   - *Note: Since GitHub Actions is only used for `terraform plan` in this project and never runs `terraform apply`, we are intentionally omitting subscription-level roles like `Contributor` and `User Access Administrator` to follow the Principle of Least Privilege.*
