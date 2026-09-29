# Sandbox execution runbook

Run the three scripts independently in this order for a new environment:

```text
Bootstrap.ps1  →  Provisioning.ps1  →  Deployment.ps1
```

Bootstrap and Provisioning are optional for an environment whose required resources and permissions already exist. Deployment can use either the environment file or a ready manifest.

## 1. Install local prerequisites

Use PowerShell 7.4 or later and install the modules for the workflows you will run:

```powershell
$modules = @(
  'Az.Accounts','Az.Resources','Az.ManagedServiceIdentity','Az.Network',
  'Az.OperationalInsights','Az.ApplicationInsights','Az.KeyVault',
  'Az.Websites','Az.Sql','Az.Compute','Az.Storage','SqlServer'
)
Install-Module $modules -Scope CurrentUser -Repository PSGallery -Force -AllowClobber
```

The operator needs subscription/resource-group permissions to create the configured resources and role assignments. Provisioning SQL managed-identity users also requires the signed-in operator to be the configured Microsoft Entra administrator of the Azure SQL logical server. Worker deployment requires permission to list the deployment Storage account keys and invoke VM Run Command.

## 2. Prepare configuration

```powershell
Copy-Item ./config/sandbox.env.example ./config/sandbox.env
Copy-Item ./config/databases.example.json ./config/databases.json
```

In `sandbox.env`:

1. Set `TENANT_ID` and `SUBSCRIPTION_ID`.
2. Change `DATABASES_FILE` to `databases.json` and edit that file for every required database.
3. Set `WEB_OS` to `Linux` or `Windows`, and set the App Service runtime string in `WEB_RUNTIME` (for example, an App Service stack value supported by the selected OS).
4. Set `WORKER_OS`, `WORKER_EXECUTABLE`, and optional `WORKER_ARGUMENTS`.
5. For Linux, set `WORKER_SSH_PUBLIC_KEY_PATH`. For Windows, supply `-VmAdministratorCredential` when Provisioning creates the VM.
6. Set `SQL_PRODUCT=AzureSqlDatabase`, `SQL_ENTRA_ADMIN_DISPLAY_NAME`, and `SQL_ENTRA_ADMIN_OBJECT_ID`.
7. For public endpoint deployment, set `DEPLOYMENT_CLIENT_IPV4` to the deployment machine's public egress IPv4 with `/32`. The scripts never detect this address automatically. Use `DEPLOYMENT_NETWORK_MODE=Private` only from a machine that can reach the private endpoints.
8. Review every `Auto`, `Create`, or `Existing` mode. `Existing` requires its complete Azure resource ID. Globally unique service names might need explicit name overrides.

Do not store SQL passwords, tokens, Storage keys, or application secret values in the environment file. Web settings should contain ordinary values or Key Vault references.

Validate local parsing before Azure login:

```powershell
pwsh -NoProfile -Command @'
Import-Module ./scripts/modules/Common.psm1 -Force
Import-Module ./scripts/modules/Configuration.psm1 -Force
$config = Import-EnvironmentConfiguration ./config/sandbox.env
Test-EnvironmentConfiguration $config Provisioning
'@
```

## 3. Bootstrap

Preview provider, resource-group, and managed-identity intent:

```powershell
./scripts/Bootstrap.ps1 -ConfigPath ./config/sandbox.env -WhatIf
```

Apply Bootstrap:

```powershell
./scripts/Bootstrap.ps1 -ConfigPath ./config/sandbox.env
```

The successful command prints the exact path to:

```text
.artifacts/sandbox/<run-id>/bootstrap.json
```

Bootstrap registers only the required missing resource providers when `BOOTSTRAP_REGISTER_PROVIDERS=true`. It creates or reuses the resource group and the shared user-assigned managed identity. It does not create a subscription, service principal, or app registration.

## 4. Provision infrastructure

If a new Azure SQL server will be created, obtain its local administrator credential without writing it to disk:

```powershell
$sqlAdmin = Get-Credential -Message 'Azure SQL local administrator'
```

For a Windows worker VM being created:

```powershell
$vmAdmin = Get-Credential -Message 'Windows VM administrator'
```

Preview the ordered provisioning plan:

```powershell
./scripts/Provisioning.ps1 -ConfigPath ./config/sandbox.env -WhatIf
```

