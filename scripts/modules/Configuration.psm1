Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AllowedEnvKeys = @(
 'ENVIRONMENT','TENANT_ID','SUBSCRIPTION_ID','LOCATION','APPLICATION_NAME','RESOURCE_NAME_PREFIX','SHORT_RESOURCE_NAME_PREFIX','RESOURCE_INSTANCE','AUTH_MODE','AUTH_CLIENT_ID','AUTH_CERTIFICATE_THUMBPRINT','BOOTSTRAP_REGISTER_PROVIDERS',
 'DEPLOYMENT_NETWORK_MODE','DEPLOYMENT_CLIENT_IPV4','DEPLOYMENT_ACCESS_LIFETIME','DEPLOYMENT_ALLOW_SQL','DEPLOYMENT_ALLOW_KEY_VAULT','DEPLOYMENT_ALLOW_APP_SERVICE_SCM','DEPLOYMENT_ALLOW_APP_SERVICE_MAIN',
 'RESOURCE_GROUP_MODE','RESOURCE_GROUP_NAME','RESOURCE_GROUP_ID','MANAGED_IDENTITY_MODE','MANAGED_IDENTITY_NAME','MANAGED_IDENTITY_ID','NETWORK_MODE','NETWORK_NAME','NETWORK_ID','VNET_ADDRESS_PREFIX','WORKER_SUBNET_NAME','WORKER_SUBNET_PREFIX','APP_SUBNET_NAME','APP_SUBNET_PREFIX',
 'LOG_ANALYTICS_MODE','LOG_ANALYTICS_NAME','LOG_ANALYTICS_ID','LOG_ANALYTICS_RETENTION_DAYS','APPLICATION_INSIGHTS_MODE','APPLICATION_INSIGHTS_NAME','APPLICATION_INSIGHTS_ID','KEY_VAULT_MODE','KEY_VAULT_NAME','KEY_VAULT_ID','KEY_VAULT_ENABLE_RBAC','KEY_VAULT_SECRET_NAMES',
 'APP_SERVICE_PLAN_MODE','APP_SERVICE_PLAN_NAME','APP_SERVICE_PLAN_ID','APP_SERVICE_PLAN_SKU','APP_SERVICE_PLAN_WORKER_COUNT','WEB_APP_MODE','WEB_APP_NAME','WEB_APP_ID','WEB_OS','WEB_RUNTIME','WEB_HEALTH_PATH','WEB_USE_STAGING_SLOT','WEB_APP_SETTINGS_FILE',
 'WORKER_VM_MODE','WORKER_VM_NAME','WORKER_VM_ID','WORKER_COMPUTER_NAME','WORKER_OS','WORKER_RUNTIME','WORKER_VM_SIZE','WORKER_ADMIN_USERNAME','WORKER_SSH_PUBLIC_KEY_PATH','WORKER_IMAGE_PUBLISHER','WORKER_IMAGE_OFFER','WORKER_IMAGE_SKU','WORKER_IMAGE_VERSION','WORKER_SERVICE_NAME','WORKER_EXECUTABLE','WORKER_ARGUMENTS','WORKER_HEALTH_COMMAND',
 'SQL_PRODUCT','SQL_AUTHENTICATION_MODE','SQL_SERVER_MODE','SQL_SERVER_NAME','SQL_SERVER_ID','SQL_ENTRA_ADMIN_DISPLAY_NAME','SQL_ENTRA_ADMIN_OBJECT_ID','SQL_DATABASE_DEFAULT_EDITION','SQL_DATABASE_DEFAULT_SERVICE_OBJECTIVE','SQL_RUNTIME_ROLES','DATABASES_FILE',
 'DEPLOYMENT_STORAGE_MODE','DEPLOYMENT_STORAGE_NAME','DEPLOYMENT_STORAGE_ID','DEPLOYMENT_STORAGE_SKU','DEPLOYMENT_STORAGE_CONTAINER'
)

