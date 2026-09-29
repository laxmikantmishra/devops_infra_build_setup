# Environment input and three-script artifact handoff

```text
config/sandbox.env ──→ Bootstrap.ps1 ──→ bootstrap.json
config/sandbox.env ──→ Provisioning.ps1 ──→ deployment-manifest.json
config/sandbox.env OR deployment-manifest.json
               + local packages ──→ Deployment.ps1 ──→ release-report.json
```

These are independent commands, each with its own configuration loading, tool/context checks and authentication. No script invokes another entry script or depends on its in-memory state. Earlier outputs are optional handoffs, not mandatory prerequisites. Actual Azure prerequisites must still exist for the requested operation.

Interactive operator login is the default, so an existing deployment SPN is not required. Optional certificate/SPN authentication and other modes are documented in [authentication](authentication.md).

## 1. Bootstrap

`Bootstrap.ps1 -ConfigPath ...` parses the environment file, checks tools/authentication/target context and prerequisites, discovers existing bootstrap resources, and builds its change plan. It then registers only required missing providers and resolves/creates the target group and shared user-assigned identity.

It validates the deployment IP/private-route settings and may establish narrowly configured access to existing dependencies needed during bootstrap. New application resources do not yet have firewalls to update; their rules are handled by Provisioning after creation. Bootstrap cleans up its own temporary grants before returning.

Write `.artifacts/<environment>/<run-id>/bootstrap.json` with version/status, tenant/subscription/group and identity IDs, configuration/dependency-file/script hashes, provider results, timestamps, and checks. Partial results remain reports and cannot be accepted as a successful bootstrap artifact. Never export credentials.

## 2. Provisioning

`Provisioning.ps1 -ConfigPath ...` resolves its prerequisites directly from configuration and live Azure state. `-BootstrapPath` is optional; if supplied, validate the artifact against both rather than ignoring mismatches. Required provider registrations, the resource group, and shared identity must already exist, whether created manually or by Bootstrap; report missing prerequisites without invoking Bootstrap. It discovers and plans application resources, applies Create/Existing/Auto rules, configures the explicitly selected network access and shared identity bindings, and verifies readiness. Planning is internal; there is no separate Plan command or required external plan file.

`-ReuseOnly` forbids resource creation, resource configuration changes, role/database grants, and firewall mutations. It validates supplied existing resources and exports a manifest only when their prerequisites and current connectivity are sufficient. The normal workflow creates only missing resources and applies authorized managed/configuration changes.

Write `.artifacts/<environment>/<run-id>/deployment-manifest.json` atomically after resolution and readiness checks succeed. Include resolved resource IDs, non-secret endpoints, database mapping, runtime identity IDs, optional bootstrap provenance, per-target readiness, and the allowed deployment-client access policy. Remove owned temporary rules before the script exits and record cleanup. Readiness describes the time of validation, not a promise that temporary access remains open.

See [the draft manifest](examples/deployment-manifest.example.json); `ExampleOnly`, unresolved IDs, or failed readiness must be rejected. Deployment can use this manifest without the original `.env` file, or resolve existing targets directly from a supplied environment file without any prior output artifact.

## 3. Deployment

`Deployment.ps1` accepts exactly one of `-ConfigPath` or `-ManifestPath`, plus selected local application packages. Configuration mode resolves existing targets by exact resource IDs/names and performs the same live readiness checks as manifest mode. It never creates resources even if a config resource mode is Create or Auto. Manifest mode validates schema/status and resource references without requiring the environment file. `-Target` selects Web, Worker, Database, or All. Web/Worker require their respective package path; Database requires an explicit migration artifact. All deploys web and worker and includes database migrations only when `-DatabaseArtifactPath` is supplied. Reject unrelated package arguments and missing selected packages before any Azure write.

The script authenticates as the local deployment operator, verifies context and live resources/identity bindings, checks package versions/checksums, and confirms private connectivity or reconciles only the deployment-client IP rules explicitly authorized in the selected configuration or manifest. `-ClientIpv4` may supply the current public egress IPv4/32; it does not change allowed targets, network mode, or public-access settings. Without an override, use the selected input's configured client address and verify reachability.

Deploy selected artifacts in the compatible migration/web/worker order, verify the release, clean up owned temporary IP rules in `finally`, and write `.artifacts/<environment>/<run-id>/release-report.json`. Record failures and pending cleanup truthfully. Do not create missing infrastructure, change runtime permissions, or silently select another target group. A release can run this script alone even if neither of the other scripts has ever been run, provided its target infrastructure/configuration already exists.

## Configuration parsing

Use `config/sandbox.env.example` as the primary input pattern. `DATABASES_FILE` references a structured collection relative to the env file. The example remains incomplete until SQL product, sizing, networking, and runtimes are decided.

Parse one KEY=VALUE per line, blank lines, full-line comments, and optional matching outer quotes. Split on the first equals sign; reject unknown/duplicate keys and malformed lines. Never execute/dot-source input, expand variables, or silently merge process environment values. Normalize into a versioned validated configuration object. JSON may be an alternative input, selected explicitly for that run.

## Artifact rules

Keep desired configuration, observed resource manifests, and local application packages separate. Export no passwords, tokens, publish profiles, credential-bearing connection strings, or signed URLs. Include hashes for all referenced input files, not just the top-level `.env`. Treat generated artifacts as untrusted input: validate schema/status, context, IDs, and allowed actions before use.

Validate only the fields and permissions needed by the selected script/target. Bootstrap must not require web packages, final SQL grants or VM runtime choices it does not use; Deployment must not demand creation-only SKU/image settings for existing targets. Resolve references needed for selected targets without reading irrelevant files. Every script produces internal sanitized plans/reports and access journals. None of the successful handoff artifacts grants authentication or guarantees current reachability. `-WhatIf` must perform no Azure, guest, or database mutations and must not emit a successful handoff artifact.

See [bootstrap and network details](bootstrap-and-network-access.md) and [the README commands](../README.md).
