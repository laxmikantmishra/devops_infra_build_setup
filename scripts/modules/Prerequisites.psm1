Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Test-RequiredCommands {
 [CmdletBinding()]param([Parameter(Mandatory)][string[]]$Names)
 $missing=@($Names|Where-Object{-not(Get-Command $_ -ErrorAction SilentlyContinue)});if($missing){throw "Required commands are unavailable: $($missing -join ', '). Install the corresponding Az modules."};$true
}

function Get-RequiredProviderNamespaces { @('Microsoft.ManagedIdentity','Microsoft.Web','Microsoft.Compute','Microsoft.Network','Microsoft.Sql','Microsoft.KeyVault','Microsoft.Insights','Microsoft.OperationalInsights','Microsoft.Storage') }

function Get-ProviderReadiness {
 [CmdletBinding()]param()
 @(foreach($namespace in Get-RequiredProviderNamespaces){$provider=Get-AzResourceProvider -ProviderNamespace $namespace -ErrorAction Stop;[pscustomobject]@{namespace=$namespace;registrationState=$provider.RegistrationState}})
}

function Test-SubscriptionReadiness {
 [CmdletBinding()]param([Parameter(Mandatory)]$Configuration,[Parameter(Mandatory)][ValidateSet('Bootstrap','Provisioning','Deployment')][string]$Operation)
 $context=Get-AzContext -ErrorAction Stop;if($context.Subscription.Id -ne $Configuration.subscriptionId){throw 'Active subscription does not match configuration.'}
 $subscription=Get-AzSubscription -SubscriptionId $Configuration.subscriptionId -TenantId $Configuration.tenantId -ErrorAction Stop;if($subscription.State -ne 'Enabled'){throw "Subscription state is '$($subscription.State)'."}
 $providers=Get-ProviderReadiness
 [pscustomobject]@{tenantId=$Configuration.tenantId;subscriptionId=$Configuration.subscriptionId;subscriptionName=$subscription.Name;state=$subscription.State;operation=$Operation;providers=$providers}
}

Export-ModuleMember -Function Test-RequiredCommands,Get-RequiredProviderNamespaces,Get-ProviderReadiness,Test-SubscriptionReadiness
