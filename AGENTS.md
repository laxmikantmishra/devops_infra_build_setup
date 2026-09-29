# Azure infrastructure and application deployment guidelines

## Purpose and current scope

Build a modular, PowerShell-driven deployment solution for an existing application that needs:

- An Azure App Service and its App Service Plan.
- A virtual machine running a worker service.
- SQL hosting with multiple application databases.
- Application Insights and an explicitly linked Log Analytics workspace.
- An Azure Key Vault.
- One shared user-assigned runtime managed identity for App Service and the worker VM.
- Supporting network, disk, identity, and monitoring resources.

All application infrastructure and its supporting Azure resources must belong to one configured resource group per environment. Create that group when needed or reuse it. Microsoft Entra identities are tenant objects, and subscription-level prerequisites are outside resource-group scope.

The three PowerShell workflows and resource/release modules are implemented. The sample configuration remains a template and requires application-specific values before live use. Do not claim any resource has been discovered or deployed until it has actually been verified in Azure.

## Selected environment and naming

- Environment: `sandbox`; application identifier/tag: `askey-swarms-sandbox`.
- Region: `eastus` for all regional application resources and resource-group metadata. Preserve required global scopes and parent-inherited locations. Validate existing resource locations; do not move resources or fall back to another region automatically.
- Resource pattern: `AEY-EU-SWARMS-SANDBOX-{TYPE}-01`. `EU` is the exact requested name token; it does not select a Europe region.
- Type keys include RG, UAMI, ASP, APP, VM, SQL, DB-<logical-key>, AI, LAW, VNET, and appropriate supporting-resource keys. Use lowercase for SQL/DNS-facing names. Key Vault uses `aey-eu-swarms-sbx-kv-01` to fit its service limit. Worker VM resource name is `AEY-EU-SWARMS-SANDBOX-VM-01` with distinct guest computer name `AEYEUSWRMSBX01`.
- Preserve explicit existing IDs and actual resource/database names. Validate name/ID consistency and report naming deviations. Auto mode uses exact names. Global-name conflicts require explicit overrides; no random suffixes, silent sequence changes, or resource replacements.
- Resolve naming consistently across all three independent scripts. Export actual names, IDs, locations and computer names, and validate per-service rules before writes. See `docs/naming.md` and the sandbox configuration examples.

## Working principles

1. Keep infrastructure provisioning, application configuration, database migrations, and application releases separate and independently runnable.
2. Support empty environments, partially provisioned environments, and environments where every resource already exists.
3. Use configuration files and resource IDs rather than environment-specific values embedded in scripts.
4. Make repeat runs safe. Inspect actual state, calculate the intended changes, and apply only the selected operations.
5. Preserve existing data, settings, permissions, and unrelated resources. Reuse does not imply permission to reconfigure a resource.
6. Use least-privilege identities and keep credentials out of source control, command arguments, logs, and output artifacts.
7. Implement one phase at a time with observable outputs and a clear completion check.
8. Follow the user's authorized scope. Do not repeatedly request permission for already authorized routine work. Obtain explicit authorization for destructive changes or production cutovers not covered by the request.
9. Use current Microsoft documentation to verify supported API versions, SKUs, runtime support, and deployment commands when implementing.
10. Record assumptions and unresolved decisions. Never silently substitute a different SQL product, operating system, subscription, or resource group.

## Decisions to resolve before implementation depends on them

| Decision | Information needed |
| --- | --- |
| Azure target | Tenant/subscription IDs remain required; sandbox, eastus and the naming convention are selected |
| Web application | Language/framework, runtime version, Windows or Linux, source/build commands, artifact format, health endpoint |
| Worker | Windows Service or Linux systemd service, runtime, startup arguments, queue/job behavior, shutdown/drain behavior, health signal |
| SQL product | Azure SQL Database on a logical SQL server, SQL Managed Instance, or SQL Server on a VM |
| Databases | Names, sizing, service tiers, optional elastic pool, authentication, migration tooling, backup/retention requirements |
| Existing resources | Explicit resource IDs where available, ownership, compatibility, and whether changes are allowed |
| Networking | Public endpoints with restrictions or private access; deployment runner reachability; application outbound dependencies |
| Operations | Availability needs, allowed downtime, release strategy, recovery objectives, monitoring retention, budget |
| Delivery | Local execution or CI/CD, build location, artifact storage, deployment identity |

