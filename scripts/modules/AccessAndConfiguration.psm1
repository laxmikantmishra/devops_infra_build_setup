Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Ensure-RoleAssignment {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$ObjectId,[string]$RoleDefinitionId,[string]$RoleName,[string]$Scope)
    $existing = Get-AzRoleAssignment -ObjectId $ObjectId -Scope $Scope -ErrorAction Stop | Where-Object RoleDefinitionId -Match "$RoleDefinitionId$"
    if ($existing) { return [pscustomobject]@{ role=$RoleName; scope=$Scope; action='Reuse' } }
    if ($PSCmdlet.ShouldProcess($Scope,"Assign $RoleName to managed identity")) {
        $null = New-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionId $RoleDefinitionId -Scope $Scope -ErrorAction Stop
        return [pscustomobject]@{ role=$RoleName; scope=$Scope; action='Create' }
    }
    [pscustomobject]@{ role=$RoleName; scope=$Scope; action='Create'; preview=$true }
}

function Set-SqlManagedIdentityUsers {
    [CmdletBinding(SupportsShouldProcess)]
    param($Configuration,$Resources)
    if ((Get-SqlAuthenticationMode $Configuration) -eq 'Sql') { return }
    if (-not (Get-Module -ListAvailable SqlServer)) { throw 'The SqlServer PowerShell module is required to configure the managed identity in databases.' }
    Import-Module SqlServer -ErrorAction Stop
    $tokenResult = Get-AzAccessToken -ResourceUrl 'https://database.windows.net' -ErrorAction Stop
    $token = if ($tokenResult.Token -is [securestring]) { [Net.NetworkCredential]::new('', $tokenResult.Token).Password } else { [string]$tokenResult.Token }
    $identityName = $Resources.managedIdentity.name.Replace(']',']]')
    $identityLiteral = $Resources.managedIdentity.name.Replace("'","''")
    foreach ($database in $Resources.databases) {
        $commands = [Collections.Generic.List[string]]::new()
        $commands.Add("IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$identityLiteral') CREATE USER [$identityName] FROM EXTERNAL PROVIDER;")
        foreach ($role in @($Configuration.sql.runtimeRoles)) {
            if ($role -notmatch '^db_[A-Za-z0-9_]+$') { throw "Unsafe SQL role name '$role'." }
            $commands.Add("IF IS_ROLEMEMBER(N'$role', N'$identityLiteral') <> 1 ALTER ROLE [$role] ADD MEMBER [$identityName];")
        }
        if ($PSCmdlet.ShouldProcess($database.name,'Create managed identity database user and role memberships')) {
            Invoke-Sqlcmd -ServerInstance $Resources.sqlServer.fullyQualifiedDomainName -Database $database.name -AccessToken $token -Query ($commands -join "`n") -Encrypt Mandatory -ErrorAction Stop | Out-Null
        }
    }
}

