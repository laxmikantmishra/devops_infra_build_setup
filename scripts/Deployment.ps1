#Requires -Version 7.0
<#
.SYNOPSIS
Deploy local artifacts to existing resources resolved from configuration or a manifest.
.DESCRIPTION
Deploys selected local artifacts to existing resources. It never provisions
application infrastructure.
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Configuration')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Configuration')]
    [ValidateNotNullOrEmpty()]
    [string] $ConfigPath,

    [Parameter(Mandatory, ParameterSetName = 'Manifest')]
    [ValidateNotNullOrEmpty()]
    [string] $ManifestPath,

    [ValidateSet('Web', 'Worker', 'Database', 'All')]
    [string] $Target = 'All',

    [string] $WebArtifactPath,

    [string] $WorkerArtifactPath,

    [string] $DatabaseArtifactPath,

    [string] $ClientIpv4,

    [ValidateSet('Interactive', 'DeviceCode', 'ExistingContext', 'ServicePrincipalCertificate', 'ManagedIdentity')]
    [string] $AuthMode,

    [string] $AuthClientId,

    [string] $CertificateThumbprint,

    [switch] $NonInteractive,

    [pscredential] $DatabaseCredential,

    [string] $OutputDirectory = '.artifacts'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modules=Join-Path $PSScriptRoot 'modules'
foreach($name in 'Common','Configuration','DeploymentManifest','Authentication','Prerequisites','Discovery','NetworkAccess','WebRelease','WorkerRelease','DatabaseRelease','Verification'){Import-Module (Join-Path $modules "$name.psm1") -Force -ErrorAction Stop}

$needWeb=$Target -in 'Web','All';$needWorker=$Target -in 'Worker','All';$needDatabase=$Target -eq 'Database' -or ($Target -eq 'All' -and (Test-StringPresent $DatabaseArtifactPath))
if($needWeb -and -not(Test-StringPresent $WebArtifactPath)){throw 'WebArtifactPath is required for Web and All deployments.'}
if($needWorker -and -not(Test-StringPresent $WorkerArtifactPath)){throw 'WorkerArtifactPath is required for Worker and All deployments.'}
if($Target -eq 'Database' -and -not(Test-StringPresent $DatabaseArtifactPath)){throw 'DatabaseArtifactPath is required for Database deployments.'}
if(-not $needWeb -and (Test-StringPresent $WebArtifactPath)){throw 'WebArtifactPath is not valid for the selected target.'}
if(-not $needWorker -and (Test-StringPresent $WorkerArtifactPath)){throw 'WorkerArtifactPath is not valid for the selected target.'}
if(-not $needDatabase -and (Test-StringPresent $DatabaseArtifactPath)){throw 'DatabaseArtifactPath is not valid for the selected target.'}
foreach($path in @($WebArtifactPath,$WorkerArtifactPath,$DatabaseArtifactPath)|Where-Object{Test-StringPresent $_}){if(-not(Test-Path -LiteralPath $path)){throw "Artifact path not found: $path"}}