function Read-EnvFile {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Path)
    $resolved=(Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path;$values=[ordered]@{};$number=0
    foreach($line in [IO.File]::ReadAllLines($resolved)){
        $number++;$trimmed=$line.Trim();if(-not $trimmed -or $trimmed.StartsWith('#')){continue}
        $separator=$line.IndexOf('=');if($separator -lt 1){throw "Malformed env line $number in ${resolved}: expected KEY=VALUE."}
        $key=$line.Substring(0,$separator).Trim();$value=$line.Substring($separator+1).Trim()
        if($key -notmatch '^[A-Z][A-Z0-9_]*$'){throw "Invalid env key '$key' at line $number."};if($script:AllowedEnvKeys -notcontains $key){throw "Unknown env key '$key' at line $number."};if($values.Contains($key)){throw "Duplicate env key '$key' at line $number."}
        if($value.Length -ge 2 -and (($value[0] -eq '"' -and $value[-1] -eq '"') -or ($value[0] -eq "'" -and $value[-1] -eq "'"))){$value=$value.Substring(1,$value.Length-2)}
        if($value -match '\$\(|`|\$\{|\$[A-Za-z_]'){throw "Env value for '$key' contains unsupported expression syntax."};$values[$key]=$value
    }
    [pscustomobject]@{Path=$resolved;Directory=(Split-Path -Parent $resolved);Values=$values}
}

function Get-EnvValue { param($Values,[string]$Name,$Default=$null) if($Values.Contains($Name)){return $Values[$Name]};$Default }
function New-ResourceConfig { param($Values,[string]$Prefix) [ordered]@{mode=(Get-EnvValue $Values "${Prefix}_MODE" 'Auto');name=(Get-EnvValue $Values "${Prefix}_NAME");resourceId=(Get-EnvValue $Values "${Prefix}_ID")} }
function Resolve-ReferencedPath { param([string]$Base,[string]$Value) if(-not(Test-StringPresent $Value)){return $null};if([IO.Path]::IsPathRooted($Value)){return $Value};Join-Path $Base $Value }