The provisional architecture below assumes Azure SQL Database with one logical server and many databases. This is a design assumption, not a settled requirement. Validate application compatibility before selecting it. A single worker VM is also a single point of failure; record whether this meets the application's availability needs.

## Architecture and resource boundaries

| Module | Responsibility | Dependencies |
| --- | --- | --- |
| Prerequisites | Read-only tool, configuration, context, permission and readiness checks | Explicit target configuration |
| Bootstrap | Register needed providers when configured; resolve/create group and identity | Matching plan and preflight |
| NetworkAccess | Grant/remove explicitly scoped deployment-client IP rules, or verify private reachability | Resolved targets and planned changes |
| ResourceGroup | Resolve or create the single target group and its tags | Explicit subscription context |
| ManagedIdentity | Resolve or create the shared user-assigned runtime identity | Resource group |
| Network | VNet, subnets, NSGs, required private endpoints and private DNS | Resource group and network design |
| Monitoring | Log Analytics, workspace-based Application Insights, configured diagnostics/alerts | Resource group |
| KeyVault | Vault, intended secret references, access configuration | Resource group; network if private |
| SqlServer | Logical SQL server and optional elastic pool under the provisional SQL choice | Resource group; network if private |
| SqlDatabases | Independently create or resolve every configured database | Resolved SQL server/pool |
| AppService | App Service Plan, web app, managed identity, optional deployment slot | Resource group; network integration if selected |
| WorkerVm | VM, NIC, disks, managed identity, OS/runtime bootstrap | Resource group and network |
| AccessAndConfiguration | Scoped role assignments, database users/grants, owned application settings | Resolved resources and identities |
| WebRelease | Deploy a versioned web artifact and check readiness | Compatible web app and configuration |
| WorkerRelease | Transfer a versioned artifact, install/update the service, verify it | Compatible VM and configuration |
| DatabaseRelease | Execute the configured migration process for selected databases | Database access and migration artifact |
| DeploymentManifest | Export resolved non-secret resource references and validate them for local releases | Resolved resources and verified deployment prerequisites |

Explicitly provision or reference a Log Analytics workspace in the same resource group. Avoid implicit workspace creation that can introduce another resource group. Enforce the same-group rule for reused dependencies too. Report resources found outside the group as conflicts; do not move or recreate them automatically.

## Tooling and repository layout

Use PowerShell 7 and tested versions of the Az PowerShell modules for authentication, discovery, planning, provisioning, and orchestration. This project must not use Bicep. Do not introduce ARM deployment templates, Terraform, or azd as replacement infrastructure tooling unless the user changes this decision. Pin supported tool versions in the implementation documentation. Keep application deployment commands behind PowerShell functions appropriate to the actual application stack; application build and migration tools may still be invoked from PowerShell.

Use resource-specific Az cmdlets directly. Where a required operation is unavailable in the selected Az modules, isolate an authenticated Azure REST call behind a PowerShell helper with an explicitly supported API version, error handling, and the same preview safeguards. Do not use template deployment commands as a fallback.

The following is the implemented layout. See README.md for the current validation status.

```text
AGENTS.md
README.md
config/
  environment.schema.json
  sandbox.example.json
  sandbox.env.example
  databases.example.json
scripts/
  Bootstrap.ps1
  Provisioning.ps1
  Deployment.ps1
  modules/
    Common.psm1
    Authentication.psm1
    Prerequisites.psm1
    Bootstrap.psm1
    NetworkAccess.psm1
    Configuration.psm1
    DeploymentManifest.psm1
    Discovery.psm1
    Planning.psm1
    Infrastructure.psm1
    resources/
      ResourceGroup.psm1
      ManagedIdentity.psm1
      Network.psm1
      Monitoring.psm1
      KeyVault.psm1
      SqlServer.psm1
      SqlDatabases.psm1
      AppService.psm1
      WorkerVm.psm1
    AccessAndConfiguration.psm1
    DatabaseRelease.psm1
    WebRelease.psm1
    WorkerRelease.psm1
    Verification.psm1
  guest/
    Install-WorkerWindows.ps1
    install-worker-linux.sh
tests/
  unit/
  integration/
docs/
  architecture.md
  operations.md
  runbook.md
  decisions.md
  environment-to-deployment.md
  managed-identity.md
  authentication.md
  naming.md
  bootstrap-and-network-access.md
  examples/
    deployment-manifest.example.json
.artifacts/                     # Generated, ignored by Git
  <environment>/<run-id>/
```

