# Azure deployment automation

The operator interface has exactly three independently invoked PowerShell scripts:

**Bootstrap → Provisioning → Deployment** is the logical order for a new environment. Each script can run in a fresh session without invoking the other scripts or requiring their output files.

The configured environment is **sandbox**, region **eastus**, application identifier **askey-swarms-sandbox**. Resource names follow `AEY-EU-SWARMS-SANDBOX-{TYPE}-01`, with service-specific adaptations. See [the complete naming map](docs/naming.md). The `EU` name token does not change the selected Azure region.

| Script | Responsibility | Input | Output |
| --- | --- | --- | --- |
| `Bootstrap.ps1` | Validate target subscription and prerequisites; register required providers; create/reuse the resource group and shared managed identity | Environment file | `bootstrap.json` |
| `Provisioning.ps1` | Create/reuse application resources, configure network access and identity permissions, verify prerequisites | Environment file; optional bootstrap artifact | `deployment-manifest.json` |
| `Deployment.ps1` | Resolve existing targets, deploy local packages and explicitly selected migrations; verify the release | Environment file OR deployment manifest, plus local packages | `release-report.json` |

**Status: implemented and locally validated.** No Azure resources have been changed from this repository session; live execution requires the tenant, subscription, application runtime, credentials, and packages described in the runbook.

## Folder structure

```text
config/                         Environment and database examples
scripts/
  Bootstrap.ps1                 First operator command
  Provisioning.ps1              Second operator command
  Deployment.ps1                Third operator command
  modules/                      Internal reusable PowerShell modules
    resources/                  Resource-specific modules
  guest/                        Linux and Windows worker installers
tests/
  unit/
  integration/
docs/                           Architecture, decisions and runbooks
.artifacts/                     Ignored generated run outputs
AGENTS.md                       Development guidelines
```

Validation, discovery, planning, network access, configuration, and verification are internal steps. Operators do not invoke a stage dispatcher or individual modules. No Bicep or ARM templates are used.

## Usage

Follow [the step-by-step sandbox runbook](docs/runbook.md) for local setup, input preparation, Bootstrap, Provisioning, package deployment, expected outputs, and troubleshooting. For a new environment, complete Bootstrap before Provisioning; a WhatIf preview does not create the required group or shared identity. Existing local environment files must explicitly include `SQL_AUTHENTICATION_MODE=Sql` to select SQL username/password authentication.

Copy [config/sandbox.env.example](config/sandbox.env.example) to `config/sandbox.env` and fill in the target environment, resource, runtime, SQL administrator, SSH key, and deployment IP settings.

```powershell
./scripts/Bootstrap.ps1 -ConfigPath ./config/sandbox.env

$sqlAdmin = Get-Credential -Message 'SQL administrator / provisioning check login'
./scripts/Provisioning.ps1 -ConfigPath ./config/sandbox.env -SqlAdministratorCredential $sqlAdmin

# Deploy directly to existing resources using configuration.
./scripts/Deployment.ps1 -ConfigPath ./config/sandbox.env -Target Web -WebArtifactPath ./publish/web.zip

# Alternatively, use a saved output manifest; no environment file is required.
./scripts/Deployment.ps1 -ManifestPath ./path/to/deployment-manifest.json -Target Web -WebArtifactPath ./publish/web.zip
```

Replace `./path/to/` with the actual reported output paths. Each script supports `-WhatIf` and `-OutputDirectory` (default `.artifacts`, relative to the caller's working directory).

`-BootstrapPath` is optional on Provisioning. Without it, the script resolves bootstrap prerequisites from configuration and live Azure state. Missing providers, group, or shared identity produce a precise prerequisite error; Provisioning does not silently invoke Bootstrap. Independent execution still requires the resources needed for the chosen operation.

For fully existing infrastructure, `Provisioning.ps1 -ReuseOnly` will validate existing resources/configuration and export a manifest without resource or access changes. Deployment can skip both other scripts when its targets already exist, using configuration or a saved manifest. Create/Auto in deployment input never authorizes resource creation.

Each script authenticates independently. **An existing deployment SPN is not required:** the default is interactive Azure PowerShell login with the operator's account and MFA. See [authentication](docs/authentication.md) for optional SPN/certificate and Azure-runner identity modes. The scripts do not create a custom app registration as a side effect of login.

The sandbox examples select Azure SQL Database with SQL username/password authentication (`SQL_AUTHENTICATION_MODE=Sql`). Entra SQL administrator fields are unnecessary in this mode. Provisioning takes `-SqlAdministratorCredential` for creation/readiness, and database releases take `-DatabaseCredential`; passwords stay out of configuration and manifests. Application runtime SQL credentials and grants remain application-specific; see the runbook.

The shared runtime managed identity is attached to web and worker and remains separate from operator authentication. Explicit deployment-client allowlist settings are handled internally with per-run cleanup. Deployment may manage only narrowly scoped client rules authorized by the selected configuration/manifest; it never provisions application resources or repairs runtime identity/database permissions.

## Further details

- [Environment and artifact handoff](docs/environment-to-deployment.md)
- [Bootstrap and deployment network access](docs/bootstrap-and-network-access.md)
- [Managed identity](docs/managed-identity.md)
- [Open decisions](docs/decisions.md)
- [Independent authentication and optional SPN](docs/authentication.md)
- [Operations](docs/operations.md)
- [Validated tool versions](docs/tool-versions.md)

The implementation targets PowerShell 7.4 or later. See the runbook for required modules and validation commands.
