#Requires -Version 7.0
<#
.SYNOPSIS
Prepare the selected Azure subscription, resource group and shared identity.
.DESCRIPTION
Validates the target context, registers required providers, and resolves or creates
the resource group and shared user-assigned managed identity.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $ConfigPath,

    [ValidateSet('Interactive', 'DeviceCode', 'ExistingContext', 'ServicePrincipalCertificate', 'ManagedIdentity')]
    [string] $AuthMode,

    [string] $AuthClientId,

    [string] $CertificateThumbprint,

    [switch] $NonInteractive,

    [string] $OutputDirectory = '.artifacts'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modules=Join-Path $PSScriptRoot 'modules'
foreach($name in 'Common','Configuration','Authentication','Prerequisites','resources/ResourceGroup','resources/ManagedIdentity','Bootstrap'){Import-Module (Join-Path $modules "$name.psm1") -Force -ErrorAction Stop}
$run=$null
try {
    $configuration=Import-EnvironmentConfiguration -Path $ConfigPath
    $null=Test-EnvironmentConfiguration -Configuration $configuration -Operation Bootstrap
    $run=New-RunContext -Environment $configuration.environment -Operation Bootstrap -OutputDirectory $OutputDirectory -WhatIf:$WhatIfPreference
    Add-RunEvent $run Info "Authenticating to subscription $($configuration.subscriptionId)."
    $null=Connect-DeploymentAzure -Configuration $configuration -AuthMode $AuthMode -AuthClientId $AuthClientId -CertificateThumbprint $CertificateThumbprint -NonInteractive:$NonInteractive
    $null=Test-SubscriptionReadiness -Configuration $configuration -Operation Bootstrap
    $provenance=Get-ConfigurationProvenance -Configuration $configuration -ScriptsRoot $PSScriptRoot
    $artifact=Invoke-BootstrapWorkflow -Configuration $configuration -RunContext $run -Provenance $provenance -WhatIf:$WhatIfPreference
    $path=Join-Path $run.Directory 'bootstrap.json'
    if(-not $WhatIfPreference){Write-JsonFileAtomic -Path $path -InputObject $artifact;Add-RunEvent $run Success "Bootstrap artifact written to $path."}else{Add-RunEvent $run Plan 'Bootstrap preview completed; no artifact was published.'}
    $null=Complete-RunReport -RunContext $run -Status $(if($WhatIfPreference){'Preview'}else{'Succeeded'})
    [pscustomobject]@{Status=if($WhatIfPreference){'Preview'}else{'Succeeded'};ArtifactPath=if($WhatIfPreference){$null}else{$path};RunDirectory=$run.Directory}
} catch {
    if($run){Add-RunEvent $run Error $_.Exception.Message;$null=Complete-RunReport -RunContext $run -Status Failed -ErrorMessage $_.Exception.Message}
    throw
}
