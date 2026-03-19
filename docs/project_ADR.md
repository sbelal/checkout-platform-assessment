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

> **Amendment (2026-03-18):** With dynamic IP injection now in place across all CI/CD workflows, the rationale for open public network access no longer applies. The TF state storage account is updated to `network_default_action = Deny`. The runner's IP is added at the start of each workflow run and removed via an `if: always()` step, providing the same operational flexibility with true network-level isolation.

---

## ADR 4: Function Code Deployment via Private Blob Container (WEBSITE_RUN_FROM_PACKAGE)

**Status:** Accepted
**Date:** 2026-03-18

### Context
The Azure Function App is deployed with `public_network_access_enabled = false` — it is only reachable within the VNet via its private endpoint. This means the standard Kudu/SCM endpoint (`https://<app>.scm.azurewebsites.net`) used by `az functionapp deployment source config-zip` is also unreachable from the public internet or GitHub-hosted CI/CD runners. We need an alternative mechanism to deploy function code that does not rely on Kudu.

### Alternatives Considered
1. **Kudu zip push deployment** — Standard approach using the SCM endpoint.
2. **WEBSITE_RUN_FROM_PACKAGE from a private storage blob** — Upload a versioned zip to a private Azure Blob container; the Function runtime mounts it directly using a managed identity or SAS URL.
3. **Container image deployment** — Package the function as a Docker image and deploy from Azure Container Registry.

### Decision
We have decided to proceed with **Alternative 2: WEBSITE_RUN_FROM_PACKAGE from a private blob container**.

### Pros and Cons

#### Kudu Zip Push (Rejected)
* **Cons:** Requires the SCM endpoint to be network-reachable. Incompatible with a fully private function app.

#### WEBSITE_RUN_FROM_PACKAGE (Chosen)
* **Pros:**
  * The Function runtime downloads the package directly from blob storage — no Kudu/SCM access required from the deployer.
  * Each deployment is a versioned, immutable artifact in blob storage, enabling instant rollback by updating the app setting to a previous package URL.
  * A dedicated storage account with its own private endpoint keeps function deployment packages isolated from the Terraform state storage.
  * Fully compatible with managed identity authentication — no shared keys.
* **Cons:**
  * Requires a separate storage account and blob container for packages.
  * Deployment involves an extra step: upload zip → update `WEBSITE_RUN_FROM_PACKAGE` → restart runtime.

#### Container Image (Not chosen)
* **Cons:** Requires Azure Container Registry, more operational overhead, and is overkill for a single lightweight Python function.

---

## ADR 5: Application Gateway vs APIM vs Direct Private Link

**Status:** Accepted
**Date:** 2026-03-18

### Context
The Azure Function is private (VNet-only). We need an entry point for clients to invoke the function via mTLS from within the same private network. We evaluated three options for this role.

### Alternatives Considered
1. **Azure API Management (APIM)** — Full API gateway with payload transformation, developer portal, and subscription management.
2. **Direct Private Link / Private Endpoint** — Callers connect directly to the function's private endpoint with no intermediary.
3. **Azure Application Gateway (WAF_v2)** — Layer 7 load balancer with built-in WAF, SSL/TLS termination, and mTLS support.

### Decision
We have decided to proceed with **Alternative 3: Azure Application Gateway (WAF_v2)**.

### Pros and Cons

#### APIM (Not chosen)
* **Pros:** Rich API management — payload transformation, rate limiting, searchable developer catalog, OpenAPI import.
* **Cons:** We do not need payload transformation, subscription management, or a developer catalog in this project. APIM is significantly more expensive and complex. mTLS configuration in APIM is more involved.

#### Direct Private Link (Not chosen)
* **Cons:** No WAF protection. No SSL/mTLS termination at a single entry point. Each client must independently manage TLS directly to the function with no centralised certificate management.

#### Application Gateway WAF_v2 (Chosen)
* **Pros:**
  * **WAF:** OWASP rule sets protect the function from common web exploits (SQLi, XSS, etc.) without requiring changes to function code.
  * **mTLS termination:** Client certificate validation is handled centrally at the gateway, not in application code. Certificates are stored in Azure Key Vault and referenced by managed identity.
  * **Single entry point:** SSL certificate management, domain routing, and mTLS policy are all managed in one place.
  * **Internal frontend:** Configured with a private IP — no public internet exposure.
* **Cons:**
  * WAF_v2 SKU has a higher baseline cost than a simple private endpoint.

---

## ADR 6: Dynamic IP Injection vs Self-Hosted Runners for CI/CD Access to Private Resources

**Status:** Accepted
**Date:** 2026-03-18

### Context
All sensitive Azure resources use `network_default_action = Deny`. GitHub-hosted Actions runners are not Azure services and therefore not covered by the `AzureServices` network bypass. They require explicit IP allowlisting to access these resources during CI/CD runs.

### Alternatives Considered
1. **Dynamic IP injection** — Each workflow detects the runner's public IP, temporarily adds it to all allowlists, runs Terraform or deployment operations, then removes the IP via `if: always()`.
2. **Self-hosted runners inside the VNet** — Run CI/CD on a VM or container within the same VNet, giving runners native private network access.
3. **GitHub IP range pre-allowlisting** — Statically allowlist all GitHub Actions runner CIDRs (published at `api.github.com/meta`).

### Decision
We have decided to proceed with **Alternative 1: Dynamic IP injection** as the current approach, with **Alternative 2 (self-hosted runners)** identified as the recommended long-term target.

### Pros and Cons

#### Dynamic IP Injection (Chosen — current)
* **Pros:**
  * No additional infrastructure or cost — works with standard GitHub-hosted runners.
  * Cleanup step (`if: always()`) ensures the IP is removed even on failure, minimising exposure window.
  * Entra ID authentication is still required — IP allowlisting alone is insufficient to access any resource.
* **Cons:**
  * Brief window where a dynamic IP is allowlisted. Mitigated by mandatory Entra ID auth and immediate cleanup.
  * Adds ~15s latency per workflow run for network rule propagation.

#### Self-Hosted Runners in VNet (Recommended long-term)
* **Pros:** Zero public internet exposure on the CI/CD path. No IP management. Consistent private network access.
* **Cons:** Requires provisioning and maintaining runner infrastructure within the VNet. Higher operational overhead. Not justified at current project scale.

#### GitHub IP Range Pre-allowlisting (Rejected)
* **Cons:** GitHub publishes thousands of CIDRs that change frequently. Maintaining a static allowlist is impractical and creates a persistent, wide attack surface.
