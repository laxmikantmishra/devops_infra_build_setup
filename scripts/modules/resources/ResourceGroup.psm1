Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-TargetResourceGroup { param($Configuration) Get-AzResourceGroup -Name $Configuration.resourceGroup.name -ErrorAction SilentlyContinue }
function Resolve-ResourceGroup {
 [CmdletBinding(SupportsShouldProcess)]param([Parameter(Mandatory)]$Configuration,[switch]$ReuseOnly)
 $desired=$Configuration.resourceGroup;$existing=Get-TargetResourceGroup $Configuration
 if($existing){if($existing.Location -ne $Configuration.location){throw "Resource group '$($desired.name)' is in '$($existing.Location)', expected '$($Configuration.location)'."};return [pscustomobject]@{action='Reuse';resource=$existing;id=$existing.ResourceId;name=$existing.ResourceGroupName;location=$existing.Location}}
 if($desired.mode -eq 'Existing' -or $ReuseOnly){throw "Required resource group '$($desired.name)' does not exist."}
 if($PSCmdlet.ShouldProcess($desired.name,'Create Azure resource group')){$existing=New-AzResourceGroup -Name $desired.name -Location $Configuration.location -Tag $Configuration.tags -Force -ErrorAction Stop;return [pscustomobject]@{action='Create';resource=$existing;id=$existing.ResourceId;name=$existing.ResourceGroupName;location=$existing.Location}}
 [pscustomobject]@{action='Create';resource=$null;id="/subscriptions/$($Configuration.subscriptionId)/resourceGroups/$($desired.name)";name=$desired.name;location=$Configuration.location;preview=$true}
}
Export-ModuleMember -Function Get-TargetResourceGroup,Resolve-ResourceGroup