$run=$null;$networkAccess=$null;$resources=$null
try {
    if($PSCmdlet.ParameterSetName -eq 'Manifest'){$manifest=Import-DeploymentManifest -Path $ManifestPath;$configuration=Convert-ManifestToConfiguration $manifest;$inputHash=$manifest._sourceSha256;$inputProvenance=[ordered]@{manifestPath=$manifest._sourcePath;manifestSha256=$inputHash}}else{$configuration=Import-EnvironmentConfiguration -Path $ConfigPath;$null=Test-EnvironmentConfiguration -Configuration $configuration -Operation Deployment -Target $Target;$inputProvenance=Get-ConfigurationProvenance -Configuration $configuration -ScriptsRoot $PSScriptRoot;$inputHash=$inputProvenance.sourceSha256}
    $null=Test-DeploymentTargetConfiguration -Configuration $configuration -Target $Target
    $run=New-RunContext -Environment $configuration.environment -Operation Deployment -OutputDirectory $OutputDirectory -WhatIf:$WhatIfPreference
    $null=Connect-DeploymentAzure -Configuration $configuration -AuthMode $AuthMode -AuthClientId $AuthClientId -CertificateThumbprint $CertificateThumbprint -NonInteractive:$NonInteractive
    $null=Test-SubscriptionReadiness -Configuration $configuration -Operation Deployment
    if($PSCmdlet.ParameterSetName -eq 'Manifest'){$null=Test-ManifestResourcesLive -Manifest $manifest -Target $Target -IncludeDatabase:$needDatabase;$resources=Convert-ManifestToResolvedResources $manifest}else{$resources=Resolve-ExistingInfrastructure -Configuration $configuration -Target $Target -IncludeDatabase:$needDatabase}
    $allowChanges=if($PSCmdlet.ParameterSetName -eq 'Manifest'){[bool]$manifest.deploymentNetwork.allowRuleChanges}else{$true}
    $configuration.deploymentNetwork.targets.sql=[bool]($configuration.deploymentNetwork.targets.sql -and $needDatabase)
    $configuration.deploymentNetwork.targets.keyVault=$false
    $configuration.deploymentNetwork.targets.appServiceScm=[bool]($configuration.deploymentNetwork.targets.appServiceScm -and $needWeb)
    $configuration.deploymentNetwork.targets.appServiceMain=[bool]($configuration.deploymentNetwork.targets.appServiceMain -and $needWeb)
    $networkAccess=Open-DeploymentNetworkAccess -Configuration $configuration -ResolvedResources $resources -RunContext $run -ClientIpv4 $ClientIpv4 -AllowChanges:$allowChanges -WhatIf:$WhatIfPreference
    try {
        $releases=[Collections.Generic.List[object]]::new();$health=@()
        if($needDatabase){$releases.Add((Publish-DatabaseRelease -Configuration $configuration -Resources $resources -ArtifactPath $DatabaseArtifactPath -DatabaseCredential $DatabaseCredential -WhatIf:$WhatIfPreference))}
        if($needWeb){$releases.Add((Publish-WebRelease -Configuration $configuration -Resources $resources -ArtifactPath $WebArtifactPath -WhatIf:$WhatIfPreference));if(-not $WhatIfPreference){$health+=Test-WebReleaseHealth -Configuration $configuration -Resources $resources}}
        if($needWorker){$releases.Add((Publish-WorkerRelease -Configuration $configuration -Resources $resources -ArtifactPath $WorkerArtifactPath -GuestScriptsRoot (Join-Path $PSScriptRoot 'guest') -WhatIf:$WhatIfPreference))}
    } finally {
        Close-DeploymentNetworkAccess -Configuration $configuration -NetworkAccess $networkAccess -ResolvedResources $resources -WhatIf:$WhatIfPreference
        $networkAccess=$null
    }
    $report=[ordered]@{schemaVersion='1.0';artifactType='release-report';status=if($WhatIfPreference){'Preview'}else{'Succeeded'};runId=$run.RunId;generatedAtUtc=(Get-Date).ToUniversalTime().ToString('o');environment=$configuration.environment;tenantId=$configuration.tenantId;subscriptionId=$configuration.subscriptionId;target=$Target;inputSha256=$inputHash;inputProvenance=$inputProvenance;releases=@($releases);health=$health}
    $path=Join-Path $run.Directory 'release-report.json';if(-not $WhatIfPreference){Write-JsonFileAtomic -Path $path -InputObject $report;Add-RunEvent $run Success "Release report written to $path."}
    $null=Complete-RunReport -RunContext $run -Status $report.status
    [pscustomobject]@{Status=$report.status;ArtifactPath=if($WhatIfPreference){$null}else{$path};RunDirectory=$run.Directory}
} catch {
    if($run){
        Add-RunEvent $run Error $_.Exception.Message
        if(-not $WhatIfPreference){$failed=[ordered]@{schemaVersion='1.0';artifactType='release-report';status='Failed';runId=$run.RunId;generatedAtUtc=(Get-Date).ToUniversalTime().ToString('o');environment=$run.Environment;target=$Target;error=$_.Exception.Message};Write-JsonFileAtomic -Path (Join-Path $run.Directory 'release-report.json') -InputObject $failed}
        $null=Complete-RunReport -RunContext $run -Status Failed -ErrorMessage $_.Exception.Message
    }
    throw
}
