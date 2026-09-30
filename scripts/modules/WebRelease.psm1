Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Publish-WebRelease {
    [CmdletBinding(SupportsShouldProcess)]param($Configuration,$Resources,[Parameter(Mandatory)][string]$ArtifactPath)
    Import-Module Az.Websites -ErrorAction Stop
    $path=(Resolve-Path -LiteralPath $ArtifactPath -ErrorAction Stop).Path
    if([IO.Path]::GetExtension($path) -ne '.zip'){throw 'WebArtifactPath must be a .zip package.'}
    $hash=Get-FileSha256 $path
    if($PSCmdlet.ShouldProcess($Resources.appService.webApp.name,"Deploy web package $path")){Write-DeploymentStatus -Stage WebRelease -Status Update -Message ("{0}: {1}..." -f "Deploy web package $path",$Resources.appService.webApp.name);Publish-AzWebApp -ResourceGroupName $Configuration.resourceGroup.name -Name $Resources.appService.webApp.name -ArchivePath $path -Force -ErrorAction Stop|Out-Null}
    [pscustomobject]@{target='Web';artifactPath=$path;sha256=$hash;resourceId=$Resources.appService.webApp.id;status=if($WhatIfPreference){'Preview'}else{'Deployed'}}
}
Export-ModuleMember -Function Publish-WebRelease