Implement only the guest operating system actually selected. Resource modules return typed objects; the orchestrator controls dependencies and reporting. Do not couple modules through mutable global variables or by parsing console messages.

Each resource module must separate reading current state, comparing owned properties, and applying planned changes. `Planning.psm1` assembles those comparisons into an ordered plan; `Infrastructure.psm1` executes the resource modules in dependency order. Reuse the same comparison logic for planning and execution so their behavior cannot diverge.

## Environment configuration contract

Use an environment-style `.env` file as the primary authored input. Reference structured collections such as multiple databases through JSON files whose paths resolve relative to the environment file. Parse input as data without dot-sourcing, evaluation, variable expansion, or implicit process-environment overrides. Reject malformed lines and unknown/duplicate keys. JSON remains an alternative input; select one format per run and do not silently merge them.

Normalize input into a single configuration object and define and validate its versioned JSON schema before provisioning. Include:

- `schemaVersion`, `environment`, `tenantId`, `subscriptionId`, `location`, `resourceGroup`, and `tags`.
- Naming inputs: application identifier, full and shortened prefixes, instance string, explicit name overrides, and separate VM computer name. Keep the instance as a string to preserve its leading zero.
- A resource entry for each primary resource and supporting dependency, with `mode`, `name` or `resourceId`, and required creation properties.
- A database collection with a stable key, database name or ID, mode, capacity/tier, and migration configuration for each database.
- Web and worker runtime settings, managed identities, network requirements, and health checks.
- Shared runtime identity mode/name/resource ID; discover and export its client/principal IDs rather than accepting inconsistent operator-supplied IDs.
- Versioned application artifacts with expected checksums and migration artifact/version references.
- Secret identifiers or retrieval references only; no secret values.
- An explicit allowlist of configuration keys and permissions this solution owns and may change.
- Bootstrap provider-registration setting, deployment network mode, explicit public client IPv4/32 when applicable, temporary/persistent lifetime, and selected endpoint allowlist flags.

Keep authored desired configuration separate from generated inventory. Discovery may produce a candidate configuration, but must not overwrite the user's source configuration. Reject unknown fields, duplicate database names, inconsistent parent IDs, invalid combinations, and missing required values with actionable errors.

### Per-resource modes

| Mode | Behavior |
| --- | --- |
| `Create` | Declare the resource as managed by this solution. Create it when absent. On rerun, reconcile only when ownership and identity match; report unrelated name collisions. |
| `Existing` | Resolve an explicit resource ID and validate compatibility. Reference it without redeclaring its infrastructure properties. |
| `Auto` | Look for an exact type/name in the configured group. If found and compatible, reuse it as `Existing`; if genuinely absent, plan creation. |

Use the same rules independently for the SQL server and every database, and for the App Service Plan and web app. A server can be reused while missing databases are created. Supporting dependencies must be resolved as deliberately as primary resources.

Treat access denied, timeouts, throttling, and incomplete enumeration as discovery failures, never as proof a resource is absent. Do not fuzzy-match or silently select between candidates. Name availability outside the group does not authorize adopting an external resource.

`Existing` resources may receive application artifacts and explicitly authorized configuration changes through separate release/configuration stages. Changing their infrastructure requires an explicit adoption decision and reviewed desired properties. Switching a mode must never itself delete a resource.

## Execution interface: exactly three scripts

The three public scripts are **Bootstrap, Provisioning, and Deployment**, each independently invoked. The arrow order describes a new-environment lifecycle, not mandatory script chaining or artifact dependencies. No script invokes another entry script. Do not add a stage dispatcher or require separate preflight, discover, plan, network-access, configure, or verify commands. Keep those concerns in internal modules invoked by the owning script.

| Script | Responsibilities | Input | Successful output |
| --- | --- | --- | --- |
| `Bootstrap.ps1` | Validate configuration/tools/context, discover/plan bootstrap resources, register required providers, resolve/create group and shared identity, verify results | `-ConfigPath` | `bootstrap.json` |
| `Provisioning.ps1` | Resolve live prerequisites, optionally validate bootstrap artifact, discover/plan resources, configure infrastructure/access and verify readiness | `-ConfigPath`, optional `-BootstrapPath` | `deployment-manifest.json` |
| `Deployment.ps1` | Resolve existing targets from configuration or manifest, check live prerequisites, deploy selected packages, verify and clean up | Exactly one of `-ConfigPath` or `-ManifestPath`, selected package paths | `release-report.json` |

