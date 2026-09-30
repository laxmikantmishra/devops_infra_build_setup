Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-TargetResourceGroup { param($Configuration) Get-AzResourceGroup -Name $Configuration.resourceGroup.name -ErrorAction SilentlyContinue }
function Resolve-ResourceGroup {
 [CmdletBinding(SupportsShouldProcess)]param([Parameter(Mandatory)]$Configuration,[switch]$ReuseOnly)
 $desired=$Configuration.resourceGroup;Write-DeploymentStatus -Stage ResourceGroup -Status Read -Message "Retrieving resource group $($desired.name)...";$existing=Get-TargetResourceGroup $Configuration
 if($existing){if($existing.Location -ne $Configuration.location){throw "Resource group '$($desired.name)' is in '$($existing.Location)', expected '$($Configuration.location)'."};Write-DeploymentStatus -Stage ResourceGroup -Status Reuse -Message "Using existing resource group $($desired.name).";return [pscustomobject]@{action='Reuse';resource=$existing;id=$existing.ResourceId;name=$existing.ResourceGroupName;location=$existing.Location}}
 if($desired.mode -eq 'Existing' -or $ReuseOnly){throw "Required resource group '$($desired.name)' does not exist."}
 if($PSCmdlet.ShouldProcess($desired.name,'Create Azure resource group')){Write-DeploymentStatus -Stage ResourceGroup -Status Create -Message ("{0}: {1}..." -f 'Create Azure resource group',$desired.name);$existing=New-AzResourceGroup -Name $desired.name -Location $Configuration.location -Tag $Configuration.tags -Force -ErrorAction Stop;return [pscustomobject]@{action='Create';resource=$existing;id=$existing.ResourceId;name=$existing.ResourceGroupName;location=$existing.Location}}
 [pscustomobject]@{action='Create';resource=$null;id="/subscriptions/$($Configuration.subscriptionId)/resourceGroups/$($desired.name)";name=$desired.name;location=$Configuration.location;preview=$true}
}
Export-ModuleMember -Function Get-TargetResourceGroup,Resolve-ResourceGroup
