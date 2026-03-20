# Architecture Overview

## High-Level Architecture

The Checkout Platform runs on Azure, deployed via Terraform with a modular structure supporting multiple environments (dev, prod).

```mermaid
flowchart TB
    subgraph Internet
        Client["Client (HTTPS + mTLS)"]
    end

    subgraph RG["Resource Group (rg-checkout-assessment-{env})"]
        subgraph VNet["Virtual Network (vnet-checkout-assessment-{env})"]
            subgraph snet_appgw["snet-appgw + NSG"]
                AppGW["Application Gateway\n(WAF_v2 + mTLS)\nPublic IP (dev) / Private IP"]
            end

            subgraph snet_pe["snet-private-endpoints + NSG"]
                PE_Func["Private Endpoint\n(Function App)"]
                PE_KV["Private Endpoint\n(Key Vault)"]
                PE_Blob["Private Endpoint\n(Storage - Blob)"]
                PE_Queue["Private Endpoint\n(Storage - Queue)"]
                PE_Table["Private Endpoint\n(Storage - Table)"]
            end

            subgraph snet_func["snet-func-outbound + NSG"]
                VNetInt["Function App\nVNet Integration\n(Outbound)"]
            end
        end

        FuncApp["Azure Function App\n(Python 3.11, Linux)\nHTTPS Only, System MI"]
        KV["Azure Key Vault\n(RBAC, Purge Protected)\nPublic Access Disabled"]
        Storage["Storage Account\n(Function Packages)\nPublic Access Disabled"]
        CertMgmt["Certificate Management\n(TLS CA + Server Certs)"]

        subgraph Observability
            LAW["Log Analytics\nWorkspace"]
            AppInsights["Application\nInsights"]
            Alerts["Metric Alerts\n(HTTP 5xx)"]
        end
    end

    Client -- "HTTPS :443" --> AppGW
    AppGW -- "HTTPS :443\n(pick hostname)" --> PE_Func
    AppGW -- "Key Vault Access\n(TCP :443)" --> PE_KV
    PE_Func --> FuncApp
    FuncApp --> VNetInt
    VNetInt -- "Outbound via VNet" --> PE_Blob
    PE_KV --> KV
    PE_Blob --> Storage
    PE_Queue --> Storage
    PE_Table --> Storage
    CertMgmt -- "Stores certs" --> KV
    AppGW -. "Reads TLS certs\n(User Assigned MI)" .-> KV
    FuncApp -. "Managed Identity" .-> Storage

    AppGW -- "Diagnostic Logs" --> LAW
    FuncApp -- "Diagnostic Logs" --> LAW
    FuncApp -- "Telemetry" --> AppInsights
    KV -- "Audit Logs" --> LAW
    Storage -- "Metrics" --> LAW
    AppInsights --> LAW
    Alerts -. "Monitors" .-> FuncApp
```

## Network Architecture

All services communicate through **private endpoints** within the VNet. Public access is disabled on the Function App, Key Vault, and Storage Account. Each subnet has a **Network Security Group (NSG)** with least-privilege rules.

```mermaid
flowchart LR
    subgraph VNet["VNet Address Space"]
        subgraph S1["snet-appgw + NSG"]
            AGW["App Gateway\n+ Public IP (dev only)\n+ Private IP (listener)"]
        end
        subgraph S2["snet-private-endpoints + NSG"]
            PE1["PE: Function App\n(privatelink.azurewebsites.net)"]
            PE2["PE: Key Vault\n(privatelink.vaultcore.azure.net)"]
            PE3["PE: Storage Blob\n(privatelink.blob)"]
            PE4["PE: Storage Queue\n(privatelink.queue)"]
            PE5["PE: Storage Table\n(privatelink.table)"]
        end
        subgraph S3["snet-func-outbound + NSG\n(Delegated: Microsoft.Web/serverFarms)"]
            FO["Function App\nOutbound Integration"]
        end
    end

    AGW --> PE1
    AGW --> PE2
    FO --> PE3

    DNS1["Private DNS Zone\nazurewebsites.net"] -. "linked" .-> VNet
    DNS2["Private DNS Zone\nvaultcore.azure.net"] -. "linked" .-> VNet
    DNS3["Private DNS Zone\nblob.core.windows.net"] -. "linked" .-> VNet
    DNS4["Private DNS Zone\nqueue.core.windows.net"] -. "linked" .-> VNet
    DNS5["Private DNS Zone\ntable.core.windows.net"] -. "linked" .-> VNet
```

## CI/CD Pipeline Architecture

```mermaid
flowchart LR
    subgraph PR["Pull Request Workflow"]
        direction TB
        V["Validate Modules"] --> P["terraform plan (Dev)"]
        P --> Comment["Post Plan as PR Comment"]
    end

    subgraph Main["Post-Merge Workflow (Prod)"]
        direction TB
        PP["terraform plan (Prod)"] --> Upload["Upload Plan Artifact"]
    end

    subgraph FuncDeploy["Function Deploy Workflow"]
        direction TB
        Build["Build Python Package"] --> Blob["Upload to Blob Storage"]
        Blob --> SAS["Generate SAS URL"]
        SAS --> Update["Update Function App Setting"]
        Update --> Restart["Restart Function App"]
    end

    PR_Trigger["PR to main"] --> PR
    Merge_Trigger["Push to main\n(environments/** or modules/**)"] --> Main
    Func_Trigger["Push to main\n(src/function/**)"] --> FuncDeploy

    Note["ℹ️ terraform apply steps are<br/>currently disabled in both<br/>PR and Prod workflows"]
```

## Terraform Module Dependency Graph

```mermaid
flowchart TD
    Env["environments/{dev,prod}/main.tf"] --> Infra["module: infrastructure"]

    Infra --> VNet["module: vnet\n• VNet\n• 3 Subnets"]
    Infra --> KV["module: key_vault\n• Key Vault\n• Private Endpoint\n• Private DNS Zone\n• RBAC Roles"]
    Infra --> FS["module: function_storage\n• Storage Account\n• Private Endpoints (Blob, Queue, Table)\n• Private DNS Zones"]
    Infra --> Func["module: function\n• Service Plan\n• Linux Function App\n• Private Endpoint\n• Private DNS Zone\n• RBAC Roles"]
    Infra --> Cert["module: certificate_management\n• TLS CA Key/Cert\n• Server Key/Cert\n• Key Vault Secrets"]
    Infra --> AppGW["module: app_gateway\n• App Gateway (WAF_v2)\n• User Assigned Identity\n• Public IP\n• mTLS SSL Profile"]
    Infra --> Obs["module: observability\n• Log Analytics Workspace\n• Application Insights\n• Metric Alerts"]

    KV --> Cert
    Cert --> AppGW
    VNet --> KV
    VNet --> FS
    VNet --> Func
    VNet --> AppGW
    FS --> Func
    Func --> Obs
    Func --> AppGW
    KV --> AppGW
