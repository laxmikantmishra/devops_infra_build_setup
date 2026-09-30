# Sandbox execution runbook

This runbook starts from a local checkout and an Azure subscription. The selected database product is **Azure SQL Database with SQL username/password authentication**. Run the numbered steps in order for a new environment:

```text
Prepare configuration → Bootstrap → Provisioning → Prepare packages → Deployment
```

**If you have not run Bootstrap, start with steps 1–4 below.** Provisioning does not create its resource-group/shared-identity prerequisites or invoke Bootstrap automatically. Bootstrap can be skipped only when those prerequisites have already been verified for the same environment. Running only `Bootstrap.ps1 -WhatIf` does not complete Bootstrap.

**Fix for `SQL_ENTRA_ADMIN_DISPLAY_NAME and SQL_ENTRA_ADMIN_OBJECT_ID are required when Provisioning may create the SQL server`:** edit the actual file passed to `-ConfigPath`, not just the example, and ensure these entries occur exactly once:

```dotenv
SQL_PRODUCT=AzureSqlDatabase
SQL_AUTHENTICATION_MODE=Sql
SQL_ENTRA_ADMIN_DISPLAY_NAME=
SQL_ENTRA_ADMIN_OBJECT_ID=
```

Save the file. An older `.env` without the authentication-mode key defaults to Entra; blank Entra fields alone do not select SQL authentication. For JSON input, set `sql.authenticationMode` to `Sql`. This particular error is local configuration validation, not evidence of an Azure permission failure or missing Bootstrap. After fixing it, complete Bootstrap before first-time Provisioning. If the exact same error persists, use the local mode check in step 3 and confirm you are running the updated scripts from this checkout.

If Provisioning already failed, preserve your edited configuration and any run reports. Do not delete resources or overwrite your configuration with the examples. After successful Bootstrap, continue at step 5. A failure mentioning missing resource groups, identities, or providers is consistent with skipped Bootstrap; other errors need their own diagnosis (see step 9).

These are operator instructions, not evidence that Azure resources have been deployed or tested. Application runtimes, package build commands, runtime SQL settings, and credentials still require your actual values.

## 1. Open PowerShell in the repository

From your terminal, launch PowerShell 7:

```text
pwsh -NoProfile
```

Run every following `powershell` block **inside that PowerShell session**, not directly in zsh, bash, or Windows Command Prompt. Change to your checkout; the path below is this workspace's path:

```powershell
Set-Location '/Users/laxmikantmishra/Documents/devops_infra_build_setup'
$ErrorActionPreference = 'Stop'
$PSVersionTable.PSVersion
if ($PSVersionTable.PSVersion -lt [version]'7.4') {
    throw 'Use PowerShell 7.4 or later.'
}
if (-not (Test-Path ./scripts/Bootstrap.ps1)) {
    throw 'Change to the repository root before continuing.'
}
```

Use your actual checkout path on another machine. Keep the same session for the walkthrough so `$configPath`, credentials, and captured result variables remain available. The scripts themselves are independent: if you reopen PowerShell, reestablish the directory/variables and obtain credentials again. Do not save credentials to recover a session.

## 2. Install and check PowerShell modules

Install the tested module versions only if they are missing:

```powershell
$moduleVersions = [ordered]@{
    'Az.Accounts' = '5.5.3'
    'Az.Resources' = '10.2.1'
    'Az.ManagedServiceIdentity' = '2.0.0'
    'Az.Network' = '8.2.0'
    'Az.OperationalInsights' = '3.4.1'
    'Az.ApplicationInsights' = '3.0.0'
    'Az.KeyVault' = '6.6.1'
    'Az.Websites' = '4.1.0'
    'Az.Sql' = '7.1.0'
    'Az.Compute' = '11.9.0'
    'Az.Storage' = '9.7.2'
    'SqlServer' = '22.4.5.1'
}
foreach ($entry in $moduleVersions.GetEnumerator()) {
    $installed = @(Get-Module -ListAvailable -Name $entry.Key |
        Where-Object Version -EQ ([version]$entry.Value))
    if (-not $installed.Count) {
        Install-Module -Name $entry.Key -RequiredVersion $entry.Value -Scope CurrentUser -Repository PSGallery -AllowClobber -ErrorAction Stop
    }
    Import-Module -Name $entry.Key -RequiredVersion $entry.Value -ErrorAction Stop
}
Get-Module -Name @($moduleVersions.Keys) | Select-Object Name, Version
```