```powershell
# Operator workflow.
./scripts/Bootstrap.ps1 -ConfigPath ./config/sandbox.env
./scripts/Provisioning.ps1 -ConfigPath ./config/sandbox.env
./scripts/Deployment.ps1 -ConfigPath ./config/sandbox.env -Target Web -WebArtifactPath ./publish/web.zip
# Alternatively use a saved manifest without an environment file.
./scripts/Deployment.ps1 -ManifestPath ./path/to/deployment-manifest.json -Target Web -WebArtifactPath ./publish/web.zip
```

- Each script initializes its own dependencies/authentication and explicit Azure context in a fresh process. Import helpers relative to $PSScriptRoot; do not rely on caller globals or a previous script login. Authentication defaults to interactive operator login; a deployment SPN is optional. Missing actual Azure prerequisites still produce actionable errors.
- Provisioning requires the configured group/shared identity and selected provider registrations to exist; discover them directly when no bootstrap artifact is supplied. Do not automatically invoke Bootstrap. Deployment accepts configuration or a manifest and only resolves existing targets, irrespective of Create/Auto input modes. Never infer permission to provision from deployment input.
- Validate input per script and selected target; do not require unrelated creation settings, packages or configuration files for operations that do not use them.
- Every script accepts `-WhatIf` and `-OutputDirectory`; the latter defaults to `.artifacts` relative to the caller's working directory. Write run output beneath `<output>/<environment>/<run-id>/`. Report actual handoff paths on success.
- `Provisioning.ps1 -ReuseOnly` prohibits all resource/configuration/permission/firewall changes, verifies existing readiness and connectivity, and exports a manifest only if sufficient. Normal provisioning uses Create/Existing/Auto per resource. Never create resources in ReuseOnly even if a resource mode says Create or Auto.
- Deployment is the code-only workflow. It accepts a manifest without an environment file or an environment file without any manifest; no DeploymentMode switch is needed. It never provisions missing resources or repairs runtime identities, permissions, or database configuration. The only infrastructure access changes it may make are narrowly defined deployment-client rules explicitly permitted by its selected configuration or manifest.
- Deployment `-Target` supports Web, Worker, Database, and All. Web/Worker require the corresponding package argument. Database requires `-DatabaseArtifactPath`. All deploys web and worker, adding database migrations only when an explicit database artifact is supplied. Reject unrelated/missing package inputs before mutation.
- Internal planning compares owned properties and records Create/Update/Reuse/NoChange/Conflict with reasons/dependencies before writes. There is no required separately generated plan file. Bind each internal plan to configuration, script and dependency-file hashes and discovered identities; revalidate before apply.
- Use SupportsShouldProcess and guard every mutation, including native, guest, database and REST calls. Preview dependent creation without using fabricated resource outputs. WhatIf does not prove service-side success and must not publish a successful handoff artifact. Do not add a blanket Force bypass.

### Authentication without an existing deployment SPN

- Default to interactive Azure PowerShell operator login (MFA/tenant policies apply). A custom app registration or deployment service principal is not required. Do not silently create one merely to execute these scripts.
- Reserve common AuthMode, AuthClientId, CertificateThumbprint, and NonInteractive parameters. Explicit arguments override mode-specific non-secret config values. Manifest-only execution defaults to Interactive unless explicitly overridden; artifacts do not supply credentials. NonInteractive forbids login prompts. See docs/authentication.md for mode contracts.
- Each script validates the requested tenant/subscription before Azure operations. ExistingContext is an explicit opt-in, not a dependency on earlier scripts. Certificate/SPN and Azure-runner managed identity are optional modes with their own prerequisites. Do not silently switch accounts or downgrade to username/password authentication.
- The shared runtime managed identity is separate from operator authentication. Its service principal is Azure-managed and needs no custom application registration. Lack of SPN is different from lack of authorized tenant/subscription access.
- App registration is a separate optional requirement for application sign-in or automation. Before adding create/reuse behavior, establish its purpose, application type, exact permissions/consent, redirect URIs and credential method. Preserve reused registrations. Do not grant broad Graph access or reset credentials automatically; tenant rights and Azure RBAC are distinct. Ordinary interactive Azure operations must not depend on unneeded Graph permissions. Continue using PowerShell; no Bicep.

