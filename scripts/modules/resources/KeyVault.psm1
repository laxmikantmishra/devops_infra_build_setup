Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Resolve-KeyVault {
 [CmdletBinding(SupportsShouldProcess)]param($Configuration,[switch]$ReuseOnly)
 Import-Module Az.KeyVault -ErrorAction Stop;$cfg=$Configuration.resources.keyVault;Write-DeploymentStatus -Stage KeyVault -Status Read -Message "Retrieving Key Vault $($cfg.name)...";$vault=Get-AzKeyVault -ResourceGroupName $Configuration.resourceGroup.name -VaultName $cfg.name -ErrorAction SilentlyContinue
 if($vault){if($vault.Location -ne $Configuration.location){throw "Key Vault '$($cfg.name)' is in '$($vault.Location)', expected '$($Configuration.location)'."};if(-not $vault.EnableRbacAuthorization){throw "Key Vault '$($cfg.name)' does not use Azure RBAC authorization."};Write-DeploymentStatus -Stage KeyVault -Status Reuse -Message "Using existing Key Vault $($cfg.name).";return [pscustomobject]@{action='Reuse';resource=$vault;id=$vault.ResourceId;name=$vault.VaultName;vaultUri=$vault.VaultUri;location=$vault.Location}}
 if($cfg.mode -eq 'Existing' -or $ReuseOnly){throw "Key Vault '$($cfg.name)' does not exist."}
 if($PSCmdlet.ShouldProcess($cfg.name,'Create Key Vault')){Write-DeploymentStatus -Stage KeyVault -Status Create -Message ("{0}: {1}..." -f 'Create Key Vault',$cfg.name);$parameters=@{ResourceGroupName=$Configuration.resourceGroup.name;VaultName=$cfg.name;Location=$Configuration.location;Sku='Standard';EnablePurgeProtection=$true;Tag=$Configuration.tags;ErrorAction='Stop'};if($Configuration.keyVault.enableRbac){$parameters.EnableRbacAuthorization=$true};$vault=New-AzKeyVault @parameters;return [pscustomobject]@{action='Create';resource=$vault;id=$vault.ResourceId;name=$vault.VaultName;vaultUri=$vault.VaultUri;location=$vault.Location}}
 $id="/subscriptions/$($Configuration.subscriptionId)/resourceGroups/$($Configuration.resourceGroup.name)/providers/Microsoft.KeyVault/vaults/$($cfg.name)";[pscustomobject]@{action='Create';id=$id;name=$cfg.name;vaultUri="https://$($cfg.name).vault.azure.net/";location=$Configuration.location;preview=$true}
}
Export-ModuleMember -Function Resolve-KeyVault
