Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Resolve-KeyVault {
 [CmdletBinding(SupportsShouldProcess)]param($Configuration,[switch]$ReuseOnly)
 if(-not $Configuration.keyVault.enableRbac){throw 'This implementation requires KEY_VAULT_ENABLE_RBAC=true.'}
 # Az.KeyVault 6.x enables RBAC by default; the supported switch disables it.
 Import-Module Az.KeyVault -ErrorAction Stop;$cfg=$Configuration.resources.keyVault;Write-DeploymentStatus -Stage KeyVault -Status Read -Message "Retrieving Key Vault $($cfg.name)...";$vault=Get-AzKeyVault -ResourceGroupName $Configuration.resourceGroup.name -VaultName $cfg.name -ErrorAction SilentlyContinue
 if($vault){if((-not (Test-AzureLocationMatch -Actual $vault.Location -Expected $Configuration.location))){throw "Key Vault '$($cfg.name)' is in '$($vault.Location)', expected '$($Configuration.location)'."};if(-not $vault.EnableRbacAuthorization){throw "Key Vault '$($cfg.name)' does not use Azure RBAC authorization."};Write-DeploymentStatus -Stage KeyVault -Status Reuse -Message "Using existing Key Vault $($cfg.name).";return [pscustomobject]@{action='Reuse';resource=$vault;id=$vault.ResourceId;name=$vault.VaultName;vaultUri=$vault.VaultUri;location=$vault.Location}}
 if($cfg.mode -eq 'Existing' -or $ReuseOnly){throw "Key Vault '$($cfg.name)' does not exist."}
 if($PSCmdlet.ShouldProcess($cfg.name,'Create Key Vault')){Write-DeploymentStatus -Stage KeyVault -Status Create -Message ("{0}: {1}..." -f 'Create Key Vault',$cfg.name);$parameters=@{ResourceGroupName=$Configuration.resourceGroup.name;VaultName=$cfg.name;Location=$Configuration.location;Sku='Standard';EnablePurgeProtection=$true;DisableRbacAuthorization=$false;Tag=$Configuration.tags;ErrorAction='Stop'};$null=New-AzKeyVault @parameters;$vault=Get-AzKeyVault -ResourceGroupName $Configuration.resourceGroup.name -VaultName $cfg.name -ErrorAction Stop;if(-not $vault.EnableRbacAuthorization){throw "Created Key Vault '$($cfg.name)' did not report Azure RBAC authorization enabled. Provisioning cannot continue."};return [pscustomobject]@{action='Create';resource=$vault;id=$vault.ResourceId;name=$vault.VaultName;vaultUri=$vault.VaultUri;location=$vault.Location}}
 $id="/subscriptions/$($Configuration.subscriptionId)/resourceGroups/$($Configuration.resourceGroup.name)/providers/Microsoft.KeyVault/vaults/$($cfg.name)";[pscustomobject]@{action='Create';id=$id;name=$cfg.name;vaultUri="https://$($cfg.name).vault.azure.net/";location=$Configuration.location;preview=$true}
}
Export-ModuleMember -Function Resolve-KeyVault
