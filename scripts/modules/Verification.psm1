Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-SqlDatabaseAccess {
    param($Configuration,$Resources,[pscredential]$SqlAdministratorCredential)
    $mode = Get-SqlAuthenticationMode $Configuration
    if ($mode -eq 'Sql' -and -not $SqlAdministratorCredential) { throw 'SqlAdministratorCredential is required for SQL-authenticated readiness checks.' }
    if (-not (Get-Module -ListAvailable SqlServer)) { throw 'The SqlServer PowerShell module is required for database readiness checks.' }
    Import-Module SqlServer -ErrorAction Stop
    $parameters = @{ServerInstance=$Resources.sqlServer.fullyQualifiedDomainName;Encrypt='Mandatory';ErrorAction='Stop';ConnectionTimeout=30;QueryTimeout=30}
    if ($mode -eq 'Sql') {
        $parameters.Credential = $SqlAdministratorCredential
        $parameters.Query = 'SELECT 1 AS Connected'
    } else {
        $tokenResult = Get-AzAccessToken -ResourceUrl 'https://database.windows.net' -ErrorAction Stop
        $parameters.AccessToken = if ($tokenResult.Token -is [securestring]) { [Net.NetworkCredential]::new('', $tokenResult.Token).Password } else { [string]$tokenResult.Token }
        $literal = $Resources.managedIdentity.name.Replace("'", "''")
        $parameters.Query = "SELECT name FROM sys.database_principals WHERE name=N'$literal'"
    }
    foreach ($db in $Resources.databases) {
        $found = @(Invoke-Sqlcmd @parameters -Database $db.name)
        $checkName = if ($mode -eq 'Sql') { "databaseSqlConnectivity:$($db.key)" } else { "databaseIdentity:$($db.key)" }
        [pscustomobject]@{name=$checkName;ready=($found.Count -gt 0);resourceId=$db.id;authenticationMode=$mode}
    }
}

function Test-ProvisionedInfrastructure {
    param($Configuration,$Resources,[pscredential]$SqlAdministratorCredential)
    Import-Module Az.Websites,Az.Compute,Az.Resources,Az.Sql -ErrorAction Stop
    $checks=[Collections.Generic.List[object]]::new()
    foreach($item in @(@('resourceGroup',$Resources.resourceGroup.id),@('managedIdentity',$Resources.managedIdentity.id),@('keyVault',$Resources.keyVault.id),@('deploymentStorage',$Resources.deploymentStorage.id),@('webApp',$Resources.appService.webApp.id),@('workerVm',$Resources.workerVm.id),@('sqlServer',$Resources.sqlServer.id))){$checks.Add([pscustomobject]@{name=$item[0];ready=(Test-StringPresent $item[1]);resourceId=$item[1]})}
    foreach($db in $Resources.databases){$checks.Add([pscustomobject]@{name="database:$($db.key)";ready=(Test-StringPresent $db.id);resourceId=$db.id})}
    $web=Get-AzWebApp -ResourceGroupName $Configuration.resourceGroup.name -Name $Resources.appService.webApp.name -ErrorAction Stop
    $webAssigned=$web.Identity -and $web.Identity.UserAssignedIdentities -and @($web.Identity.UserAssignedIdentities.Keys) -contains $Resources.managedIdentity.id
    $checks.Add([pscustomobject]@{name='webManagedIdentity';ready=[bool]$webAssigned;resourceId=$Resources.appService.webApp.id})
    $vm=Get-AzVM -ResourceGroupName $Configuration.resourceGroup.name -Name $Resources.workerVm.name -ErrorAction Stop
    $vmAssigned=$vm.Identity -and $vm.Identity.UserAssignedIdentities -and @($vm.Identity.UserAssignedIdentities.Keys) -contains $Resources.managedIdentity.id
    $checks.Add([pscustomobject]@{name='workerManagedIdentity';ready=[bool]$vmAssigned;resourceId=$Resources.workerVm.id})
    $webIntegrated=$web.VirtualNetworkSubnetId -eq $Resources.network.appSubnetId;$checks.Add([pscustomobject]@{name='webVnetIntegration';ready=[bool]$webIntegrated;resourceId=$Resources.network.appSubnetId})
    foreach($rule in @(@{name="$($Configuration.naming.resourceNamePrefix)-SQLVNET-APP-01";subnet=$Resources.network.appSubnetId},@{name="$($Configuration.naming.resourceNamePrefix)-SQLVNET-WORKER-01";subnet=$Resources.network.workerSubnetId})){$found=Get-AzSqlServerVirtualNetworkRule -ResourceGroupName $Configuration.resourceGroup.name -ServerName $Resources.sqlServer.name -VirtualNetworkRuleName $rule.name -ErrorAction SilentlyContinue;$checks.Add([pscustomobject]@{name="sqlNetwork:$($rule.name)";ready=($found -and $found.VirtualNetworkSubnetId -eq $rule.subnet);resourceId=$Resources.sqlServer.id})}
    foreach($role in @(@{id='4633458b-17de-408a-b874-0445c86b69e6';scope=$Resources.keyVault.id;name='keyVaultRole'},@{id='2a2b9908-6ea1-4ae2-8e65-a410df84e7d1';scope=$Resources.deploymentStorage.id;name='storageRole'},@{id='3913510d-42f4-4e42-8a64-420c390055eb';scope=$Resources.monitoring.applicationInsights.id;name='monitoringRole'})){
        $assignment=Get-AzRoleAssignment -ObjectId $Resources.managedIdentity.principalId -Scope $role.scope -ErrorAction Stop|Where-Object RoleDefinitionId -Match "$($role.id)$"
        $checks.Add([pscustomobject]@{name=$role.name;ready=[bool]$assignment;resourceId=$role.scope})
    }
    foreach ($check in @(Test-SqlDatabaseAccess -Configuration $Configuration -Resources $Resources -SqlAdministratorCredential $SqlAdministratorCredential)) { $checks.Add($check) }
    $failed=@($checks|Where-Object{-not $_.ready});if($failed.Count){throw "Provisioning readiness checks failed: $($failed.name -join ', ')."}
    [pscustomobject]@{ready=$true;checks=@($checks)}
}

function Test-WebReleaseHealth {
    param($Configuration,$Resources)
    if(-not $Configuration.deploymentNetwork.targets.appServiceMain){return [pscustomobject]@{status='Skipped';reason='Public app health access is not enabled.'}}
    $path=$Configuration.application.web.healthPath;if(-not $path.StartsWith('/')){$path="/$path"};$uri="https://$($Resources.appService.webApp.hostName)$path"
    $response=Invoke-WebRequest -Uri $uri -Method Get -TimeoutSec 60 -SkipHttpErrorCheck -ErrorAction Stop
    if($response.StatusCode -lt 200 -or $response.StatusCode -ge 400){throw "Web health check returned HTTP $($response.StatusCode) from $uri."}
    [pscustomobject]@{status='Passed';uri=$uri;statusCode=$response.StatusCode}
}

Export-ModuleMember -Function Test-ProvisionedInfrastructure,Test-WebReleaseHealth
