# Architecture

All application resources and selected supporting dependencies belong to one resource group per environment. The public interface is exactly Bootstrap.ps1, Provisioning.ps1, and Deployment.ps1, invoked independently; the boundaries below are internal modules, not additional operator commands.

| Boundary | Resources or responsibility |
| --- | --- |
| Prerequisites / Bootstrap | Validate target context and prerequisites, register needed providers, resolve/create group and identity |
| ResourceGroup | Target group and owned tags |
| ManagedIdentity | Shared user-assigned identity for web and worker, in the same group |
| Network | VNet, shared NAT egress, worker subnet, delegated App Service integration subnet, and SQL service endpoints |
| NetworkAccess | Explicit deployment-client access to selected endpoints and owned-rule cleanup |
| Monitoring | Explicit Log Analytics workspace and Application Insights |
| KeyVault | Vault and scoped access |
| SqlServer / SqlDatabases | Azure SQL logical server and individual databases |
| AppService | App Service Plan, web application, shared identity, and VNet integration |
| DeploymentStorage | Private blob container used briefly to stage worker releases |
| WorkerVm | VM, NIC, disks, identity, selected runtime bootstrap |
| AccessAndConfiguration | Explicitly owned settings, permissions, database users |
| Releases | Independent web, worker, and database delivery |
| Verification | Application health, dependency access, worker behavior, telemetry |

PowerShell resource modules read state, compare owned configuration, and apply planned operations. The orchestrator follows dependencies: resource group → shared identity and network/foundational services → compute/databases → identity attachments and scoped access/configuration → compatible release sequence → verification.

See [managed identity design](managed-identity.md) for web/worker attachments, Key Vault permissions, per-database users/grants, Application Insights authentication, and separation from local deployment credentials.

The implementation supports `AzureSqlDatabase`; any different SQL product must be designed before use. Provisioning applies only the explicitly owned identity, runtime setting, role, SQL user, and network-integration changes to reused resources. Deployment.ps1 fails when infrastructure required by its selected target is missing.

This document describes the implemented system. Live Azure validation remains environment-specific.

[Bootstrap and deployment network access](bootstrap-and-network-access.md) precede data-plane configuration and local releases. A bootstrap report records setup results; the final deployment manifest is published only after prerequisites are verified. Runtime network routes remain separate from the deployment client's IP rules.

Each script authenticates independently through a shared internal Authentication module. Default interactive operator login needs no custom deployment SPN. Output artifacts are optional; direct configuration and live-state resolution support manually provisioned environments. See [authentication](authentication.md).
