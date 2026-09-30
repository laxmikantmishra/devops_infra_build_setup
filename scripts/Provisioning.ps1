#Requires -Version 7.0
<#
.SYNOPSIS
Create or reuse application resources, configure access and export a deployment manifest.
.DESCRIPTION
Creates or reuses the configured resources, applies managed identity access, and
exports a non-secret deployment manifest.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $ConfigPath,

    [ValidateNotNullOrEmpty()]
    [string] $BootstrapPath,

    [switch] $ReuseOnly,

    [ValidateSet('Interactive', 'DeviceCode', 'ExistingContext', 'ServicePrincipalCertificate', 'ManagedIdentity')]
    [string] $AuthMode,

    [string] $AuthClientId,

    [string] $CertificateThumbprint,

    [switch] $NonInteractive,

    [pscredential] $SqlAdministratorCredential,

    [pscredential] $VmAdministratorCredential,

    [string] $OutputDirectory = '.artifacts'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modules=Join-Path $PSScriptRoot 'modules'
foreach($name in 'Common','Configuration','Authentication','Prerequisites','Planning','NetworkAccess','DeploymentManifest','Verification','resources/ResourceGroup','resources/ManagedIdentity','resources/Network','resources/Monitoring','resources/KeyVault','resources/DeploymentStorage','resources/SqlServer','resources/SqlDatabases','resources/AppService','resources/WorkerVm','Infrastructure','AccessAndConfiguration'){Import-Module (Join-Path $modules "$name.psm1") -Force -ErrorAction Stop}
$run=$null;$networkAccess=$null;$bootstrap=$null
try {
    $configuration=Import-EnvironmentConfiguration -Path $ConfigPath
    $null=Test-EnvironmentConfiguration -Configuration $configuration -Operation Provisioning -ReuseOnly:$ReuseOnly
    if ((Get-SqlAuthenticationMode $configuration) -eq 'Sql' -and -not $SqlAdministratorCredential -and -not $WhatIfPreference) { throw 'SqlAdministratorCredential is required for SQL-authenticated provisioning readiness checks, including ReuseOnly. Supply a PSCredential; do not put passwords in configuration.' }
    $run=New-RunContext -Environment $configuration.environment -Operation Provisioning -OutputDirectory $OutputDirectory -WhatIf:$WhatIfPreference
    $null=Connect-DeploymentAzure -Configuration $configuration -AuthMode $AuthMode -AuthClientId $AuthClientId -CertificateThumbprint $CertificateThumbprint -NonInteractive:$NonInteractive
    $readiness=Test-SubscriptionReadiness -Configuration $configuration -Operation Provisioning
    $missing=@($readiness.providers|Where-Object registrationState -ne 'Registered');if($missing){throw "Required Azure providers are not registered: $($missing.namespace -join ', '). Run Bootstrap.ps1 first."}
    if(Test-StringPresent $BootstrapPath){$resolvedBootstrapPath=(Resolve-Path -LiteralPath $BootstrapPath).Path;$bootstrap=ConvertTo-PlainHashtable (Get-Content -LiteralPath $resolvedBootstrapPath -Raw|ConvertFrom-Json -Depth 50);if($bootstrap.schemaVersion -ne '1.0' -or $bootstrap.artifactType -ne 'bootstrap' -or $bootstrap.status -ne 'Ready' -or $bootstrap.subscriptionId -ne $configuration.subscriptionId -or $bootstrap.tenantId -ne $configuration.tenantId){throw 'Bootstrap artifact is not a ready schema 1.0 bootstrap artifact or does not match the configured tenant/subscription.'};if($bootstrap.resourceGroup.name -ne $configuration.resourceGroup.name -or $bootstrap.managedIdentity.name -ne $configuration.resources.managedIdentity.name){throw 'Bootstrap artifact resource group or managed identity does not match configuration.'}}
    $plan=New-ProvisioningPlan -Configuration $configuration -ReuseOnly:$ReuseOnly
    foreach($step in $plan){Add-RunEvent $run Plan "$($step.intent): $($step.step)"}
    if($WhatIfPreference){$null=Complete-RunReport -RunContext $run -Status Preview;return [pscustomobject]@{Status='Preview';Plan=$plan;ArtifactPath=$null;RunDirectory=$run.Directory}}
    $resources=Invoke-InfrastructureWorkflow -Configuration $configuration -RunContext $run -ReuseOnly:$ReuseOnly -SqlAdministratorCredential $SqlAdministratorCredential -VmAdministratorCredential $VmAdministratorCredential
    if($bootstrap -and ($bootstrap.resourceGroup.resourceId -ne $resources.resourceGroup.id -or $bootstrap.managedIdentity.resourceId -ne $resources.managedIdentity.id)){throw 'Bootstrap artifact resource IDs no longer match live Azure state.'}
    $networkAccess=Open-DeploymentNetworkAccess -Configuration $configuration -ResolvedResources $resources -RunContext $run -AllowChanges:(-not $ReuseOnly)
    try {
        $access=Invoke-AccessAndConfiguration -Configuration $configuration -Resources $resources -ReuseOnly:$ReuseOnly
        $verification=Test-ProvisionedInfrastructure -Configuration $configuration -Resources $resources -SqlAdministratorCredential $SqlAdministratorCredential
    } finally {
        Close-DeploymentNetworkAccess -Configuration $configuration -NetworkAccess $networkAccess -ResolvedResources $resources
        $networkAccess=$null
    }
    $provenance=Get-ConfigurationProvenance -Configuration $configuration -ScriptsRoot $PSScriptRoot
    if($bootstrap){$provenance.bootstrapPath=$resolvedBootstrapPath;$provenance.bootstrapSha256=Get-FileSha256 $resolvedBootstrapPath;$provenance.bootstrapRunId=$bootstrap.runId}
    $manifest=New-DeploymentManifest -Configuration $configuration -Resources $resources -RunContext $run -Provenance $provenance -ReuseOnly:$ReuseOnly -Verification $verification
    $path=Join-Path $run.Directory 'deployment-manifest.json';Write-JsonFileAtomic -Path $path -InputObject $manifest
    Add-RunEvent $run Success "Deployment manifest written to $path.";$null=Complete-RunReport -RunContext $run -Status Succeeded
    [pscustomobject]@{Status='Succeeded';ArtifactPath=$path;RunDirectory=$run.Directory}
} catch {
    if($run){Add-RunEvent $run Error $_.Exception.Message;$null=Complete-RunReport -RunContext $run -Status Failed -ErrorMessage $_.Exception.Message}
    throw
}
