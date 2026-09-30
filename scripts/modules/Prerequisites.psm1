Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Test-RequiredCommands {
 [CmdletBinding()]param([Parameter(Mandatory)][string[]]$Names)
 $missing=@($Names|Where-Object{-not(Get-Command $_ -ErrorAction SilentlyContinue)});if($missing){throw "Required commands are unavailable: $($missing -join ', '). Install the corresponding Az modules."};$true
}

function Get-RequiredProviderNamespaces { @('Microsoft.ManagedIdentity','Microsoft.Web','Microsoft.Compute','Microsoft.Network','Microsoft.Sql','Microsoft.KeyVault','Microsoft.Insights','Microsoft.OperationalInsights','Microsoft.Storage') }

function Test-TransientProviderReadError {
 [CmdletBinding()]param([Parameter(Mandatory)][Management.Automation.ErrorRecord]$Record)
 $transient=$false
 $exception=$Record.Exception
 while($null -ne $exception){
  # An outer transport error must not hide an authorization or TLS failure.
  if($exception -is [Security.Authentication.AuthenticationException] -or $exception -is [Management.Automation.PipelineStoppedException]){return $false}
  if($exception.Message -match '(?i)unauthorized|forbidden|access denied|authorizationfailed|certificate|SSL|TLS|authentication failed'){return $false}
  $status=$null
  if($exception.PSObject.Properties['StatusCode'] -and $null -ne $exception.StatusCode){$status=[int]$exception.StatusCode}
  elseif($exception.PSObject.Properties['Response'] -and $null -ne $exception.Response -and $exception.Response.PSObject.Properties['StatusCode']){$status=[int]$exception.Response.StatusCode}
  if($null -ne $status){
   if($status -notin 408,429,500,502,503,504){return $false}
   $transient=$true
  }
  if($exception -is [TimeoutException] -or $exception.Message -match '(?i)error while copying content to (?:a )?stream|unexpected (?:EOF|end of (?:file|stream))|connection.*(?:reset|closed)|timed out|timeout'){$transient=$true}
  $exception=$exception.InnerException
 }
 return $transient
}

function Get-DeploymentResourceProvider {
 [CmdletBinding()]
 param([Parameter(Mandatory)][string]$Namespace,$Context,[ValidateRange(1,5)][int]$MaxAttempts=3)
 if($null -eq $Context){$Context=Get-AzContext -ErrorAction Stop}
 if($null -eq $Context){throw 'An authenticated Azure context is required to read provider registration.'}
 for($attempt=1;$attempt -le $MaxAttempts;$attempt++){
  Write-DeploymentStatus -Stage Providers -Status Read -Message "Retrieving registration for $Namespace (attempt $attempt/$MaxAttempts)..."
  try {
   # Buffer this read so a failed/partial enumeration never escapes as inventory.
   $providers=@(Get-AzResourceProvider -ProviderNamespace $Namespace -DefaultProfile $Context -ErrorAction Stop)
   if(-not $providers.Count){throw "Provider lookup for '$Namespace' returned no data; registration is unresolved."}
   foreach($provider in $providers){
    if($provider.ProviderNamespace -ne $Namespace -or -not(Test-StringPresent $provider.RegistrationState)){throw "Provider lookup for '$Namespace' returned incomplete or mismatched data."}
   }
   $states=@($providers.RegistrationState | Select-Object -Unique)
   if($states.Count -ne 1){throw "Provider lookup for '$Namespace' returned conflicting registration states."}
   Write-DeploymentStatus -Stage Providers -Message "$Namespace registration: $($states[0])."
   return [pscustomobject]@{ProviderNamespace=$Namespace;RegistrationState=$states[0]}
  } catch {
   if(-not(Test-TransientProviderReadError -Record $_)){throw}
   if($attempt -ge $MaxAttempts){
    $message="Could not retrieve provider '$Namespace' after $MaxAttempts attempts because a retryable Azure transport or service error persisted. No missing-provider assumption was made. Check connectivity to Azure Resource Manager, approved VPN/proxy settings and the installed Az.Resources version; then rerun the owning script. The original error is retained as InnerException."
    throw [InvalidOperationException]::new($message,$_.Exception)
   }
   $delay=[int][math]::Pow(2,$attempt)
   Write-DeploymentStatus -Stage Providers -Status Warning -Message "Transient read failure for $Namespace ($($_.Exception.GetType().Name)); retrying in ${delay}s."
   Start-Sleep -Seconds $delay
  }
 }
}

function Get-ProviderReadiness {
 [CmdletBinding()]param($Context)
 if($null -eq $Context){$Context=Get-AzContext -ErrorAction Stop}
 @(foreach($namespace in Get-RequiredProviderNamespaces){$provider=Get-DeploymentResourceProvider -Namespace $namespace -Context $Context;[pscustomobject]@{namespace=$namespace;registrationState=$provider.RegistrationState}})
}

function Test-SubscriptionReadiness {
 [CmdletBinding()]param([Parameter(Mandatory)]$Configuration,[Parameter(Mandatory)][ValidateSet('Bootstrap','Provisioning','Deployment')][string]$Operation)
 $context=Get-AzContext -ErrorAction Stop;if($context.Subscription.Id -ne $Configuration.subscriptionId){throw 'Active subscription does not match configuration.'}
 Write-DeploymentStatus -Stage Subscription -Status Read -Message "Retrieving subscription $($Configuration.subscriptionId)..."
 $subscription=Get-AzSubscription -SubscriptionId $Configuration.subscriptionId -TenantId $Configuration.tenantId -ErrorAction Stop;if($subscription.State -ne 'Enabled'){throw "Subscription state is '$($subscription.State)'."}
 Write-DeploymentStatus -Stage Subscription -Status Success -Message "Subscription verified: $($subscription.Name) ($($subscription.Id)); state $($subscription.State)."
 $providers=Get-ProviderReadiness -Context $context
 [pscustomobject]@{tenantId=$Configuration.tenantId;subscriptionId=$Configuration.subscriptionId;subscriptionName=$subscription.Name;state=$subscription.State;operation=$Operation;providers=$providers}
}

Export-ModuleMember -Function Test-RequiredCommands,Get-RequiredProviderNamespaces,Get-ProviderReadiness,Test-SubscriptionReadiness,Get-DeploymentResourceProvider