If another version is already loaded and import fails, reopen `pwsh -NoProfile` and repeat from step 1. The scripts do not themselves pin module loading; importing the tested versions in this session establishes the walkthrough's baseline. See [validated versions](tool-versions.md) and Microsoft's [Azure PowerShell installation guidance](https://learn.microsoft.com/powershell/azure/install-azure-powershell).

Your Azure operator account needs permissions for the operations you select:

| Operation | Access needed |
| --- | --- |
| Bootstrap | Read the subscription/providers; register missing providers if enabled; create the configured group and shared user-assigned identity if absent |
| Provisioning | Create/configure the selected resources and assign the scoped Key Vault, storage, and monitoring roles |
| SQL readiness and migrations | A SQL login able to connect to each database; migrations additionally require the SQL permissions needed by their scripts |
| Web release | Deploy to the selected App Service and reach its deployment endpoint |
| Worker release | List staging storage keys, upload/delete the staged blob, and invoke VM Run Command |
| Temporary public access | Manage only the explicitly enabled endpoint rules |

Resource creation permissions alone do not necessarily authorize role assignments. Provider registration requires subscription-level provider registration permission; see [Microsoft's provider registration documentation](https://learn.microsoft.com/azure/azure-resource-manager/management/resource-providers-and-types). The scripts do not grant the operator permissions. SQL mode does not require an Entra SQL administrator or SQL directory lookup permissions. Azure login and SQL login are separate.

## 3. Prepare configuration without overwriting existing work

Create local copies only when absent:

```powershell
if (-not (Test-Path ./config/sandbox.env)) {
    Copy-Item ./config/sandbox.env.example ./config/sandbox.env
}
if (-not (Test-Path ./config/databases.json)) {
    Copy-Item ./config/databases.example.json ./config/databases.json
}
$configPath = (Resolve-Path ./config/sandbox.env).Path
```

Edit `config/sandbox.env` in your editor. If you already have this file from an older version, add `SQL_AUTHENTICATION_MODE=Sql` exactly once; copying new example files does not update an existing file.

### Before Bootstrap

| Setting | What to enter |
| --- | --- |
| `TENANT_ID`, `SUBSCRIPTION_ID` | Your actual Azure directory/tenant and subscription IDs, available in Azure Portal → Subscriptions → selected subscription |
| `ENVIRONMENT`, `LOCATION` | Keep `sandbox` and `eastus` |
| `AUTH_MODE` | `Interactive` for operator login, or `DeviceCode` if your login environment requires it |
| `BOOTSTRAP_REGISTER_PROVIDERS` | `true` if your account may register missing providers; otherwise arrange registration with the subscription administrator first |
| `RESOURCE_GROUP_MODE`, `MANAGED_IDENTITY_MODE` | `Auto` for first-time creation or exact-name reuse. `Existing` requires the actual resource ID and will not create a missing resource |
| Names and other resource modes | Keep the example names unless using approved explicit overrides. Preserve actual names/IDs when reusing resources |
| `DATABASES_FILE` | `databases.json`, relative to `sandbox.env` |
| `SQL_PRODUCT`, `SQL_AUTHENTICATION_MODE` | `AzureSqlDatabase` and `Sql` |
| `SQL_ENTRA_ADMIN_DISPLAY_NAME`, `SQL_ENTRA_ADMIN_OBJECT_ID` | Leave blank in SQL mode |

Edit `config/databases.json`: each database needs a stable unique key, actual database name, mode, and approved edition/service objective. `Existing` databases require their full resource IDs. The two database names in the example are illustrative; replace them with the intended database list before provisioning. A new server can have new databases, and an existing server can have missing databases created independently.

Do not delete unrelated template keys to make a minimal Bootstrap file: the current loader and validator inspect the full resource configuration and referenced JSON files even for Bootstrap. Web/worker runtime values can remain blank until provisioning.

### Before Provisioning

| Setting | Required preparation |
| --- | --- |
| `WEB_OS`, `WEB_RUNTIME` | Choose the actual application OS and supported runtime. Linux uses an App Service stack string; the current Windows helper accepts `DOTNET|version`, `NODE|version`, or `PHP|version`. Do not guess a stack or switch the application OS |
| `APP_SERVICE_PLAN_SKU` | A tier compatible with the selected runtime/network integration; verify availability in eastus |
| `WEB_USE_STAGING_SLOT` | Keep `false`; this implementation rejects staging-slot deployments |
| `WORKER_OS`, `WORKER_RUNTIME` | Actual worker OS and runtime. The VM installer does not install arbitrary application runtimes |
| `WORKER_VM_SIZE`, `WORKER_IMAGE_*` | An approved VM size/image for the worker in eastus. Verify compatibility and quota before provisioning |
| `WORKER_SSH_PUBLIC_KEY_PATH` | For a new Linux VM, an existing OpenSSH public-key file; use an absolute path. Never enter the private-key path |
| `DEPLOYMENT_NETWORK_MODE` | Keep `PublicAllowList` for the example public-endpoint workflow. `Private` requires an already working private route, DNS and endpoints; selecting it does not create those prerequisites |
| `DEPLOYMENT_CLIENT_IPV4` | Your runner's confirmed public egress IPv4 with `/32`; obtain it from your network administrator or known egress configuration. Do not use the laptop's LAN address or an example address |
| `DEPLOYMENT_ACCESS_LIFETIME` | `Temporary` for per-run access cleanup |
| `DEPLOYMENT_ALLOW_*` | Explicitly authorize only required endpoints. Keep SQL enabled for SQL checks. Enable `DEPLOYMENT_ALLOW_APP_SERVICE_MAIN=true` if you authorize the runner's main-site health check access |
| `WEB_HEALTH_PATH` | The application's real health endpoint, not merely a page that always returns 200 |
| `WEB_APP_SETTINGS_FILE` | Optional JSON path relative to the env file, containing non-secret settings or Key Vault references |

For Linux, reuse an approved public key. If you need a new key and have OpenSSH installed, this command prompts for a new output filename and passphrase; do not overwrite an existing key:

```powershell
ssh-keygen -t ed25519 -C 'swarms-sandbox-worker'
```

Set `WORKER_SSH_PUBLIC_KEY_PATH` to the resulting `.pub` file's absolute path. For Windows, leave it blank; a VM administrator credential is supplied in step 5. No script opens SSH or RDP for you.

Do not put passwords, access tokens, storage keys, signed URLs, or secret connection strings in `.env`, JSON settings, package arguments, or artifacts. `SQL_RUNTIME_ROLES` only applies to optional Entra mode and is ignored in SQL mode.

Run the local Bootstrap configuration check (no Azure login or writes):

```powershell
Import-Module ./scripts/modules/Common.psm1 -Force
Import-Module ./scripts/modules/Configuration.psm1 -Force
$config = Import-EnvironmentConfiguration -Path $configPath
Test-EnvironmentConfiguration -Configuration $config -Operation Bootstrap
$config._sourcePath
Get-SqlAuthenticationMode -Configuration $config
if ((Get-SqlAuthenticationMode -Configuration $config) -ne 'Sql') {
    throw 'Edit this configuration file to select SQL_AUTHENTICATION_MODE=Sql before continuing.'
}
```

Expected results: `True`, the actual configuration path, and `Sql`. If the helper command is unavailable, the checkout is missing the SQL authentication update. Correct any error before proceeding. This validates local input; it does not prove permissions, resource availability, or connectivity.

## 4. Run Bootstrap first

Preview:

```powershell
./scripts/Bootstrap.ps1 -ConfigPath $configPath -WhatIf
```

Expect an Azure login prompt. Each script authenticates independently; no custom app registration/SPN or prior manual login is required. Preview performs reads but creates no resources and publishes no successful handoff artifact.

Apply and capture the actual result:

```powershell
$bootstrapResult = ./scripts/Bootstrap.ps1 -ConfigPath $configPath
if ($bootstrapResult.Status -ne 'Succeeded') {
    throw 'Bootstrap did not succeed. Stop and resolve its error before Provisioning.'
}
$bootstrapResult | Format-List Status, ArtifactPath, RunDirectory
$bootstrapReport = Get-Content -LiteralPath $bootstrapResult.ArtifactPath -Raw | ConvertFrom-Json
$bootstrapReport | Select-Object status, tenantId, subscriptionId, resourceGroup, managedIdentity
$bootstrapReport.providers | Format-Table namespace, finalState
```

Completion check: `Status=Succeeded`, report `status=Ready`, correct tenant/subscription, resolved resource group/shared identity, and provider final states `Registered`. The artifact is under `.artifacts/sandbox/<actual-run-id>/bootstrap.json`; use the returned path rather than typing `<run-id>`.

Provider registration can remain `Registering` after the initial request. The current implementation stops rather than polling until completion. Allow registration to finish, then rerun the **apply** block above. Bootstrap rechecks existing resources/providers. `BOOTSTRAP_REGISTER_PROVIDERS=false` cannot make missing registrations ready.

Do not proceed while Bootstrap fails. It creates/resolves only the group and shared identity and registers providers; it does not create the SQL server, application, or worker VM.

## 5. Validate and provision infrastructure

First fill all provisioning settings from step 3, then reload and validate the edited file:

```powershell
$config = Import-EnvironmentConfiguration -Path $configPath
Test-EnvironmentConfiguration -Configuration $config -Operation Provisioning
if ($config.application.worker.operatingSystem -eq 'Linux' -and $config.resources.workerVm.mode -ne 'Existing') {
    if (-not (Test-Path -LiteralPath $config.application.worker.sshPublicKeyPath -PathType Leaf)) {
        throw 'The configured worker public-key file does not exist.'
    }
}
```

Expect `True` and no key-path error. These checks are not a complete Azure deployment preflight; unresolved SKU, quota, image and runtime choices must be checked before the live run.

Preview the provisioning plan:

```powershell
./scripts/Provisioning.ps1 -ConfigPath $configPath -WhatIf
```

Provisioning preview checks login/provider readiness and returns a high-level ordered plan. It does not prove every target exists or that service-side creation will succeed. It requires no SQL password and publishes no manifest.

Obtain the SQL credential securely. For a **new SQL server**, this sets its initial SQL administrator. For an **existing SQL server**, supply a current SQL login that can connect to all configured databases; reuse does not reset its password:

```powershell
$sqlAdmin = Get-Credential -Message 'Azure SQL administrator / provisioning connectivity login'
$provisionParameters = @{
    ConfigPath = $configPath
    SqlAdministratorCredential = $sqlAdmin
}
```

**Windows worker only:** run this block if a Windows VM might need creation. Skip it for Linux or an existing VM:

```powershell
$vmAdmin = Get-Credential -Message 'New Windows worker VM administrator'
$provisionParameters.VmAdministratorCredential = $vmAdmin
```

Run provisioning with configuration alone; it discovers Bootstrap prerequisites from Azure, so there is no placeholder bootstrap path to edit:

```powershell
$provisionResult = ./scripts/Provisioning.ps1 @provisionParameters
if ($provisionResult.Status -ne 'Succeeded') {
    throw 'Provisioning did not succeed. Stop before Deployment.'
}
$provisionResult | Format-List Status, ArtifactPath, RunDirectory
$manifestPath = $provisionResult.ArtifactPath
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$manifest | Select-Object status, environment, tenantId, subscriptionId, sql
$manifest.verification.checks | Format-Table name, ready
```

Completion check: `Status=Succeeded`, manifest `status=Ready`, `sql.authenticationMode=Sql`, and all recorded readiness checks true. The artifact is `.artifacts/sandbox/<actual-run-id>/deployment-manifest.json`. Temporary access cleanup must succeed before this handoff is published.

Optional: before the provisioning apply command, add `$provisionParameters.BootstrapPath = $bootstrapResult.ArtifactPath` if you want it to validate that particular successful Bootstrap artifact. This is not required, including when running in a fresh session.

Provisioning creates/resolves the network, monitoring, vault, deployment storage, SQL server/databases, App Service plan/app, and worker VM. It attaches the shared identity and grants non-SQL dependency access. SQL mode does not assign an Entra administrator, create Entra SQL users, or automatically create runtime SQL logins.

SQL readiness is a read-only connectivity query using the supplied login in each database. It does not prove migration privileges or the application's runtime SQL access. Credentials are passed in memory as `PSCredential` objects and are not exported. See [New-AzSqlServer](https://learn.microsoft.com/powershell/module/az.sql/new-azsqlserver) and [Invoke-Sqlcmd](https://learn.microsoft.com/powershell/module/sqlserver/invoke-sqlcmd).

### Fully existing infrastructure only

If all resources, attachments, grants and network routes already exist, obtain `$sqlAdmin` as above and use:

```powershell
$provisionResult = ./scripts/Provisioning.ps1 -ConfigPath $configPath -ReuseOnly -SqlAdministratorCredential $sqlAdmin
if ($provisionResult.Status -ne 'Succeeded') { throw 'Existing infrastructure is not ready.' }
$manifestPath = $provisionResult.ArtifactPath
```

`ReuseOnly` creates nothing and opens no client rules. The runner must already be able to reach SQL. Its manifest forbids later deployment rule changes. It is not a shortcut around missing Bootstrap resources or permissions.

## 6. Prepare application settings and release packages

Before deploying application code:

1. Have an authorized SQL administrator establish the application's SQL users and least-privilege grants in the required databases. Use a separate migration login with permissions appropriate to the migration scripts.
2. Store runtime SQL credentials in Key Vault. Configure the web application's actual setting names with Key Vault references, and configure the worker's supported secret retrieval mechanism. App Service references do not automatically work in a VM process. The scripts do not invent connection-string names or distribute the provisioning administrator password.
3. If you change `WEB_APP_SETTINGS_FILE`, rerun normal Provisioning to apply the owned settings and capture the new manifest. Bootstrap does not need repeating merely because SQL authentication/settings changed.
4. Build immutable packages using the application's confirmed build process. This repository does not contain a universal build command or install the worker's runtime for you.
5. Set `WORKER_EXECUTABLE` to the executable's path relative to the package root, `WORKER_SERVICE_NAME`, optional startup arguments, and a meaningful `WORKER_HEALTH_COMMAND`. Do not place credentials in arguments or health commands. For manifest-based releases, regenerate the manifest after changing these release settings, or use current configuration as the release input.

| Target | Package layout |
| --- | --- |
| Web | `publish/web.zip` with the publish output at the archive root, without an extra outer folder |
| Worker | `publish/worker.zip` with the configured executable at its relative path; the application must support the selected Windows Service/systemd execution model |
| Database | `publish/sql` directory, or one `.sql` file. Common root `.sql` files run against every configured database first; files inside each database-key subdirectory run afterward. Each set is sorted by filename |

Every configured database must have at least one applicable SQL script for a database release. Root scripts are not restricted to one database. The public interface has no individual database selector. Review the configured list and migration scope before running it.

Database scripts must be repeatable or implement their own migration ledger/locking. The runner does not automatically track or reverse migrations. Establish schema compatibility and recovery before a destructive migration; deploying `All` runs database scripts before Web and Worker.

Web deployment currently targets the app directly, without slot swap or automatic rollback. Plan for its downtime/recovery behavior. Worker packages are stored in versioned directories; verify the application's job/drain behavior and recovery procedure rather than treating a process start as proof of useful work.

## 7. Deploy selected packages

Choose the target you actually intend to release. Do not run every example below automatically.

For database releases, obtain the SQL deployment login:

```powershell
$databaseCredential = Get-Credential -Message 'SQL database migration login'
```

The following uses the actual manifest path captured in step 5. If you opened a new session, set `$manifestPath` to the exact successful `ArtifactPath` previously printed. Do not use the example manifest from `docs/examples` or blindly select the newest artifact from another environment.

### Database only

Preview, then apply after reviewing the scripts:

```powershell
./scripts/Deployment.ps1 -ManifestPath $manifestPath -Target Database -DatabaseArtifactPath ./publish/sql -WhatIf
$releaseResult = ./scripts/Deployment.ps1 -ManifestPath $manifestPath -Target Database -DatabaseArtifactPath ./publish/sql -DatabaseCredential $databaseCredential
```

### Web only

```powershell
./scripts/Deployment.ps1 -ManifestPath $manifestPath -Target Web -WebArtifactPath ./publish/web.zip -WhatIf
$releaseResult = ./scripts/Deployment.ps1 -ManifestPath $manifestPath -Target Web -WebArtifactPath ./publish/web.zip
```

### Worker only

```powershell
./scripts/Deployment.ps1 -ManifestPath $manifestPath -Target Worker -WorkerArtifactPath ./publish/worker.zip -WhatIf
$releaseResult = ./scripts/Deployment.ps1 -ManifestPath $manifestPath -Target Worker -WorkerArtifactPath ./publish/worker.zip
```

### Web, Worker and database together

```powershell
$releaseParameters = @{
    ManifestPath = $manifestPath
    Target = 'All'
    WebArtifactPath = './publish/web.zip'
    WorkerArtifactPath = './publish/worker.zip'
    DatabaseArtifactPath = './publish/sql'
    DatabaseCredential = $databaseCredential
}
./scripts/Deployment.ps1 @releaseParameters -WhatIf
$releaseResult = ./scripts/Deployment.ps1 @releaseParameters
```

For `All` without database migrations, omit both `DatabaseArtifactPath` and `DatabaseCredential`. Web and Worker packages remain mandatory.

### Configuration instead of a manifest

A ready environment can be deployed without an artifact from Provisioning. Use exactly one of `-ConfigPath` or `-ManifestPath`:

```powershell
$releaseResult = ./scripts/Deployment.ps1 -ConfigPath $configPath -Target Database -DatabaseArtifactPath ./publish/sql -DatabaseCredential $databaseCredential
```

Create/Auto modes in configuration never authorize Deployment to create missing infrastructure. Missing targets must be provisioned first. SQL mode requires `-DatabaseCredential` whenever database scripts are selected. Web/Worker-only releases and previews need no SQL credential. Old manifests/configuration without `sql.authenticationMode` retain the former Entra behavior; regenerate a manifest from the explicit SQL-mode configuration instead of relying on an old one.

Deployment reauthenticates and manages only its authorized selected endpoint rules. If the runner's public IP changed, update `DEPLOYMENT_CLIENT_IPV4` for config-based runs, or supply `-ClientIpv4` with the actual new public `/32` for manifest-based runs. That override does not broaden allowed targets or bypass a ReuseOnly manifest's prohibition on rule changes.

## 8. Check results before calling the release healthy

After whichever live release you selected:

```powershell
if ($releaseResult.Status -ne 'Succeeded') { throw 'Release did not succeed.' }
$releaseResult | Format-List Status, ArtifactPath, RunDirectory
$releaseReport = Get-Content -LiteralPath $releaseResult.ArtifactPath -Raw | ConvertFrom-Json
$releaseReport | Select-Object status, target, releases, health
```

The report is `.artifacts/sandbox/<actual-run-id>/release-report.json`. It records selected package hashes and release results without credentials. Check each selected database's outcome and the web/worker's actual application behavior.

The default `DEPLOYMENT_ALLOW_APP_SERVICE_MAIN=false` skips the scripted web health request; a skipped check is not proof of health. If you enabled it and set the real health path, inspect the health result. The worker also needs an application-specific signal that jobs are being processed correctly. SQL credential connectivity alone does not prove the app can read its secrets and access its databases.

Temporary network grants are removed after the run, so later manual SQL connections may need separately authorized access. A manifest records observed readiness; it does not promise permanently open endpoints.

## 9. Troubleshooting and recovery

Stop at the first failed step. Preserve the full error text, command, and reported run directory, with secrets removed. If input validation failed before run initialization, there may be no report. Otherwise inspect that run's `run-report.json`, and `release-report.json` for a failed release when available.

| Error or symptom | Next action |
| --- | --- |
| `Required resource group ... does not exist`, `Required managed identity ... does not exist` | Complete Bootstrap step 4 for the same config/tenant/subscription, then rerun Provisioning. If mode is Existing, check its actual ID/name; a missing Existing resource is not created |
| `Required Azure providers are not registered` | Run Bootstrap with registration enabled and sufficient permission. If registration is still pending, wait and rerun Bootstrap |
| `Provider ... registration is 'Registering'` | Registration is not finished. Allow it to finish and rerun Bootstrap; do not proceed on preview output |
| `SQL_ENTRA_ADMIN_* ... required` | Your local env file may predate SQL mode. Add `SQL_AUTHENTICATION_MODE=Sql` once, save it, and rerun. JSON uses `sql.authenticationMode` |
| `SqlAdministratorCredential is required` | Obtain `Get-Credential` and pass `-SqlAdministratorCredential` to Provisioning, including ReuseOnly |
| `DatabaseCredential is required` | Pass the SQL migration credential to Deployment when selecting database scripts |
| `SQL_AUTHENTICATION_MODE must be one of ...` or unknown/duplicate env key | Use exactly `Sql` or `Entra`; fix the stated key/line. Env files are data, not executable PowerShell |
| Required runtime, worker OS, executable, or SSH key error | Fill the relevant fields in step 3/6; use an existing absolute public-key path for Linux |
| Public IPv4 `/32` is missing or rejected | Supply confirmed public egress IPv4/32. Private LAN, broad CIDRs and documentation/example ranges are rejected |
| Azure authorization failure | Have the administrator review the denied Azure operation and scope; a SQL login cannot authorize Azure resource creation or role assignments |
| Azure tenant/subscription mismatch | Correct the explicit IDs and use the intended account. Interactive/DeviceCode are available; `ExistingContext` requires an already matching context |
| SQL login failure | Confirm the server, current SQL username/password, and database access. An existing server password is not reset; Entra-only server policy needs a separate approved review |
| SQL timeout or firewall failure | Check public egress IP, enabled SQL rule scope, and routing/DNS. ReuseOnly opens no rules; Private mode needs preexisting private connectivity |
| SCM inherits restricted main-site rules | Review the main-site rule policy. Authorize `DEPLOYMENT_ALLOW_APP_SERVICE_MAIN` only if intended, or arrange equivalent existing access |
| Resource location, OS, name conflict or quota failure | Correct the actual configuration/approved resource choice; do not change eastus, rename resources randomly, or delete resources to bypass it |
| Artifact path or worker executable missing | Build the real package, verify its location/layout, and update release settings before retrying |
| `CleanupFailed` or interrupted process | Inspect the run's `network-access.json` and live rules. Verify ownership, scope and exact rule state before any cleanup; preserve unrelated/equivalent rules |

Correct the cause before rerunning. A partial run may have created resources; the scripts re-resolve exact names on rerun, but they do not roll back already created infrastructure. No need to rerun successful Bootstrap solely for a SQL-mode change.

Do not assume rerunning automatically recovers rules from an earlier hard interruption: the current network module does not reconcile prior run journals. Review those journals and live rules with an authorized operator. Temporary is a cleanup policy, not a service-side automatic expiry.

Retry database scripts only after reviewing their partial state/ledger. Do not assume all databases changed atomically or that an application rollback reverses a migration. Consult [operations](operations.md) and [network access details](bootstrap-and-network-access.md) for recovery context.

## 10. Optional authentication modes and output location

Interactive is the default. For device-code login, add `-AuthMode DeviceCode` to the owning script's command. `ExistingContext` is opt-in and requires a matching context. `ServicePrincipalCertificate` requires `-AuthClientId` and `-CertificateThumbprint`; `ManagedIdentity` requires a suitable Azure runner. `-NonInteractive` rejects Interactive/DeviceCode. See [authentication](authentication.md).

Every script accepts `-OutputDirectory`. The default `.artifacts` is relative to your current working directory; runs are written underneath `<output>/sandbox/<run-id>/`. Use returned `ArtifactPath`/`RunDirectory` values when changing this root. Each script can run in a new process with configuration and the credentials it needs; neither prior login nor a prior script's in-memory variables are mandatory outside this walkthrough.