function Import-EnvironmentConfiguration {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Path)
    if([IO.Path]::GetExtension($Path).ToLowerInvariant() -eq '.json'){$resolved=(Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path;$c=ConvertTo-PlainHashtable (Get-Content -LiteralPath $resolved -Raw|ConvertFrom-Json -Depth 100);$c['_sourcePath']=$resolved;$c['_sourceDirectory']=Split-Path -Parent $resolved;return $c}
    $e=Read-EnvFile $Path;$v=$e.Values;$databasePath=Resolve-ReferencedPath $e.Directory (Get-EnvValue $v 'DATABASES_FILE');$databases=@();if($databasePath){if(-not(Test-Path -LiteralPath $databasePath -PathType Leaf)){throw "DATABASES_FILE not found: $databasePath"};$databases=@(ConvertTo-PlainHashtable (Get-Content -LiteralPath $databasePath -Raw|ConvertFrom-Json -Depth 50))}
    $settingsPath=Resolve-ReferencedPath $e.Directory (Get-EnvValue $v 'WEB_APP_SETTINGS_FILE');$appSettings=[ordered]@{};if($settingsPath){$appSettings=ConvertTo-PlainHashtable (Get-Content -LiteralPath $settingsPath -Raw|ConvertFrom-Json -Depth 20)}
    [ordered]@{
      schemaVersion='1.0';environment=(Get-EnvValue $v 'ENVIRONMENT');tenantId=(Get-EnvValue $v 'TENANT_ID');subscriptionId=(Get-EnvValue $v 'SUBSCRIPTION_ID');location=(Get-EnvValue $v 'LOCATION')
      authentication=[ordered]@{mode=(Get-EnvValue $v 'AUTH_MODE' 'Interactive');clientId=(Get-EnvValue $v 'AUTH_CLIENT_ID');certificateThumbprint=(Get-EnvValue $v 'AUTH_CERTIFICATE_THUMBPRINT')}
      naming=[ordered]@{applicationName=(Get-EnvValue $v 'APPLICATION_NAME');resourceNamePrefix=(Get-EnvValue $v 'RESOURCE_NAME_PREFIX');shortResourceNamePrefix=(Get-EnvValue $v 'SHORT_RESOURCE_NAME_PREFIX');instance=(Get-EnvValue $v 'RESOURCE_INSTANCE')}
      tags=[ordered]@{application=(Get-EnvValue $v 'APPLICATION_NAME');environment=(Get-EnvValue $v 'ENVIRONMENT');location=(Get-EnvValue $v 'LOCATION')}
      bootstrap=[ordered]@{registerRequiredProviders=(ConvertTo-BooleanValue 'BOOTSTRAP_REGISTER_PROVIDERS' (Get-EnvValue $v 'BOOTSTRAP_REGISTER_PROVIDERS' 'true'))}
      deploymentNetwork=[ordered]@{mode=(Get-EnvValue $v 'DEPLOYMENT_NETWORK_MODE' 'Private');clientIpv4Cidr=(Get-EnvValue $v 'DEPLOYMENT_CLIENT_IPV4');lifetime=(Get-EnvValue $v 'DEPLOYMENT_ACCESS_LIFETIME' 'Temporary');targets=[ordered]@{sql=(ConvertTo-BooleanValue 'DEPLOYMENT_ALLOW_SQL' (Get-EnvValue $v 'DEPLOYMENT_ALLOW_SQL' 'false'));keyVault=(ConvertTo-BooleanValue 'DEPLOYMENT_ALLOW_KEY_VAULT' (Get-EnvValue $v 'DEPLOYMENT_ALLOW_KEY_VAULT' 'false'));appServiceScm=(ConvertTo-BooleanValue 'DEPLOYMENT_ALLOW_APP_SERVICE_SCM' (Get-EnvValue $v 'DEPLOYMENT_ALLOW_APP_SERVICE_SCM' 'false'));appServiceMain=(ConvertTo-BooleanValue 'DEPLOYMENT_ALLOW_APP_SERVICE_MAIN' (Get-EnvValue $v 'DEPLOYMENT_ALLOW_APP_SERVICE_MAIN' 'false'))}}
      resourceGroup=(New-ResourceConfig $v 'RESOURCE_GROUP')
      resources=[ordered]@{managedIdentity=(New-ResourceConfig $v 'MANAGED_IDENTITY');network=(New-ResourceConfig $v 'NETWORK');logAnalytics=(New-ResourceConfig $v 'LOG_ANALYTICS');applicationInsights=(New-ResourceConfig $v 'APPLICATION_INSIGHTS');keyVault=(New-ResourceConfig $v 'KEY_VAULT');deploymentStorage=(New-ResourceConfig $v 'DEPLOYMENT_STORAGE');appServicePlan=(New-ResourceConfig $v 'APP_SERVICE_PLAN');webApp=(New-ResourceConfig $v 'WEB_APP');workerVm=(New-ResourceConfig $v 'WORKER_VM');sqlServer=(New-ResourceConfig $v 'SQL_SERVER')}
      network=[ordered]@{addressPrefix=(Get-EnvValue $v 'VNET_ADDRESS_PREFIX' '10.42.0.0/16');workerSubnetName=(Get-EnvValue $v 'WORKER_SUBNET_NAME' 'snet-worker');workerSubnetPrefix=(Get-EnvValue $v 'WORKER_SUBNET_PREFIX' '10.42.1.0/24');appSubnetName=(Get-EnvValue $v 'APP_SUBNET_NAME' 'snet-app');appSubnetPrefix=(Get-EnvValue $v 'APP_SUBNET_PREFIX' '10.42.2.0/24')}
      monitoring=[ordered]@{retentionDays=[int](Get-EnvValue $v 'LOG_ANALYTICS_RETENTION_DAYS' '30')}
      keyVault=[ordered]@{enableRbac=(ConvertTo-BooleanValue 'KEY_VAULT_ENABLE_RBAC' (Get-EnvValue $v 'KEY_VAULT_ENABLE_RBAC' 'true'));secretNames=@((Get-EnvValue $v 'KEY_VAULT_SECRET_NAMES' '').Split(',',[StringSplitOptions]::RemoveEmptyEntries)|ForEach-Object Trim)}
      appService=[ordered]@{sku=(Get-EnvValue $v 'APP_SERVICE_PLAN_SKU' 'B1');workerCount=[int](Get-EnvValue $v 'APP_SERVICE_PLAN_WORKER_COUNT' '1')}
      deploymentStorage=[ordered]@{sku=(Get-EnvValue $v 'DEPLOYMENT_STORAGE_SKU' 'Standard_LRS');container=(Get-EnvValue $v 'DEPLOYMENT_STORAGE_CONTAINER' 'releases')}
      application=[ordered]@{web=[ordered]@{operatingSystem=(Get-EnvValue $v 'WEB_OS');runtime=(Get-EnvValue $v 'WEB_RUNTIME');healthPath=(Get-EnvValue $v 'WEB_HEALTH_PATH' '/');useStagingSlot=(ConvertTo-BooleanValue 'WEB_USE_STAGING_SLOT' (Get-EnvValue $v 'WEB_USE_STAGING_SLOT' 'false'));appSettings=$appSettings};worker=[ordered]@{operatingSystem=(Get-EnvValue $v 'WORKER_OS');runtime=(Get-EnvValue $v 'WORKER_RUNTIME');computerName=(Get-EnvValue $v 'WORKER_COMPUTER_NAME');vmSize=(Get-EnvValue $v 'WORKER_VM_SIZE' 'Standard_B2s');adminUsername=(Get-EnvValue $v 'WORKER_ADMIN_USERNAME' 'azureuser');sshPublicKeyPath=(Get-EnvValue $v 'WORKER_SSH_PUBLIC_KEY_PATH');image=[ordered]@{publisher=(Get-EnvValue $v 'WORKER_IMAGE_PUBLISHER');offer=(Get-EnvValue $v 'WORKER_IMAGE_OFFER');sku=(Get-EnvValue $v 'WORKER_IMAGE_SKU');version=(Get-EnvValue $v 'WORKER_IMAGE_VERSION' 'latest')};serviceName=(Get-EnvValue $v 'WORKER_SERVICE_NAME' 'SwarmsWorker');executable=(Get-EnvValue $v 'WORKER_EXECUTABLE');arguments=(Get-EnvValue $v 'WORKER_ARGUMENTS');healthCommand=(Get-EnvValue $v 'WORKER_HEALTH_COMMAND')}}
      sql=[ordered]@{authenticationMode=(Get-EnvValue $v 'SQL_AUTHENTICATION_MODE' 'Entra');product=(Get-EnvValue $v 'SQL_PRODUCT');entraAdminDisplayName=(Get-EnvValue $v 'SQL_ENTRA_ADMIN_DISPLAY_NAME');entraAdminObjectId=(Get-EnvValue $v 'SQL_ENTRA_ADMIN_OBJECT_ID');defaultEdition=(Get-EnvValue $v 'SQL_DATABASE_DEFAULT_EDITION' 'GeneralPurpose');defaultServiceObjective=(Get-EnvValue $v 'SQL_DATABASE_DEFAULT_SERVICE_OBJECTIVE' 'GP_S_Gen5_1');runtimeRoles=@((Get-EnvValue $v 'SQL_RUNTIME_ROLES' 'db_datareader,db_datawriter').Split(',',[StringSplitOptions]::RemoveEmptyEntries)|ForEach-Object Trim)}
      databases=$databases;_sourcePath=$e.Path;_sourceDirectory=$e.Directory;_databasePath=$databasePath;_settingsPath=$settingsPath
    }
}