### Bootstrap and network access inside the three scripts

- Each script validates explicit tenant/subscription and reports unreadable/unresolved prerequisites. Bootstrap can discover and plan an absent group without first creating it. It may register only required missing providers when configured and resolve/create the target group/shared identity; it does not create subscriptions or self-grant permissions.
- Bootstrap validates deployment IP/private-route settings and may apply explicitly planned rules only to existing dependencies it actually needs. Provisioning handles access to newly created resources and data-plane configuration. Deployment rechecks current connectivity and may reconcile only the selected input's authorized client rules for selected release targets.
- The shared NetworkAccess module handles these operations internally. Each owning script journals and cleans its temporary changes in finally before returning, including failures. Persistent grants remain only when configured. No rule needs to be kept temporarily open between scripts: the next script obtains its own authorized access.
- Deployment may accept `-ClientIpv4` as an explicit public IPv4/32 override; it must not expand permitted endpoint scopes, lifetime, default actions or public-access settings. Without an override, use the selected input's policy address. Require valid explicit IP input for a public grant; never infer a private LAN IP or silently contact an external detection service.
- Preserve existing rules and identities, SCM inheritance, default actions, and unrelated grants. Reused equivalent rules remain unowned. Inspect first-allow-rule impacts and priority conflicts. Private endpoints require private reachability; managed identity and public IP rules cannot bypass network controls. No automatic SSH/RDP exposure or trusted-service bypass.
- Write access journals before mutation and track per-rule ownership, context, and exact prior/current state. Handle concurrent use with locking/conflict detection. On hard interruption, retain actionable journals and reconcile through the owning script on resume. These rules do not acquire automatic expiry from manifest metadata.
- Bootstrap and provisioning reports record successful changes so reruns revalidate actual state and do not recreate resources. Full details are in `docs/bootstrap-and-network-access.md`.

### Output artifacts and local deployment

- Bootstrap exports version/status, target context, resolved group/shared identity, registration/check results and provenance in bootstrap.json. If supplied, Provisioning verifies it against configuration and live Azure state before using it. Otherwise discover those prerequisites directly; do not require a prior report.
- Provisioning exports deployment-manifest.json containing resource IDs, non-secret endpoints, database mappings, optional bootstrap provenance, per-target readiness, and the authorized deployment-network policy (mode, client IP, allowed targets, lifetime, rule-change permission). ReuseOnly exports rule-change permission as false. These readiness checks describe observed state, not permanent open access.
- Include `resources.managedIdentity.resourceId`, `clientId`, and `principalId`, plus identity attachment references for web/worker. Verify all IDs against live state before releases; identity recreation can change principal/client IDs while retaining a resource name/ID.
- Publish successful handoff artifacts atomically after required checks and owned temporary cleanup succeed. Partial failures and unresolved cleanup remain truthful run reports and must not be labeled ready. Keep the journals available for recovery.
- Export no passwords, access tokens, publish profiles, signed URLs, or credential-bearing connection strings. Treat artifacts as untrusted input and validate schema/status, target context and allowed operations. Reject example artifacts and unresolved IDs. Possession of a manifest does not authenticate the operator.
- Deployment records package versions/checksums, selected input hash, exact targets, health results and cleanup status in release-report.json. A failed release still produces a failure report where possible. Local build tooling depends on the confirmed runtime.
- See `docs/environment-to-deployment.md` for the handoff contract. The examples are drafts; artifact parsers/exporters, Azure operations and releases remain unimplemented.

## Three-phase implementation plan

Implement common configuration validation, context/tool checks, logging and artifact contracts first, then complete the three scripts in sequence. Shared helpers stay internal.

| Phase | Deliverables | Completion check |
| --- | --- | --- |
| 1. Bootstrap | Environment parser, prerequisite checks, bootstrap discovery/plan, provider registration, group/shared-identity modules, bootstrap report | Correct subscription; empty and existing group/identity scenarios; safe reruns and no preview writes |
| 2. Provisioning | Resource modules, discovery/plan, per-service access rules, identity/database permissions and application configuration, verified manifest, ReuseOnly mode | Empty/partial/existing environments work; repeat runs preserve unrelated state; temporary access cleanup verified |
| 3. Deployment | Configuration- or manifest-based local web/worker/database releases, bounded client-access handling, health checks, recovery, release report | Selected versions run successfully; compatible rollback and failed-release cleanup verified; independent releases use configuration or a manifest plus local artifacts |

