# Bootstrap prerequisites and deployment network access

## Execution order

```text
Bootstrap.ps1 → bootstrap.json
Provisioning.ps1 → deployment-manifest.json
Deployment.ps1 → release-report.json
```

These are independently invoked scripts; the arrows show outputs, not compulsory chaining. Each script owns authentication, validation, planning, required client access, verification, and temporary-rule cleanup. NetworkAccess is an internal module, not an operator command. No subscription or firewall has been changed in this repository session.

## Prerequisites and bootstrap

The internal prerequisites helper validates configuration, PowerShell/Az dependencies, authentication, and the explicitly configured tenant/subscription. It checks relevant permissions, provider state, selected region/SKU availability, capacity, policies and locks as far as readable. Report unverified checks instead of inventing readiness. Do not mutate Azure during preflight. Select a process-scoped context and pass it explicitly to operations; never fall back to another accessible subscription. [Azure context documentation](https://learn.microsoft.com/en-us/powershell/azure/context-persistence)

Internal discovery/planning must work when the target group does not exist. Bootstrap.ps1 builds and validates its own plan before create calls:

1. Register missing providers required for selected resources if `BOOTSTRAP_REGISTER_PROVIDERS=true`; otherwise report missing registrations. Typical namespaces include Microsoft.ManagedIdentity, Microsoft.Web, Microsoft.Compute, Microsoft.Network, Microsoft.Sql, Microsoft.KeyVault, Microsoft.Insights, and Microsoft.OperationalInsights. Derive the actual set from the selected architecture. Do not register every provider, enable preview features, or unregister providers on cleanup. [Resource provider registration](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-providers-and-types)
2. Resolve/create the resource group in `SUBSCRIPTION_ID`, with the configured region and owned tags.
3. Resolve/create the shared user-assigned identity in that group using the established resource modules.
4. Write `.artifacts/<environment>/<run-id>/bootstrap.json` containing target context, run/config/script hashes, registration results, resolved group/identity IDs, timestamps, and per-step status. A bootstrap report is not an application deployment manifest.

Bootstrap does not create subscriptions or tenants, grant itself missing privileges, or deploy application code. Keep subscription provider permissions, group creation rights, runtime role assignments, and database bootstrap permissions distinct. A reused group/identity is validated; it is not silently taken over.

Provisioning.ps1 resolves bootstrap prerequisites directly from its configuration, validates a bootstrap artifact only if supplied, and builds its own plan from live state. Unexpected drift must be resolved before apply. Resuming bootstrap must not recreate successful resources.

## Deployment machine access

`DEPLOYMENT_CLIENT_IPV4` supplies the public egress IPv4 **with /32**, for example `203.0.113.10/32` (documentation-only; replace it). Reject blank, malformed, private, reserved/example, or broad ranges before granting public access. Behind a VPN/proxy/NAT, use the egress seen by the target service. Do not silently contact an external IP-discovery service. A future explicit detection option must show the detected address in the plan.

`DEPLOYMENT_NETWORK_MODE=PublicAllowList` plans exact client-IP rules for selected public endpoints. `Private` adds no public IP rules and expects the operator host to already have private DNS and routing. Service calls and health checks validate reachability when they run. Mixed public/private endpoints require per-target policy support; do not silently change modes.

The internal NetworkAccess module runs after targets exist and before a script needs their data-plane endpoints. Bootstrap may use it for selected existing dependencies; Provisioning uses it after creating/resolving targets; Deployment uses only endpoint rules authorized by its selected configuration or manifest. A missing target is pending, not a successful grant. Provisioning -ReuseOnly performs no grants or other Azure writes.

| Target | Access rule and check |
| --- | --- |
| Azure SQL Database logical server | Exact client IPv4 as equal firewall start/end addresses; this server-level rule covers its databases, while SQL authentication/grants still restrict data access |
| Key Vault | Client /32 in the vault firewall if public selected-network access is permitted; caller still requires data-plane permission |
| App Service SCM/Kudu | Explicit deployment-endpoint rule; check whether SCM inherits main-site restrictions and preserve that setting unless an explicit planned change authorizes otherwise |
| App Service main site | Separate opt-in rule for direct smoke tests; do not restrict or expose the app simply to enable SCM deployment |
| Worker VM | Use the selected private/agent-based deployment route; no automatic public IP, SSH/RDP rule, or guest-firewall opening |

SQL behavior depends on the selected SQL product. Do not apply Azure SQL Database firewall commands to Managed Instance or SQL Server on a VM. For supported Azure SQL public endpoints, firewall rules do not replace database credentials. [SQL firewall documentation](https://learn.microsoft.com/en-us/azure/azure-sql/database/firewall-configure)

Inspect existing priorities and default actions on App Service before adding rules. Adding the first allow rule can change unmatched traffic behavior; identify this in the plan and stop on unintended customer-access impact. Account for deny rules, SCM inheritance, and any other network controls. [App Service restrictions](https://learn.microsoft.com/en-us/azure/app-service/app-service-ip-restrictions)

Public IP rules cannot override disabled public network access, private-endpoint-only routes, policies, or other enforced boundaries. In those cases require a VPN/private runner and valid DNS/routing. Do not disable firewalls, choose AllowAll, enable trusted-service bypass, set SQL's special 0.0.0.0 rule, or change public access settings as an automatic workaround. [Key Vault network controls](https://learn.microsoft.com/en-us/azure/key-vault/general/network-security)

The deployment machine's IP rules do not provide the web app or worker with runtime connectivity. Their outbound routes and service access must be designed and verified separately. Managed identity authenticates requests but does not bypass firewalls.

## Rule ownership and cleanup

`DEPLOYMENT_ACCESS_LIFETIME=Temporary` means the workflow records and later removes only rules it introduced. `Persistent` retains explicitly configured rules across runs. Reusing an existing equivalent allow rule does not transfer ownership or permit later removal.

Write a network-access journal before mutation and update it after each operation. Record target resource/context, endpoint, rule identifier, exact address/priority, prior state, created-versus-reused status, owning run, and cleanup outcome. Use target locking or explicit conflict detection so concurrent runs cannot remove a rule still in use. Preserve unrelated rules and do not change default actions or SCM inheritance implicitly.

Remove each script's temporary rules in `finally` before it returns, including on failure. The next script obtains and records its own required access. On hard interruption, retain the journal and reconcile it safely when the owning script resumes; temporary metadata does not make these service rules expire automatically. Verify each rule still matches the recorded owned change before removing it.

Provisioning writes the permitted deployment-network policy into the manifest. Deployment can also read the policy from environment configuration when no manifest exists. It may change only those client rules, never create resources or repair identity/database permissions. An optional `-ClientIpv4` overrides the address with a valid public IPv4/32 without expanding allowed targets or changing public access, lifetime, or default actions. ReuseOnly manifests forbid rule changes. Private-mode deployment verifies private reachability and adds no public rules.

Do not publish a successful handoff artifact if required cleanup is unresolved. Record release outcome and cleanup outcome separately so an application can be reported deployed while overall workflow recovery remains pending.

## Commands

```powershell
./scripts/Bootstrap.ps1 -ConfigPath ./config/sandbox.env -WhatIf
./scripts/Bootstrap.ps1 -ConfigPath ./config/sandbox.env
./scripts/Provisioning.ps1 -ConfigPath ./config/sandbox.env
./scripts/Deployment.ps1 -ManifestPath ./path/to/deployment-manifest.json -Target Web -WebArtifactPath ./publish/web.zip
```

See [the handoff contract](environment-to-deployment.md). No separate network-access or cleanup script is required.
