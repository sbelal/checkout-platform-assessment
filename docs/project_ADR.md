# Architecture Decision Records (ADRs)

This document records the architectural decisions made for this project. In each ADR, we will discuss the alternatives considered, the pros and cons of each alternative, and the final decision.

## ADR 1: Terraform State Storage Isolation and Security

**Status:** Accepted
**Date:** 2026-03-18

### Context
We need to store the Terraform state for our infrastructure deployments. The infrastructure spans multiple environments (e.g., dev, prod). We must decide how to organize the Azure Blob Storage containers for storing the Terraform state files securely.

### Alternatives Considered
1. **Single Container for All Environments:** Store both `dev` and `prod` state files within the same Blob Storage container, using different state file names or workspace prefixes.
2. **Dedicated Containers per Environment (Dev and Prod):** Create separate Blob Storage containers for each environment (e.g., `tfstate-dev` and `tfstate-prod`) within the same storage account.

### Decision
We have decided to proceed with **Alternative 2: Dedicated Containers per Environment (Dev and Prod)**. We will create two separate Blob containers within our Terraform state storage account. Additionally, these containers will be explicitly configured as private, ensuring they cannot be accessed from the internet.

### Pros and Cons

#### Single Container
* **Pros:** 
  * Simpler initial setup (only one container to create).
* **Cons:** 
  * **Poor RBAC (Role-Based Access Control):** It is difficult to restrict access such that a developer or pipeline can only read/write state for `dev` but not `prod`. Standard Azure RBAC for data access is most easily applied at the container level.
  * **Blast Radius:** Accidental deletion, misconfiguration, or corruption of the backend configuration structure affects all environments simultaneously.

#### Dedicated Containers (Chosen)
* **Pros:**
  * **Better RBAC and Isolation:** We can securely apply specific role assignments at the container level. The CI/CD pipeline for DEV will only have permission to access the `dev` container, while the PROD pipeline will operate exclusively on the `prod` container. This enforces the Principle of Least Privilege.
  * **Security and Privacy:** Configuring them as private ensures sensitive state data (which inherently contains plain-text infrastructure secrets and sensitive configuration values) is completely blocked from public internet access.
* **Cons:** 
  * Slightly more initial management overhead (creating two containers and managing separate role assignments).

## ADR 2: Centralized Remote Terraform Backend (Azure Blob Storage)

**Status:** Accepted
**Date:** 2026-03-18

### Context
We must decide how to persist the Terraform state for our infrastructure deployments. State can be managed locally on the machine executing Terraform or remotely in a centralized backend.

### Alternatives Considered
1. **Local State:** Storing the `.tfstate` file directly on the machine executing Terraform or in the source control repository.
2. **Remote Backend (Azure Blob Storage):** Storing the state remotely in a centralized Azure Storage Account container.

### Decision
We have decided to proceed with **Alternative 2: Remote Backend (Azure Blob Storage)**. This setup directly mirrors real-world production practices where state must be securely centralized.

### Pros and Cons

#### Local State
* **Pros:** 
  * Zero setup cost and easy for a single developer testing locally.
* **Cons:** 
  * **Conflicts and Out-of-Sync State:** If a developer runs `terraform plan` or `apply` locally while a CI/CD pipeline (e.g., GitHub Actions) runs it simultaneously or sequentially with a different local state, it will lead to conflicting changes, drift, and severe infrastructure corruption.
  * **No Locking Mechanism:** Concurrent execution across different machines can natively overwrite the state because there is no robust lock.

#### Remote Backend (Azure Blob Storage) (Chosen)
* **Pros:**
  * **Single Source of Truth:** Both local developer machines and CI/CD pipelines use the exact same state file, completely eliminating conflicts.
  * **Robust State Locking:** Azure Storage natively supports blob lease locking. This prevents concurrent Terraform runs from modifying the state simultaneously, avoiding corruption entirely.
* **Cons:** 
  * Requires initial manual provisioning of the Storage Account before Terraform can be fully utilized (which we have documented as a prerequisite in the README).

## ADR 3: Storage Account Network and Authentication Security

**Status:** Accepted
**Date:** 2026-03-18

### Context
We must decide how to secure access to the Terraform state storage account. This involves both authentication (how users/services prove who they are) and network access (from where they can connect).

### Alternatives Considered
1. **Shared Access Keys and Full Public Access:** Relying on standard Azure Storage Account keys for authentication and leaving all network traffic open, including unauthenticated public blob access.
2. **Entra ID Authentication + Disabled Public Blob Access + Open Public Network Access:** Disabling storage account keys entirely in favor of Entra ID (Azure AD) RBAC, disabling anonymous public blob access, but allowing connections from the public internet (since GitHub Actions runners and local developers operate over the internet).
3. **Strict Network Isolation (Private Endpoints / IP Whitelisting):** Using Entra ID for authentication but strictly restricting network traffic via firewall rules (e.g., only allowing specific developer IPs or using a self-hosted CI/CD runner within a VNet).

### Decision
We have decided to proceed with **Alternative 2: Entra ID Authentication + Disabled Public Blob Access + Open Public Network Access**. 

### Pros and Cons

#### Shared Access Keys and Full Public Access
* **Pros:** Simplest to configure.
* **Cons:** Unacceptable security risk. Shared keys provide over-privileged access and if leaked, compromise the entire storage account. Anonymous blob access risks exposing the `.tfstate` file (which contains plain-text infrastructure secrets and sensitive data).

#### Strict Network Isolation
* **Pros:** Maximum security. Traffic stays entirely within private boundaries or strict IP ranges.
* **Cons:** Introduces significant operational complexity. GitHub-hosted Actions runners have dynamic, unpredictable IP addresses, which would necessitate migrating to expensive self-hosted runners within a Virtual Network. Developer IP addresses are also dynamic and difficult to manage.

#### Entra ID + Disabled Public Blob + Open Network Access (Chosen)
* **Pros:**
  * **Strong Authentication:** By disabling Shared Key Access (`--allow-shared-key-access false`), we force all interactions to authenticate exclusively via Microsoft Entra ID. We can tightly control permissions using least-privilege Azure RBAC.
  * **Limited CI/CD Permissions:** Since GitHub Actions only performs `terraform plan` in this project, it does not require subscription-level roles like `Contributor` or `User Access Administrator`. We only assign the **Storage Blob Data Contributor** role scoped to the Terraform state storage account, adhering to the Principle of Least Privilege.
  * **Data Privacy:** Disabling public blob access (`--allow-blob-public-access false`) ensures that no unauthenticated requests can read the `.tfstate` files.
  * **Operational Flexibility:** By not blocking public network traffic entirely, local developers and GitHub-hosted Actions runners can seamlessly run Terraform without complex VPNs or self-hosted runner infrastructure. The risk of open network access is completely mitigated by the strict Entra ID authentication requirement.
* **Cons:** 
  * Network traffic traverses the public internet, though this is thoroughly mitigated using mandatory TLS 1.2 encryption.
