# Sandbox resource naming and location

The selected application identifier is `askey-swarms-sandbox`. Azure resource names use the requested abbreviated prefix `AEY-EU-SWARMS-SANDBOX` and a two-digit instance suffix, initially `01`. Keep the long application identifier in the application tag. This interpretation follows the user's explicit resource-name example.

All regional application resources, including the group, identity, App Service Plan, worker VM, SQL hosting, vault, workspace, and Application Insights, must use `eastus`. `EU` is the user-provided naming token; never infer a Europe region from it. Child resources inherit their parent's region where appropriate; genuinely global resource types retain their required scope/location.

## Selected names

| Resource | Type key | Name |
| --- | --- | --- |
| Resource group | RG | `AEY-EU-SWARMS-SANDBOX-RG-01` |
| Shared user-assigned identity | UAMI | `AEY-EU-SWARMS-SANDBOX-UAMI-01` |
| App Service Plan | ASP | `AEY-EU-SWARMS-SANDBOX-ASP-01` |
| Web app | APP | `aey-eu-swarms-sandbox-app-01` |
| Worker VM resource | VM | `AEY-EU-SWARMS-SANDBOX-VM-01` |
| Worker guest computer name | Compact hostname | `AEYEUSWRMSBX01` |
| SQL logical server, if selected | SQL | `aey-eu-swarms-sandbox-sql-01` |
| Primary database example | DB-PRIMARY | `AEY-EU-SWARMS-SANDBOX-DB-PRIMARY-01` |
| Secondary database example | DB-SECONDARY | `AEY-EU-SWARMS-SANDBOX-DB-SECONDARY-01` |
| Application Insights | AI | `AEY-EU-SWARMS-SANDBOX-AI-01` |
| Log Analytics workspace | LAW | `AEY-EU-SWARMS-SANDBOX-LAW-01` |
| Key Vault | KV | `aey-eu-swarms-sbx-kv-01` |
| Virtual network | VNET | `AEY-EU-SWARMS-SANDBOX-VNET-01` |
| Deployment artifact Storage account | ST | `aeyeuswarmssbxst01` |
| Worker network interface | NIC | `AEY-EU-SWARMS-SANDBOX-NIC-01` |
| Worker OS disk | OSDISK | `AEY-EU-SWARMS-SANDBOX-OSDISK-01` |
| Worker NAT gateway | NAT | `AEY-EU-SWARMS-SANDBOX-NAT-01` |
| Worker NAT public IP | PIP-NAT | `AEY-EU-SWARMS-SANDBOX-PIP-NAT-01` |
| SQL app-subnet rule | SQLVNET-APP | `AEY-EU-SWARMS-SANDBOX-SQLVNET-APP-01` |
| SQL worker-subnet rule | SQLVNET-WORKER | `AEY-EU-SWARMS-SANDBOX-SQLVNET-WORKER-01` |

For supporting resources, use distinct keys such as `NSG`, `NIC`, `OSDISK`, `DATADISK`, and `SNET-WORKER`, preserving the final `-01`. Private endpoints can use `PE-KV` or `PE-SQL`. These are naming guidelines, not instructions to create extra resources. Required platform names, such as private DNS zones or reserved subnet names, must retain their service-defined names.

## Service-specific adaptations

Use uppercase for readable resource names where allowed. Use lowercase for SQL server names and consistently for DNS-facing app/vault names. Key Vault permits at most 24 characters; the shortened `SBX` form above is 23. Keep the full VM resource name distinct from its 14-character guest hostname, which fits the Windows 15-character limit. [Azure naming rules](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules)

## Resolution and validation

- Keep prefix, short prefix and sequence in configuration. The explicit names in the example show the intended results. A future common naming helper can derive omitted names; do not independently invent names in each script.
- Explicit existing resource IDs take precedence. Resolve and preserve their actual names, including database names and VM computer names. Report naming deviations rather than attempting to rename resources or databases. If an explicitly supplied name contradicts its ID, fail validation.
- Auto lookup uses the exact configured/derived name and resource type within the selected group. It must not adopt a globally visible resource or fall back to fuzzy matching.
- Validate per-service length, character, reserved-word and uniqueness constraints before writes. Check web app, vault and SQL server name availability through the supported Azure mechanisms. No names have been reserved or checked for availability yet.
- On a global-name collision, report the conflict and allow an explicit per-resource name/instance override. Do not add random suffixes or increment the sequence silently; independent scripts must resolve the same target on every run. Changing a naming prefix alone never authorizes resource replacement.
- Validate `eastus` against each resolved regional resource and selected SKU. Report existing resources in other regions as conflicts; do not move/recreate them or choose another region automatically. A resource group's location alone does not set the location of its resources.
- Export actual resolved names, IDs, locations and VM hostname in the deployment manifest. Deployment must use validated observed targets rather than regenerate names from a previous convention.
- The two database names are examples until the application's actual database map is supplied. Do not rename existing databases to match these samples.

The configuration and scripts apply these names. Global-name availability is validated by Azure during provisioning; conflicts require an explicit override.

### Comparing reported locations

Azure cmdlets can return a location display name such as `East US` or its programmatic identifier `eastus`. Resource validation uses the shared `Test-AzureLocationMatch` helper to ignore case and whitespace when comparing these forms. Authored configuration remains `LOCATION=eastus`; resource output values are preserved. Digits and punctuation are not removed, and missing locations never match. `East US 2`, `West US`, and `global` do not match `eastus`. No resource move, replacement, or region fallback is performed. See [Microsoft's region names](https://learn.microsoft.com/azure/reliability/regions-list).
