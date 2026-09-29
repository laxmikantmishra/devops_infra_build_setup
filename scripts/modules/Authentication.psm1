Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Connect-DeploymentAzure {
 [CmdletBinding()]param([Parameter(Mandatory)]$Configuration,[string]$AuthMode,[string]$AuthClientId,[string]$CertificateThumbprint,[switch]$NonInteractive)
 foreach($module in 'Az.Accounts','Az.Resources'){if(-not(Get-Module -ListAvailable -Name $module)){throw "Required PowerShell module '$module' is not installed."}}
 Import-Module Az.Accounts -ErrorAction Stop;Import-Module Az.Resources -ErrorAction Stop
 $mode=if(Test-StringPresent $AuthMode){$AuthMode}else{$Configuration.authentication.mode};if(-not(Test-StringPresent $mode)){$mode='Interactive'}
 $clientId=if(Test-StringPresent $AuthClientId){$AuthClientId}else{$Configuration.authentication.clientId};$thumb=if(Test-StringPresent $CertificateThumbprint){$CertificateThumbprint}else{$Configuration.authentication.certificateThumbprint}
 if($NonInteractive -and $mode -in 'Interactive','DeviceCode'){throw "AuthMode '$mode' cannot be used with -NonInteractive."}
 switch($mode){
  'Interactive'{[void](Connect-AzAccount -Tenant $Configuration.tenantId -Subscription $Configuration.subscriptionId -Scope Process -ErrorAction Stop)}
  'DeviceCode'{[void](Connect-AzAccount -Tenant $Configuration.tenantId -Subscription $Configuration.subscriptionId -UseDeviceAuthentication -Scope Process -ErrorAction Stop)}
  'ExistingContext'{}
  'ServicePrincipalCertificate'{if(-not(Test-StringPresent $clientId)-or-not(Test-StringPresent $thumb)){throw 'AuthClientId and CertificateThumbprint are required for ServicePrincipalCertificate.'};[void](Connect-AzAccount -ServicePrincipal -ApplicationId $clientId -CertificateThumbprint $thumb -Tenant $Configuration.tenantId -Subscription $Configuration.subscriptionId -Scope Process -ErrorAction Stop)}
  'ManagedIdentity'{if(Test-StringPresent $clientId){[void](Connect-AzAccount -Identity -AccountId $clientId -Subscription $Configuration.subscriptionId -Scope Process -ErrorAction Stop)}else{[void](Connect-AzAccount -Identity -Subscription $Configuration.subscriptionId -Scope Process -ErrorAction Stop)}}
  default{throw "Unsupported AuthMode '$mode'."}
 }
 $context=Get-AzContext -ErrorAction Stop;if($null -eq $context -or $context.Subscription.Id -ne $Configuration.subscriptionId -or $context.Tenant.Id -ne $Configuration.tenantId){throw "Azure context mismatch. Expected tenant '$($Configuration.tenantId)' subscription '$($Configuration.subscriptionId)'."}
 [void](Set-AzContext -Tenant $Configuration.tenantId -Subscription $Configuration.subscriptionId -Scope Process -ErrorAction Stop)
 [pscustomobject]@{Mode=$mode;TenantId=$context.Tenant.Id;SubscriptionId=$context.Subscription.Id;AccountId=$context.Account.Id;Context=(Get-AzContext)}
}

Export-ModuleMember -Function Connect-DeploymentAzure
