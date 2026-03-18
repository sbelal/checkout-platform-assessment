Cloud Platform Engineering - Technical
Assessment (Azure)
Background
At Checkout.com, the Cloud Platform team manages multi-cloud infrastructure supporting
mission-critical payment services. We are currently expanding our Azure footprint, building
landing zones, and enabling product engineering teams to deploy global workloads. This
requires a strong understanding of Azure networking, Infrastructure as Code (IaC), and
enterprise security patterns.
This assessment evaluates your understanding of Terraform, Azure services, certificate
management, and operational best practices.
The Scenario
A product engineering team needs to deploy a new internal API in Azure that will be consumed
by other services within the virtual network. The API must:
● Only be accessible from within the VNet (no public internet exposure).
● Require mutual TLS (mTLS) for client authentication.
● Log all requests for audit purposes.
● Have basic health monitoring.
● Be deployed using standardised Infrastructure as Code.
Your task is to build a simplified version of this pattern.
Core Requirements (Essential)
1. Infrastructure (Terraform)
Create Terraform code to deploy:
Networking
● A Virtual Network (VNet) with at least two subnets.
● Network Security Groups (NSGs) with appropriate least-privilege rules.
● Private Endpoints for Azure services to ensure traffic remains on the private backbone.
Compute
● An Azure Function (any supported language) that:
○ Accepts POST requests with a JSON payload containing a message field.
○ Validates the input.
○ Returns a JSON response with the original message, a timestamp, and the
request ID.
○ Handles errors gracefully.
● Function App configured with VNet integration.
API Layer
● API Management (Developer or Consumption tier) OR an Azure Function with a Private
Endpoint.
● Configured for internal access only.
Certificate Management
● Use Terraform's tls provider to generate:
○ A self-signed Certificate Authority (CA).
○ A client certificate signed by your CA.
● Store certificates securely in Azure Key Vault.
● Configure mTLS on your API layer (APIM or Application Gateway) using the CA as the
truststore.
Note: Self-signed certificates are acceptable for this assessment; please do not purchase a
domain or commercial certificates.
2. Observability
● Application Insights connected to the Function App.
● Log Analytics Workspace for centralised logging.
● At least one Alert Rule (you choose the metric to monitor).
3. Supporting Infrastructure
● Storage Account for the Function App (with appropriate network restrictions).
● Key Vault for secure management of secrets and certificates.
4. Code Structure
Your Terraform should demonstrate:
● Logical file organisation and clear resource naming conventions.
● Use of variables and locals where appropriate.
● Consideration for how this would work with remote state in Azure (e.g., Blob Storage).
You do not need to implement this, but be prepared to discuss your approach.
5. CI/CD
Include a GitHub Actions workflow that:
● Validates Terraform formatting and syntax.
● Runs terraform plan.
● Uses OIDC for Azure authentication (please document how this would be configured).
6. Documentation
Provide a README.md containing:
● An architecture diagram.
● Setup and deployment instructions.
● Any assumptions you have made.
● Teardown instructions.
● AI Usage & Critique: If you used AI coding assistants (e.g., Copilot, ChatGPT, Claude),
please list the prompts used and provide a brief technical critique of the output (e.g., did
the AI suggest any insecure patterns or non-standard Azure configurations?).
Stretch Goals (Optional)
Choose one or more based on your interests:
● Implement a reusable Terraform module structure.
● Add an Application Gateway to handle the ingress.
● Configure diagnostic settings to stream all resource logs to Log Analytics.
● Implement Managed Identity for all service-to-service communication.
● Add Terraform tests using terraform test or Terratest.
● Demonstrate environment separation (Dev/Prod) using Terraform workspaces or a
directory-based structure.
Submission
1. Push your code to a public GitHub repository.
2. Ensure the README.md contains all setup instructions.
3. Include estimated Azure costs for running this infrastructure.
4. Be prepared to discuss your implementation choices in detail during the technical
interview.
Time Expectation
● Core requirements: 2-3 hours.
● Stretch goals: Additional 1-2 hours (optional).
We value quality of thought over absolute completeness. If you run out of time, please
document what you would have implemented next.
Practical Notes
● Use Azure Free Tier or free credits where possible.
● Include teardown instructions (terraform destroy is fine, but note any manual steps
required).
● If you make assumptions about requirements, please document them clearly.
Questions? If anything is unclear, please email [hiring contact]. Asking clarifying questions is
highly encouraged and reflects the collaborative culture of the Cloud Platform team.