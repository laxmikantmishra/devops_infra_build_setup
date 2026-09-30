# Decisions

## Confirmed

- SQL product: Azure SQL Database on a logical server, with SQL username/password authentication (`SQL_AUTHENTICATION_MODE=Sql`). No Entra SQL administrator is required for this mode.

- Environment: sandbox. Azure region: eastus for all regional application resources.
- Application identifier/tag: askey-swarms-sandbox. Resource naming prefix: AEY-EU-SWARMS-SANDBOX, instance 01; retain EU as the requested naming token. Shorten SANDBOX to SBX where required by service limits and use a separate compact VM guest hostname.
- Use PowerShell and Az modules; no Bicep.
- Use one shared user-assigned runtime managed identity per environment, attached to App Service and the worker VM, with explicit access to their dependencies. Keep local deployment/bootstrap credentials separate.
- Bootstrap prerequisite resources in the explicitly configured subscription. Support explicit deployment-client IP allowlisting for selected endpoints, with recorded ownership and cleanup for temporary rules.
- Keep application infrastructure and dependencies in one configured resource group per environment.
- Expose exactly three operator scripts: Bootstrap.ps1, Provisioning.ps1, and Deployment.ps1. Discovery, planning, network access, configuration, verification, and cleanup are internal steps.
- Each script is invoked independently in a fresh session; earlier output artifacts are optional. Provisioning accepts configuration alone, and Deployment accepts either configuration or a manifest without invoking other scripts.
- An existing deployment SPN may not be available. Default to interactive operator authentication; SPN/certificate authentication is optional. Do not require or automatically create a custom app registration for login.
- Support new, partially existing, and fully existing infrastructure.
- Implement the workflow in the three phases while keeping each public script independently invokable.
- Use an environment-style input file for infrastructure settings and generate a non-secret JSON deployment manifest for subsequent local code deployment. A separate JSON collection describes multiple databases.

## Pending

| Decision | Status |
| --- | --- |
| Tenant and subscription IDs | Not provided; region and resource-group name are now configured |
| Existing resource IDs and allowed changes | Not provided |
| Web application stack, build process, runtime, OS | Not provided |
| Worker OS, runtime, service installation, shutdown behavior | Not provided |
| Database names, tiers, migration tooling, runtime credential retrieval | Not provided; SQL username/password authentication selected |
| Runtime SQL grants, vault authorization model, telemetry authentication support | To be verified for the selected application/runtime |
| Networking and deployment runner reachability | Not provided |
| Deployment public egress IPv4/32 or private route, IP-rule lifetime | Actual address/route not provided; draft defaults to temporary public allowlisting |
| Artifact location, versioning, checksums | Not provided |
| Availability, downtime, recovery, retention, budget | Not provided |
| Local execution vs CI/CD and deployment identity | Not provided |

Resolve these values in the environment file before executing the dependent workflow. The implementation validates supported choices and stops before Azure mutations when required values are absent.
