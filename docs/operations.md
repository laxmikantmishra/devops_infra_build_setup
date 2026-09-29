# Operations

Use [the sandbox execution runbook](runbook.md) for the step-by-step commands and required configuration.

## Current status

There are exactly three operator scripts: `Bootstrap.ps1`, `Provisioning.ps1`, and `Deployment.ps1`. Their authentication, provisioning, firewall, manifest, and release modules are implemented. Local unit/static validation has passed; no live Azure execution has been performed in this repository session.

## Independent commands

1. Bootstrap accepts the environment file and produces a validated bootstrap artifact.
2. Provisioning accepts an environment file, optionally a bootstrap artifact, and resolves live prerequisites before creating/reusing application resources and exporting a manifest.
3. Deployment accepts an environment file OR a manifest plus local build packages, validates existing targets and produces a release report.

Each command authenticates in its own process and may be run without any prior script output. No existing deployment SPN is required for the default interactive login. Missing Azure prerequisites still fail with actionable errors. Deployment can run alone against existing resources even on its first invocation. Fully existing infrastructure uses Provisioning with `-ReuseOnly` to validate and export without changing infrastructure or access. See [the full contract](environment-to-deployment.md).

Each script owns validation, discovery/planning where needed, verification, and cleanup for its work. Per-script temporary network grants are removed before return. Persistent configured grants remain. On hard interruption, retain the journal; rerunning the owning script must reconcile its unfinished journal safely before adding new grants. No separate network-access command is required.

Cleanup must never remove unrelated/preexisting rules or another active run's grants. Record failed cleanup separately from deployment success and do not discard the journal. A manifest from a previous run requires live context/resource/reachability validation.

## Operational coverage

- Pinned tools, explicit authentication/context, and permission requirements.
- Three-command examples for empty, partial, and fully existing environments.
- Bootstrap/manifest validation and current deployment-client IP changes.
- Artifact preparation, migration compatibility, worker health/recovery, and web rollback.
- Per-run plans, reports, and journals under `.artifacts/<environment>/<run-id>/`.
- Safe repeat/resume behavior, interrupted-run access cleanup, and database recovery.

The exact tested tool versions are recorded in [tool-versions.md](tool-versions.md). Live smoke tests require the tenant/subscription and application packages that are still pending.