function Test-EnvironmentConfiguration {
 [CmdletBinding()]param([Parameter(Mandatory)]$Configuration,[Parameter(Mandatory)][ValidateSet('Bootstrap','Provisioning','Deployment')][string]$Operation,[ValidateSet('Web','Worker','Database','All')][string]$Target='All',[switch]$ReuseOnly)
 foreach($f in 'environment','tenantId','subscriptionId','location'){if(-not(Test-StringPresent $Configuration[$f])){throw "$f is required."}};if($Configuration.location -ne 'eastus'){throw 'LOCATION must be eastus for this environment.'}
 Assert-ValueInSet 'resource group mode' $Configuration.resourceGroup.mode @('Create','Existing','Auto')
 if($Configuration.resourceGroup.mode -eq 'Existing'){
  if($Configuration.resourceGroup.resourceId -notmatch '^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+$'){throw 'resourceGroup.resourceId is not a valid Azure resource group ID.'}
  if(-not(Test-StringPresent $Configuration.resourceGroup.name)){$Configuration.resourceGroup.name=$Configuration.resourceGroup.resourceId.Trim('/').Split('/')[-1]}
 }elseif(-not(Test-StringPresent $Configuration.resourceGroup.name)){throw 'Resource group name is required for Create and Auto modes.'}
 foreach($r in @($Configuration.resources.Values)){Assert-ValueInSet 'resource mode' $r.mode @('Create','Existing','Auto');if($r.mode -eq 'Existing'){Assert-AzureResourceId 'resourceId' $r.resourceId;if((Get-ResourceIdPart $r.resourceId SubscriptionId) -ne $Configuration.subscriptionId){throw "Existing resource ID belongs to a different subscription: $($r.resourceId)"};if((Get-ResourceIdPart $r.resourceId ResourceGroupName) -ne $Configuration.resourceGroup.name){throw "Existing resource ID belongs to a different resource group: $($r.resourceId)"};if(-not(Test-StringPresent $r.name)){$r.name=Get-ResourceIdPart $r.resourceId Name}}elseif(-not(Test-StringPresent $r.name)){throw 'Resource name is required for Create and Auto modes.'}}
 $resourceTypes=[ordered]@{managedIdentity='Microsoft.ManagedIdentity/userAssignedIdentities';network='Microsoft.Network/virtualNetworks';logAnalytics='Microsoft.OperationalInsights/workspaces';applicationInsights='Microsoft.Insights/components';keyVault='Microsoft.KeyVault/vaults';deploymentStorage='Microsoft.Storage/storageAccounts';appServicePlan='Microsoft.Web/serverfarms';webApp='Microsoft.Web/sites';workerVm='Microsoft.Compute/virtualMachines';sqlServer='Microsoft.Sql/servers'}
 foreach($key in $resourceTypes.Keys){$r=$Configuration.resources[$key];if($r.mode -eq 'Existing' -and $r.resourceId -notmatch "/providers/$([regex]::Escape($resourceTypes[$key]))/[^/]+$"){throw "resources.$key.resourceId is not a $($resourceTypes[$key]) resource ID."}}
 $dupes=@($Configuration.databases|Group-Object { $_['name'] }|Where-Object Count -gt 1);if($dupes){throw "Duplicate database name: $($dupes[0].Name)"};foreach($d in $Configuration.databases){Assert-ValueInSet "database '$($d.key)' mode" $d.mode @('Create','Existing','Auto');if($d.mode -eq 'Existing'){Assert-AzureResourceId "database '$($d.key)' resourceId" $d.resourceId;if($d.resourceId -notmatch '/providers/Microsoft\.Sql/servers/[^/]+/databases/[^/]+$'){throw "database '$($d.key)' resourceId is not an Azure SQL database ID."}}}
 if($Configuration.resources.deploymentStorage.name -notmatch '^[a-z0-9]{3,24}$'){throw 'DEPLOYMENT_STORAGE_NAME must contain 3-24 lowercase letters or digits.'}
 if($Configuration.resources.keyVault.name -notmatch '^[a-zA-Z0-9-]{3,24}$'){throw 'KEY_VAULT_NAME must contain 3-24 letters, digits, or hyphens.'}
 if($Configuration.resources.sqlServer.name -notmatch '^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$'){throw 'SQL_SERVER_NAME is not a valid Azure SQL logical-server name.'}
 if($Configuration.resources.webApp.name -notmatch '^[a-z0-9][a-z0-9-]{0,58}[a-z0-9]$'){throw 'WEB_APP_NAME must be a 2-60 character lowercase DNS name.'}
 if(-not $Configuration.keyVault.enableRbac){throw 'This implementation requires KEY_VAULT_ENABLE_RBAC=true.'}
 if($Configuration.application.web.useStagingSlot -and ($Operation -eq 'Provisioning' -or ($Operation -eq 'Deployment' -and $Target -in 'Web','All'))){throw 'WEB_USE_STAGING_SLOT=true is not supported by this release workflow.'}
 Assert-ValueInSet 'authentication mode' $Configuration.authentication.mode @('Interactive','DeviceCode','ExistingContext','ServicePrincipalCertificate','ManagedIdentity');Assert-ValueInSet 'deployment network mode' $Configuration.deploymentNetwork.mode @('PublicAllowList','Private');Assert-ValueInSet 'deployment access lifetime' $Configuration.deploymentNetwork.lifetime @('Temporary','Persistent')
 if($Configuration.deploymentNetwork.mode -eq 'PublicAllowList' -and (Test-StringPresent $Configuration.deploymentNetwork.clientIpv4Cidr)){[void](Get-PublicIPv4FromCidr $Configuration.deploymentNetwork.clientIpv4Cidr)}
 if($Operation -eq 'Provisioning' -and -not $ReuseOnly -and $Configuration.deploymentNetwork.mode -eq 'PublicAllowList' -and ($Configuration.deploymentNetwork.targets.sql -or $Configuration.deploymentNetwork.targets.keyVault -or $Configuration.deploymentNetwork.targets.appServiceScm -or $Configuration.deploymentNetwork.targets.appServiceMain) -and -not(Test-StringPresent $Configuration.deploymentNetwork.clientIpv4Cidr)){throw 'DEPLOYMENT_CLIENT_IPV4 is required before public-mode provisioning can make Azure changes.'}
 $sqlAuthenticationMode=Get-SqlAuthenticationMode $Configuration
 if($Operation -eq 'Provisioning'){
  Assert-ValueInSet 'SQL_PRODUCT' $Configuration.sql.product @('AzureSqlDatabase');Assert-ValueInSet 'WEB_OS' $Configuration.application.web.operatingSystem @('Linux','Windows');Assert-ValueInSet 'WORKER_OS' $Configuration.application.worker.operatingSystem @('Linux','Windows')
  if(-not $ReuseOnly){if(-not(Test-StringPresent $Configuration.application.web.runtime)){throw 'WEB_RUNTIME is required when Provisioning may create the web app.'};if($Configuration.resources.workerVm.mode -ne 'Existing' -and $Configuration.application.worker.operatingSystem -eq 'Linux' -and -not(Test-StringPresent $Configuration.application.worker.sshPublicKeyPath)){throw 'WORKER_SSH_PUBLIC_KEY_PATH is required to create a Linux VM.'};if($sqlAuthenticationMode -eq 'Entra' -and $Configuration.resources.sqlServer.mode -ne 'Existing' -and (-not(Test-StringPresent $Configuration.sql.entraAdminObjectId) -or -not(Test-StringPresent $Configuration.sql.entraAdminDisplayName))){throw 'SQL_ENTRA_ADMIN_DISPLAY_NAME and SQL_ENTRA_ADMIN_OBJECT_ID are required when Provisioning may create the SQL server.'}}
 }
 return $true
}