Apply it, optionally binding the run to a Bootstrap artifact:

```powershell
./scripts/Provisioning.ps1 `
  -ConfigPath ./config/sandbox.env `
  -BootstrapPath ./.artifacts/sandbox/<bootstrap-run-id>/bootstrap.json `
  -SqlAdministratorCredential $sqlAdmin `
  -VmAdministratorCredential $vmAdmin
```

Omit a credential when the corresponding existing resource is reused or the selected OS does not need it. A successful run writes:

```text
.artifacts/sandbox/<run-id>/deployment-manifest.json
```

Provisioning creates or resolves the VNet/subnets, monitoring resources, Key Vault, deployment Storage account, Azure SQL server/databases, App Service plan/app, worker NIC/VM, and shared identity. It grants the runtime identity Key Vault secret read, Storage blob read, monitoring publisher access, and SQL database roles. Temporary client `/32` rules are removed before the manifest is published.

To inventory an already complete environment without changing resources or permissions:

```powershell
./scripts/Provisioning.ps1 -ConfigPath ./config/sandbox.env -ReuseOnly
```

Every configured resource must already exist for `-ReuseOnly`.

## 5. Build local release artifacts

- Web: one ZIP whose root contains the App Service publish output.
- Worker: one ZIP whose root contains `WORKER_EXECUTABLE` at the configured relative path.
- Database: one `.sql` file, or a directory with alphabetically ordered common `.sql` files at its root and database-specific files under subdirectories named for each database `key`. Root scripts run against every database, followed by that database's keyed scripts.

Database scripts must be repeatable or maintain their own migration ledger. The deployment runner does not infer rollback SQL.

## 6. Deploy code

Deploy all application packages with an optional database migration:

```powershell
./scripts/Deployment.ps1 `
  -ManifestPath ./.artifacts/sandbox/<provision-run-id>/deployment-manifest.json `
  -Target All `
  -WebArtifactPath ./publish/web.zip `
  -WorkerArtifactPath ./publish/worker.zip `
  -DatabaseArtifactPath ./publish/sql
```

Deploy targets independently:

```powershell
./scripts/Deployment.ps1 -ConfigPath ./config/sandbox.env -Target Web -WebArtifactPath ./publish/web.zip
./scripts/Deployment.ps1 -ConfigPath ./config/sandbox.env -Target Worker -WorkerArtifactPath ./publish/worker.zip
./scripts/Deployment.ps1 -ConfigPath ./config/sandbox.env -Target Database -DatabaseArtifactPath ./publish/sql
```

`-Target All` requires Web and Worker packages. It executes database scripts first only when `-DatabaseArtifactPath` is supplied, then deploys Web and Worker. Use `-DatabaseCredential` only when SQL authentication is intentionally required; otherwise the signed-in Entra identity supplies an access token.

Worker deployment uploads the ZIP to the private `releases` container, invokes VM Run Command, downloads from the VM using its managed identity, installs/restarts the service, and removes the staged blob in `finally`.

A successful release writes:

```text
.artifacts/sandbox/<run-id>/release-report.json
```

The report contains artifact hashes and resource IDs, never credentials or Storage keys.

## 7. Authentication choices

Interactive login is the default and needs no deployment SPN:

```powershell
./scripts/Bootstrap.ps1 -ConfigPath ./config/sandbox.env -AuthMode Interactive
```

Other supported modes are `DeviceCode`, `ExistingContext`, `ServicePrincipalCertificate`, and `ManagedIdentity`. Certificate authentication requires `-AuthClientId` and `-CertificateThumbprint`. `-NonInteractive` rejects Interactive and DeviceCode modes. Each script establishes and verifies its own tenant/subscription context.

## 8. Recovery and reruns

- Read `.artifacts/sandbox/<run-id>/run-report.json` after a failure.
- Read `network-access.json` when a process was interrupted. Remove only entries whose `created` value is `true` and whose recorded rule name matches the run ID.
- Rerun Bootstrap or Provisioning after correcting the cause. Exact-name discovery reuses resources already created.
- Rerun an idempotent database migration only after checking its ledger/state.
- A worker release is versioned by package hash, so rerunning the same package replaces the service definition with the same release directory.

No script deletes infrastructure, changes subscription ownership, creates an app registration, opens SSH/RDP, or guesses a public IP address.
