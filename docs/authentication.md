# Independent authentication and optional app registration

## No existing app registration or service principal

The user confirmed that SPN means a deployment service principal, which may not exist. This is not a prerequisite for interactive local execution: the scripts default to signing in the operator through Azure PowerShell and validating the explicitly selected tenant/subscription. This flow supports the organization's MFA requirements; do not implement username/password automation as a fallback. [Azure PowerShell interactive authentication](https://learn.microsoft.com/en-us/powershell/azure/authenticate-interactive)

Each of the three scripts runs in a fresh PowerShell session. It loads its own internal helpers relative to `$PSScriptRoot`, checks dependencies, authenticates, and returns/passes an explicit process-scoped context. No script depends on another script having imported modules, set globals, signed in, or created a local report.

## Authentication selection

Explicit script arguments override corresponding non-secret configuration values. Otherwise the scripts use `AUTH_MODE` from config; manifest-only execution defaults to Interactive. Manifest files do not contain or select deployment credentials.

| Mode | Behavior and requirements |
| --- | --- |
| Interactive | Operator browser/broker login for the requested tenant/subscription; default; no custom app registration |
| DeviceCode | Explicit alternative interactive login only when permitted by tenant policy |
| ExistingContext | Use an already authenticated session only after checking exact tenant, subscription, account and required access; fail without silently switching or prompting |
| ServicePrincipalCertificate | Optional existing automation identity; requires its application client ID and locally available certificate/private key plus permissions |
| ManagedIdentity | Optional Azure-hosted deployment runner with an assigned identity; unavailable as ordinary laptop authentication |

Reserve `-AuthMode`, `-AuthClientId`, `-CertificateThumbprint`, and `-NonInteractive` consistently on all scripts. NonInteractive prohibits user-login prompts; it fails clearly if selected authentication cannot run unattended. No silent fallback between accounts or modes. Validate mode-specific arguments and do not pass client/certificate fields to a user login.

The `.env` example contains `AUTH_MODE`, `AUTH_CLIENT_ID`, and `AUTH_CERTIFICATE_THUMBPRINT` only. Never store private keys, secrets, refresh tokens, or access tokens in environment config or artifacts. The identity attached to the application VM/web app is a runtime identity, not automatically the account for deployment scripts.

## Microsoft Entra tenant and permissions

An Azure subscription has a relationship with a Microsoft Entra tenant. A missing custom app registration is different from having no authorized access to that tenant/subscription. The scripts cannot bypass a missing tenant login, subscription role, Conditional Access requirement, or directory permission; report the exact prerequisite that prevents the selected operation. [Azure and Entra relationship](https://learn.microsoft.com/en-us/entra/fundamentals/faq)

Do not require Graph directory-read permissions merely to authenticate the operator or provision ordinary Azure resources. Check Azure control-plane permissions, role-assignment rights, SQL Entra bootstrap permissions, and any actual directory operations separately. A resource-group Contributor is not automatically a directory application administrator or a role-assignment administrator.

Managed identity creation produces an Azure-managed service principal; it does not require creating a separate custom app registration. Preserve this distinction when validating prerequisites. [Application objects and managed-identity service principals](https://learn.microsoft.com/en-us/entra/identity-platform/app-objects-and-service-principals)

## When app registration is needed

App registration is optional for the current interactive operator + runtime managed identity design. Consider it only for an explicitly selected automation identity, application user sign-in/API OAuth, or another requirement that actually needs an application object.

Before implementing registration, record purpose, application type, supported tenant/account types, required redirect URIs, exact API scopes/app roles, credential method, ownership and consent requirements. Keep an application-login registration separate from a deployment automation registration and from runtime managed identity. Directory objects belong to the tenant, not the application's resource group.

If the required registration does not exist, Bootstrap can gain an explicitly configured create/reuse capability using appropriate PowerShell/Graph commands in a later implementation. Creation requires the caller's directory rights, and admin consent may require another authorized administrator. Missing directory rights must not block unrelated interactive Azure work, but must block the specific feature that needs them. Never silently create an application, grant broad Graph permissions, auto-consent, or replace credentials on a reused registration. Prefer a supported federated/certificate setup for automation; reference credentials securely if any are required.

The user-invoked [entra-app-registration skill](/Users/laxmikantmishra/.agents/skills/entra-app-registration/SKILL.md) informs these registration guidelines. The user requirement for PowerShell and no Bicep continues to apply.

The scripts implement authentication but never create an app registration. No Azure authentication or app-registration operation was performed in this repository session.
