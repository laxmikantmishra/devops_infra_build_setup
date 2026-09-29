Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-ExistingInfrastructure {
    [CmdletBinding()]param($Configuration,[ValidateSet('Web','Worker','Database','All')][string]$Target='All',[switch]$IncludeDatabase)
    Import-Module Az.Resources,Az.ManagedServiceIdentity,Az.KeyVault,Az.Storage,Az.Websites,Az.Compute,Az.Sql,Az.ApplicationInsights -ErrorAction Stop
    $needWeb=$Target -in 'Web','All';$needWorker=$Target -in 'Worker','All';$needDatabase=$Target -eq 'Database' -or $IncludeDatabase;$needSql=$needDatabase -or $needWorker
    $rg=Get-AzResourceGroup -Name $Configuration.resourceGroup.name -ErrorAction Stop
    $mi=if($needWorker){Get-AzUserAssignedIdentity -ResourceGroupName $rg.ResourceGroupName -Name $Configuration.resources.managedIdentity.name -ErrorAction Stop}
    $kv=if($needWorker){Get-AzKeyVault -ResourceGroupName $rg.ResourceGroupName -VaultName $Configuration.resources.keyVault.name -ErrorAction Stop}
    $storage=if($needWorker){Get-AzStorageAccount -ResourceGroupName $rg.ResourceGroupName -Name $Configuration.resources.deploymentStorage.name -ErrorAction Stop}
    $web=if($needWeb){Get-AzWebApp -ResourceGroupName $rg.ResourceGroupName -Name $Configuration.resources.webApp.name -ErrorAction Stop}
    $vm=if($needWorker){Get-AzVM -ResourceGroupName $rg.ResourceGroupName -Name $Configuration.resources.workerVm.name -ErrorAction Stop}
    $sql=if($needSql){Get-AzSqlServer -ResourceGroupName $rg.ResourceGroupName -ServerName $Configuration.resources.sqlServer.name -ErrorAction Stop}
    $ai=if($needWorker){Get-AzApplicationInsights -ResourceGroupName $rg.ResourceGroupName -Name $Configuration.resources.applicationInsights.name -ErrorAction Stop}
    $databases=if($needSql){@(foreach($db in $Configuration.databases){$found=Get-AzSqlDatabase -ResourceGroupName $rg.ResourceGroupName -ServerName $sql.ServerName -DatabaseName $db.name -ErrorAction Stop;[pscustomobject]@{key=$db.key;name=$found.DatabaseName;id=$found.ResourceId;resource=$found}})}else{@()}
    [pscustomobject]@{
        resourceGroup=[pscustomobject]@{name=$rg.ResourceGroupName;id=$rg.ResourceId;resource=$rg}
        managedIdentity=if($mi){[pscustomobject]@{name=$mi.Name;id=$mi.Id;clientId=[string]$mi.ClientId;principalId=[string]$mi.PrincipalId;resource=$mi}}else{$null}
        keyVault=if($kv){[pscustomobject]@{name=$kv.VaultName;id=$kv.ResourceId;vaultUri=$kv.VaultUri;resource=$kv}}else{$null}
        deploymentStorage=if($storage){[pscustomobject]@{name=$storage.StorageAccountName;id=$storage.Id;blobEndpoint=$storage.PrimaryEndpoints.Blob;container=$Configuration.deploymentStorage.container;resource=$storage}}else{$null}
        monitoring=[pscustomobject]@{applicationInsights=if($ai){[pscustomobject]@{name=$ai.Name;id=$ai.Id;connectionString=$ai.ConnectionString;resource=$ai}}else{$null}}
        appService=[pscustomobject]@{webApp=if($web){[pscustomobject]@{name=$web.Name;id=$web.Id;hostName=$web.DefaultHostName;resource=$web}}else{$null}}
        workerVm=if($vm){[pscustomobject]@{name=$vm.Name;id=$vm.Id;operatingSystem=$Configuration.application.worker.operatingSystem;computerName=$Configuration.application.worker.computerName;resource=$vm}}else{$null}
        sqlServer=if($sql){[pscustomobject]@{name=$sql.ServerName;id=$sql.ResourceId;fullyQualifiedDomainName=$sql.FullyQualifiedDomainName;resource=$sql}}else{$null};databases=$databases
    }
}

