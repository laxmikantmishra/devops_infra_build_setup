# Environment configuration

The selected defaults are sandbox in eastus. `APPLICATION_NAME=askey-swarms-sandbox` supplies the application tag; `RESOURCE_NAME_PREFIX=AEY-EU-SWARMS-SANDBOX`, its short variant, and instance `01` define resource naming. See [the naming map](../docs/naming.md) for the Key Vault and VM guest-name exceptions. The explicit resource-name fields already contain the chosen examples; dynamic derivation is future implementation work.

The primary input is `sandbox.env`, copied from `sandbox.env.example`, with `databases.example.json` providing the structured database collection. See [the workflow](../docs/environment-to-deployment.md).

All three scripts can accept this environment input independently. `AUTH_MODE=Interactive` supports environments with no existing deployment SPN. `AUTH_CLIENT_ID` and `AUTH_CERTIFICATE_THUMBPRINT` are optional mode-specific identifiers, not runtime managed-identity settings. Manifest-only Deployment defaults to interactive authentication unless explicit arguments select another mode. See [authentication](../docs/authentication.md).

`MANAGED_IDENTITY_MODE`, `MANAGED_IDENTITY_NAME`, and `MANAGED_IDENTITY_ID` select the shared user-assigned identity for web and worker. Client/principal IDs will be discovered and exported in the manifest. See [managed identity configuration](../docs/managed-identity.md); exact runtime permissions remain to be specified.

Bootstrap uses the explicit `TENANT_ID`, `SUBSCRIPTION_ID`, and resource-group settings. `BOOTSTRAP_REGISTER_PROVIDERS` controls registration of required missing providers. `DEPLOYMENT_NETWORK_MODE`, `DEPLOYMENT_CLIENT_IPV4` (public IPv4/32), `DEPLOYMENT_ACCESS_LIFETIME`, and per-service flags describe deployment-machine access. The blank IP must be supplied before a public access grant. See [bootstrap and network access](../docs/bootstrap-and-network-access.md). No automatic IP detection occurs.

`sandbox.example.json` is a draft for collecting requirements, not a validated deployment configuration. Null values deliberately represent unresolved decisions. No subscription, SQL product, operating system, SKU, or application runtime has been selected.

The JSON example illustrates the normalized configuration shape and may be used as an alternative input in future. Select one input format per run; do not maintain or silently merge two competing configurations. Never put secret values in configuration; use vault secret references. Keep real environment files out of source control.

Resource modes will be:
- `Create`: managed resource, created if absent and reconciled safely on later runs.
- `Existing`: explicit resource ID, read-only during provisioning.
- `Auto`: exact name/type lookup in the target group; reuse if found, create if absent.

App Service Plan, web app, SQL server, each database, and supporting dependencies have separate entries. The worker NIC and OS disk use deterministic supporting-resource names.

The shared foundation work will add `environment.schema.json`, required creation properties, artifact/checksum references, secret references, permission/setting ownership, and script-specific semantic validation. The final schema must reject incomplete creation settings and unknown fields. Do not implement provisioning against this draft alone.
