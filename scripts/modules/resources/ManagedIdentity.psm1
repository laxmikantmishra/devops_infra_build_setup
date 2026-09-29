Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-TargetManagedIdentity { param($Configuration) Get-AzUserAssignedIdentity -ResourceGroupName $Configuration.resourceGroup.name -Name $Configuration.resources.managedIdentity.name -ErrorAction SilentlyContinue }
function Resolve-ManagedIdentity {
 [CmdletBinding(SupportsShouldProcess)]param([Parameter(Mandatory)]$Configuration,[switch]$ReuseOnly)
 Import-Module Az.ManagedServiceIdentity -ErrorAction Stop
 $desired=$Configuration.resources.managedIdentity;$existing=Get-TargetManagedIdentity $Configuration
 if($existing){if($existing.Location -ne $Configuration.location){throw "Managed identity '$($desired.name)' is in '$($existing.Location)', expected '$($Configuration.location)'."};return [pscustomobject]@{action='Reuse';resource=$existing;id=$existing.Id;name=$existing.Name;location=$existing.Location;clientId=[string]$existing.ClientId;principalId=[string]$existing.PrincipalId}}
 if($desired.mode -eq 'Existing' -or $ReuseOnly){throw "Required managed identity '$($desired.name)' does not exist."}
 if($PSCmdlet.ShouldProcess($desired.name,'Create user-assigned managed identity')){$existing=New-AzUserAssignedIdentity -ResourceGroupName $Configuration.resourceGroup.name -Name $desired.name -Location $Configuration.location -Tag $Configuration.tags -ErrorAction Stop;return [pscustomobject]@{action='Create';resource=$existing;id=$existing.Id;name=$existing.Name;location=$existing.Location;clientId=[string]$existing.ClientId;principalId=[string]$existing.PrincipalId}}
 [pscustomobject]@{action='Create';resource=$null;id="/subscriptions/$($Configuration.subscriptionId)/resourceGroups/$($Configuration.resourceGroup.name)/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$($desired.name)";name=$desired.name;location=$Configuration.location;clientId=$null;principalId=$null;preview=$true}
}
Export-ModuleMember -Function Get-TargetManagedIdentity,Resolve-ManagedIdentity