Maintain documentation and meaningful tests alongside each phase. Add CI/CD only after the same three scripts work locally. Resource dependencies remain group → shared identity/network/foundational services → compute/databases → identity attachments/configuration → releases.

## Infrastructure and security rules

- Validate tenant and subscription explicitly on every run; use an explicit Azure context in module calls. Do not rely on whichever account was last selected interactively.
- Read current state before deciding whether to create or update. Compare normalized values only for properties owned by this solution, skip unchanged resources, and re-read after a successful write to verify the outcome. Never delete a resource because it is absent from configuration.
- Resolve `Existing` resources with read-only Az calls. Keep managed and reused branches explicit and return consistent resolved IDs from both; provisioning must not call create/update cmdlets on reused resources.
- For managed resources, update only planned properties using the supported resource-specific operation. Some cmdlets/APIs replace whole settings collections; preserve unrelated values and detect intervening changes where supported. Fail on changes requiring replacement or unsupported in-place updates rather than recreating resources automatically.
- Validate App Service OS/plan compatibility, VM image/architecture and worker runtime, SQL server/database parentage, resource locations where coupling requires them, and required networking.
- Use one shared user-assigned identity per environment, attached to both the web app and worker VM. Keep its Azure resource in the same group. It supports Create/Existing/Auto like other resources. Configure changes must preserve existing system-assigned and unrelated user-assigned identities; Deployment must only validate them.
- Keep runtime identity permissions separate from provisioning, local deployment, SQL bootstrap, and migration permissions. Do not grant the shared runtime identity broad group-level management roles or directory permissions for setup convenience. Sharing a principal gives both workloads all its grants; document this shared trust boundary.
- Configure scoped Key Vault secret-read access, explicit users and runtime grants in each required database, and Monitoring Metrics Publisher on the Application Insights resource when the selected SDK/agent supports Entra-authenticated ingestion. Never assume Azure RBAC grants SQL query access. Confirm exact SQL grants and runtime support before marking readiness.
- Select the shared identity explicitly in each application's supported credentials. For App Service Key Vault references set `keyVaultReferenceIdentity` to its resource ID. Verify access from the actual web and worker hosts with bounded propagation retries. Identity does not replace network connectivity or application authentication configuration. Follow `docs/managed-identity.md` for the detailed access plan.
- Prefer identity-based SQL authentication when the application supports it. Otherwise retrieve credentials securely at runtime. Never store credentials in deployment outputs.
- Use App Service Key Vault references where appropriate. The VM worker needs its own supported secret retrieval mechanism; App Service references do not apply automatically to VM processes.
- Configure HTTPS/TLS, vault soft-delete/purge protection for new vaults, restrictive inbound access, and explicit retention policies. Do not alter protection settings on reused resources silently.
- Do not expose SQL to all Azure services or open RDP/SSH to the internet as a shortcut. Select a supported deployment route that the runner can actually reach.
- Treat App Service VNet integration, private inbound endpoints, DNS, and deployment endpoint access as separate requirements. Check the selected SKU supports the intended features.
- Merge only owned settings and permissions where possible; preserve unrelated settings and vault entries. Record any API that replaces an entire settings collection and handle it deliberately.

## Application and database release rules

- Build once and deploy immutable, versioned artifacts. Record checksums and release IDs. Keep infrastructure provisioning independent of local source builds.
- For web releases, use a staging slot when supported and selected. Verify readiness before swap. Otherwise document the direct-deployment downtime/recovery strategy.
- For worker releases, stage files in a new version directory, validate them, drain or stop the service cleanly, switch versions, start the service, and verify sustained health. Preserve the last known working version.
- Ensure Windows Service/systemd configuration includes the intended service account, startup policy, runtime, file permissions, and restart behavior. Do not assume every worker artifact is installable as a service.
- For job workers, account for duplicate processing, leases, graceful shutdown, and safe retries. A running process alone does not prove worker health.
- Database creation belongs to infrastructure; schema and data migrations belong to DatabaseRelease. Never infer permission to delete a database or reset its schema from a desired database list.
- Track and lock migrations per database using the selected migration framework. Report success/failure per database; multiple databases do not form one atomic release.
- Prefer backward-compatible expand/contract migrations. Determine the exact migration/web/worker order from compatibility needs. Stop dependent releases after a failed prerequisite migration.
- Review destructive migrations explicitly and verify the recovery path before execution. Do not automatically reverse migrations or restore a database during application rollback.
- Roll back web/worker artifacts only when compatible with the current schema. Treat database recovery as a separate procedure with its own data-loss and downtime implications.
- Instrument the application and worker with supported telemetry integration. Creating Application Insights alone does not instrument application code.