function Test-DeploymentTargetConfiguration {
 [CmdletBinding()]param([Parameter(Mandatory)]$Configuration,[Parameter(Mandatory)][ValidateSet('Web','Worker','Database','All')][string]$Target)
 if($Target -in 'Worker','All'){
  Assert-ValueInSet 'WORKER_OS' $Configuration.application.worker.operatingSystem @('Linux','Windows')
  if(-not(Test-StringPresent $Configuration.application.worker.executable)){throw 'WORKER_EXECUTABLE is required for Worker and All deployments.'}
  $executable=[string]$Configuration.application.worker.executable
  if([IO.Path]::IsPathRooted($executable) -or $executable -match '^[A-Za-z]:[\\/]' -or $executable -split '[\\/]' -contains '..'){throw 'WORKER_EXECUTABLE must be a safe path relative to the worker package root.'}
  if(-not(Test-StringPresent $Configuration.application.worker.serviceName) -or $Configuration.application.worker.serviceName -notmatch '^[A-Za-z0-9_.@-]+$'){throw 'WORKER_SERVICE_NAME is required and contains unsupported characters.'}
 }
 return $true
}

function Get-ConfigurationProvenance { param($Configuration,[string]$ScriptsRoot) $p=[ordered]@{sourcePath=$Configuration._sourcePath;sourceSha256=(Get-FileSha256 $Configuration._sourcePath);scriptsSha256=(Get-ScriptsSha256 $ScriptsRoot)};foreach($pair in @(@('_databasePath','databasePath','databaseSha256'),@('_settingsPath','settingsPath','settingsSha256'))){if(Test-StringPresent $Configuration[$pair[0]]){$p[$pair[1]]=$Configuration[$pair[0]];$p[$pair[2]]=Get-FileSha256 $Configuration[$pair[0]]}};$p }

Export-ModuleMember -Function Read-EnvFile,Import-EnvironmentConfiguration,Test-EnvironmentConfiguration,Test-DeploymentTargetConfiguration,Get-ConfigurationProvenance