function Convert-ManifestToResolvedResources {
    param($Manifest)
    $r=$Manifest.resources
    [pscustomobject]@{resourceGroup=[pscustomobject]@{name=$Manifest.resourceGroup.name;id=$Manifest.resourceGroup.resourceId};managedIdentity=[pscustomobject]@{name=$r.managedIdentity.name;id=$r.managedIdentity.resourceId;clientId=$r.managedIdentity.clientId;principalId=$r.managedIdentity.principalId};keyVault=[pscustomobject]@{name=$r.keyVault.name;id=$r.keyVault.resourceId;vaultUri=$r.keyVault.vaultUri};deploymentStorage=[pscustomobject]@{name=$r.deploymentStorage.name;id=$r.deploymentStorage.resourceId;blobEndpoint=$r.deploymentStorage.blobEndpoint;container=$r.deploymentStorage.container};monitoring=[pscustomobject]@{applicationInsights=[pscustomobject]@{name=$r.applicationInsights.name;id=$r.applicationInsights.resourceId;connectionString=$r.applicationInsights.connectionString}};appService=[pscustomobject]@{webApp=[pscustomobject]@{name=$r.webApp.name;id=$r.webApp.resourceId;hostName=$r.webApp.hostName}};workerVm=[pscustomobject]@{name=$r.workerVm.name;id=$r.workerVm.resourceId;operatingSystem=$r.workerVm.operatingSystem;computerName=$r.workerVm.computerName};sqlServer=[pscustomobject]@{name=$r.sqlServer.name;id=$r.sqlServer.resourceId;fullyQualifiedDomainName=$r.sqlServer.fullyQualifiedDomainName};databases=@($r.databases|ForEach-Object{[pscustomobject]@{key=$_.key;name=$_.name;id=$_.resourceId}})}
}

function Test-ManifestResourcesLive {
    [CmdletBinding()]param($Manifest,[ValidateSet('Web','Worker','Database','All')][string]$Target='All',[switch]$IncludeDatabase)
    Import-Module Az.Resources,Az.ManagedServiceIdentity -ErrorAction Stop
    $ids=[Collections.Generic.List[string]]::new()
    if($Target -in 'Web','All'){$ids.Add([string]$Manifest.resources.webApp.resourceId)}
    if($Target -in 'Worker','All'){foreach($key in 'managedIdentity','keyVault','deploymentStorage','applicationInsights','workerVm','sqlServer'){$ids.Add([string]$Manifest.resources[$key].resourceId)};foreach($db in $Manifest.resources.databases){$ids.Add([string]$db.resourceId)}}
    elseif($Target -eq 'Database' -or $IncludeDatabase){$ids.Add([string]$Manifest.resources.sqlServer.resourceId);foreach($db in $Manifest.resources.databases){$ids.Add([string]$db.resourceId)}}
    foreach($id in $ids){$resource=Get-AzResource -ResourceId $id -ErrorAction Stop;if(-not $resource){throw "Manifest resource no longer exists: $id"}}
    if($Target -in 'Worker','All'){$identity=Get-AzUserAssignedIdentity -ResourceGroupName $Manifest.resourceGroup.name -Name $Manifest.resources.managedIdentity.name -ErrorAction Stop;if([string]$identity.ClientId -ne [string]$Manifest.resources.managedIdentity.clientId -or [string]$identity.PrincipalId -ne [string]$Manifest.resources.managedIdentity.principalId){throw 'The managed identity IDs no longer match the deployment manifest. Run Provisioning again.'}}
    $true
}

Export-ModuleMember -Function Resolve-ExistingInfrastructure,Convert-ManifestToResolvedResources,Test-ManifestResourcesLive