## PowerShell reliability and reporting

- Use approved verbs, explicit parameter types, strict mode, terminating errors for failures, and `try/catch/finally` around stateful operations.
- Check native-process exit codes. Do not report success because a command produced output.
- Use bounded retries with backoff only for transient failures and retry-safe operations. Handle identity/RBAC propagation delays; do not blindly retry migrations.
- Produce structured, sanitized logs with run ID, stage, target, duration, status, and actionable error context. Do not capture unrestricted transcripts that can include secrets.
- Save inventory, resolved resource IDs, the change plan, preview results, artifact versions, and final verification results under the environment/run directory.
- Bind a plan to the target subscription/group, configuration/script hashes, tool versions, and discovered resource identities. Reject stale or mismatched plans and revalidate before applying.
- Checkpoints assist resume but do not replace live validation. Resume only after checking completed stages and current desired inputs.
- On failure, retain diagnostics, return a nonzero exit code, and stop dependent operations. Do not remove successfully provisioned resources as automatic cleanup.
- Return a concise final summary showing created, reused, changed, deployed, skipped, and failed targets. Redact secret values and signed URLs.

## Verification and acceptance criteria

Use Pester for meaningful configuration, resolver, state-comparison, entry-point and target-selection, and failure-handling tests; use PSScriptAnalyzer and PowerShell parsing checks. Mock Az calls to verify that reused and unchanged resources receive no provisioning writes, and that preview mode never invokes mutating Az, REST, guest, or native operations. Run cloud integration tests in an explicitly designated test environment. Do not create cost-incurring test environments without authorization.

The solution is complete when these scenarios are verified:

1. Empty environment: create the group and required resources, configure access, deploy, and verify health.
2. Partial environment: reuse compatible resources and create only missing dependencies/databases.
3. Fully existing environment: resolve explicit IDs and deploy selected application artifacts without infrastructure creation.
4. Repeat run: no unintended resource, settings, permission, or data changes.
5. Invalid environment: incompatible OS/SKU, wrong group/subscription, missing permissions, or ambiguous resources fail before mutation.
6. Failure/recovery: failed migration blocks dependent release; failed worker/web rollout reports correctly and follows the documented recovery procedure.
7. Isolation: selecting one application target or database does not deploy unrelated targets.
8. Secrets and preview: logs/artifacts contain no secrets, and preview mode causes no resource, guest, or database writes.
9. Connectivity and telemetry: web and worker can reach required databases/vault endpoints and emit useful telemetry; check ingestion with bounded waiting.
10. Resource-group boundary: all selected application resources and dependencies are verified against the configured group.
11. Shared identity: web and worker use the expected principal for required dependency operations; repeated configuration preserves unrelated identities/grants; stale identity IDs and missing database permissions fail readiness checks.
12. Bootstrap/access: wrong subscription or missing prerequisites stops changes; existing rules survive reruns/cleanup; disabled public endpoints are never opened implicitly; both success and failure paths clean up owned temporary rules or report pending cleanup.

13. Independent invocation/authentication: each script works in a fresh process with direct configuration and no prior artifact/SPN for interactive mode; optional-artifact mismatches fail; missing tenant/resource prerequisites produce precise errors without invoking another script.

## Documentation required with implementation

Maintain a README with prerequisites, configuration examples for all three starting states, the three script commands, permission requirements, artifact preparation, expected outputs, and troubleshooting. Document selected runtime/SQL decisions, owned configuration keys, database migration ordering, worker recovery, web rollback, and operational limitations.

## Microsoft references

- [Azure Az PowerShell modules](https://learn.microsoft.com/en-us/powershell/azure/new-azureps-module-az)
- [PowerShell ShouldProcess and WhatIf](https://learn.microsoft.com/en-us/powershell/scripting/learn/deep-dives/everything-about-shouldprocess)
- [Workspace-based Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/create-workspace-resource)
- [Application Insights managed workspaces](https://learn.microsoft.com/en-us/azure/azure-monitor/app/managed-workspaces)
- [App Service managed identities](https://learn.microsoft.com/en-us/azure/app-service/overview-managed-identity)