function Invoke-AccessAndConfiguration {
    [CmdletBinding(SupportsShouldProcess)]
    param($Configuration,$Resources,[switch]$ReuseOnly)
    Import-Module Az.Resources,Az.Accounts,Az.Websites,Az.Compute,Az.Sql -ErrorAction Stop
    if ($ReuseOnly) { return @() }
    $results = [Collections.Generic.List[object]]::new()
    $results.Add((Ensure-RoleAssignment -ObjectId $Resources.managedIdentity.principalId -RoleDefinitionId '4633458b-17de-408a-b874-0445c86b69e6' -RoleName 'Key Vault Secrets User' -Scope $Resources.keyVault.id -WhatIf:$WhatIfPreference))
    $results.Add((Ensure-RoleAssignment -ObjectId $Resources.managedIdentity.principalId -RoleDefinitionId '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1' -RoleName 'Storage Blob Data Reader' -Scope $Resources.deploymentStorage.id -WhatIf:$WhatIfPreference))
    $results.Add((Ensure-RoleAssignment -ObjectId $Resources.managedIdentity.principalId -RoleDefinitionId '3913510d-42f4-4e42-8a64-420c390055eb' -RoleName 'Monitoring Metrics Publisher' -Scope $Resources.monitoring.applicationInsights.id -WhatIf:$WhatIfPreference))

    $containerId = "$($Resources.deploymentStorage.id)/blobServices/default/containers/$($Resources.deploymentStorage.container)"
    if ($PSCmdlet.ShouldProcess($Resources.deploymentStorage.container,'Create or update private release container')) {
        $response = Invoke-AzRestMethod -Method PUT -Path "${containerId}?api-version=2023-05-01" -Payload '{"properties":{"publicAccess":"None"}}' -ErrorAction Stop
        if ($response.StatusCode -notin 200,201) { throw "Creating release container failed with HTTP $($response.StatusCode): $($response.Content)" }
    }

    $webId = $Resources.appService.webApp.id
    if ($PSCmdlet.ShouldProcess($Resources.appService.webApp.name,'Attach shared managed identity and configure telemetry')) {
        $webBefore=Get-AzWebApp -ResourceGroupName $Configuration.resourceGroup.name -Name $Resources.appService.webApp.name -ErrorAction Stop;$identityMap=[ordered]@{}
        if($webBefore.Identity -and $webBefore.Identity.UserAssignedIdentities){foreach($id in $webBefore.Identity.UserAssignedIdentities.Keys){$identityMap[$id]=[ordered]@{}}};$identityMap[$Resources.managedIdentity.id]=[ordered]@{}
        $identityType=if($webBefore.Identity -and [string]$webBefore.Identity.Type -match 'SystemAssigned'){'SystemAssigned, UserAssigned'}else{'UserAssigned'}
        $body = [ordered]@{ identity=[ordered]@{type=$identityType;userAssignedIdentities=$identityMap};properties=[ordered]@{keyVaultReferenceIdentity=$Resources.managedIdentity.id;virtualNetworkSubnetId=$Resources.network.appSubnetId;vnetRouteAllEnabled=$true} } | ConvertTo-Json -Depth 20 -Compress
        $response = Invoke-AzRestMethod -Method PATCH -Path "${webId}?api-version=2024-11-01" -Payload $body -ErrorAction Stop
        if ($response.StatusCode -notin 200,202) { throw "Attaching the web managed identity failed with HTTP $($response.StatusCode)." }
        $web = Get-AzWebApp -ResourceGroupName $Configuration.resourceGroup.name -Name $Resources.appService.webApp.name -ErrorAction Stop
        $settings = @{};if($web.SiteConfig.AppSettings -is [Collections.IDictionary]){foreach($key in $web.SiteConfig.AppSettings.Keys){$settings[$key]=$web.SiteConfig.AppSettings[$key]}}else{foreach($item in @($web.SiteConfig.AppSettings)){if($item.Name){$settings[$item.Name]=$item.Value}}}
        foreach($key in $Configuration.application.web.appSettings.Keys){$settings[$key]=[string]$Configuration.application.web.appSettings[$key]}
        $settings['AZURE_CLIENT_ID']=$Resources.managedIdentity.clientId
        $settings['KEY_VAULT_URI']=$Resources.keyVault.vaultUri
        $settings['SQL_SERVER_FQDN']=$Resources.sqlServer.fullyQualifiedDomainName
        $settings['SQL_DATABASES_JSON']=(@($Resources.databases|ForEach-Object{[ordered]@{key=$_.key;name=$_.name}})|ConvertTo-Json -Compress)
        if(Test-StringPresent $Resources.monitoring.applicationInsights.connectionString){$settings['APPLICATIONINSIGHTS_CONNECTION_STRING']=$Resources.monitoring.applicationInsights.connectionString;$settings['APPLICATIONINSIGHTS_AUTHENTICATION_STRING']="Authorization=AAD;ClientId=$($Resources.managedIdentity.clientId)"}
        Set-AzWebApp -ResourceGroupName $Configuration.resourceGroup.name -Name $Resources.appService.webApp.name -AppSettings $settings -ErrorAction Stop | Out-Null
    }

    $vm = Get-AzVM -ResourceGroupName $Configuration.resourceGroup.name -Name $Resources.workerVm.name -ErrorAction Stop
    $assigned = $vm.Identity -and $vm.Identity.UserAssignedIdentities -and $vm.Identity.UserAssignedIdentities.Keys -contains $Resources.managedIdentity.id
    if (-not $assigned -and $PSCmdlet.ShouldProcess($Resources.workerVm.name,'Attach shared managed identity')) { $identityIds=@($Resources.managedIdentity.id);if($vm.Identity -and $vm.Identity.UserAssignedIdentities){$identityIds+=@($vm.Identity.UserAssignedIdentities.Keys)};$identityType=if($vm.Identity -and [string]$vm.Identity.Type -match 'SystemAssigned'){'SystemAssignedUserAssigned'}else{'UserAssigned'};Update-AzVM -ResourceGroupName $Configuration.resourceGroup.name -VM $vm -IdentityType $identityType -IdentityID @($identityIds|Select-Object -Unique) -ErrorAction Stop | Out-Null }
    foreach($rule in @(@{name="$($Configuration.naming.resourceNamePrefix)-SQLVNET-APP-01";subnet=$Resources.network.appSubnetId},@{name="$($Configuration.naming.resourceNamePrefix)-SQLVNET-WORKER-01";subnet=$Resources.network.workerSubnetId})){
        $existing=Get-AzSqlServerVirtualNetworkRule -ResourceGroupName $Configuration.resourceGroup.name -ServerName $Resources.sqlServer.name -VirtualNetworkRuleName $rule.name -ErrorAction SilentlyContinue
        if(-not $existing -and $PSCmdlet.ShouldProcess($Resources.sqlServer.name,"Add SQL virtual network rule $($rule.name)")){New-AzSqlServerVirtualNetworkRule -ResourceGroupName $Configuration.resourceGroup.name -ServerName $Resources.sqlServer.name -VirtualNetworkRuleName $rule.name -VirtualNetworkSubnetId $rule.subnet -ErrorAction Stop|Out-Null}
        elseif($existing -and $existing.VirtualNetworkSubnetId -ne $rule.subnet){throw "SQL virtual network rule '$($rule.name)' points to a different subnet."}
    }
    Set-SqlManagedIdentityUsers -Configuration $Configuration -Resources $Resources -WhatIf:$WhatIfPreference
    @($results)
}

Export-ModuleMember -Function Invoke-AccessAndConfiguration
