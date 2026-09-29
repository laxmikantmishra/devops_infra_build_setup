Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ClientIpAddress {
    param([string]$Cidr)
    if(-not(Test-StringPresent $Cidr)){throw 'DEPLOYMENT_CLIENT_IPV4 or -ClientIpv4 is required for PublicAllowList mode.'}
    Get-PublicIPv4FromCidr $Cidr
}

function Save-NetworkJournal { param($Path,$Journal) if($Path){$Journal.entries=@($Journal.entries);Write-JsonFileAtomic $Path $Journal} }

function Open-DeploymentNetworkAccess {
    [CmdletBinding(SupportsShouldProcess)]
    param($Configuration,$ResolvedResources,$RunContext,[string]$ClientIpv4,[switch]$AllowChanges)
    $policy=$Configuration.deploymentNetwork
    if($policy.mode -eq 'Private'){return [pscustomobject]@{mode='Private';entries=@();journalPath=$null}}
    if(-not($policy.targets.sql -or $policy.targets.keyVault -or $policy.targets.appServiceScm -or $policy.targets.appServiceMain)){return [pscustomobject]@{mode='PublicAllowList';entries=@();changesAllowed=$false;journalPath=$null;reason='No selected release target requires a client IP rule.'}}
    $cidr=if(Test-StringPresent $ClientIpv4){$ClientIpv4}else{$policy.clientIpv4Cidr};$ip=Get-ClientIpAddress $cidr
    if(-not $AllowChanges){return [pscustomobject]@{mode='PublicAllowList';clientIpv4Cidr="$ip/32";entries=@();changesAllowed=$false;journalPath=$null}}
    Import-Module Az.Sql,Az.KeyVault,Az.Websites -ErrorAction Stop
    $entries=[Collections.Generic.List[object]]::new();$ruleName="swarms-$($RunContext.RunId)";$path=Join-Path $RunContext.Directory 'network-access.json'
    $journal=[ordered]@{schemaVersion='1.0';runId=$RunContext.RunId;status='Opening';tenantId=$Configuration.tenantId;subscriptionId=$Configuration.subscriptionId;resourceGroup=$Configuration.resourceGroup.name;mode='PublicAllowList';clientIpv4Cidr="$ip/32";lifetime=$policy.lifetime;entries=$entries}
    if(-not $WhatIfPreference){Save-NetworkJournal $path $journal}
    try {
        if($policy.targets.sql -and $ResolvedResources.sqlServer){
            $existing=Get-AzSqlServerFirewallRule -ResourceGroupName $Configuration.resourceGroup.name -ServerName $ResolvedResources.sqlServer.name -ErrorAction SilentlyContinue|Where-Object{$_.StartIpAddress -eq $ip -and $_.EndIpAddress -eq $ip}
            if($existing){$entries.Add([pscustomobject]@{type='SqlFirewall';resource=$ResolvedResources.sqlServer.id;name=$existing[0].FirewallRuleName;created=$false})}
            elseif($PSCmdlet.ShouldProcess($ResolvedResources.sqlServer.name,"Add temporary SQL firewall rule for $ip")){$null=New-AzSqlServerFirewallRule -ResourceGroupName $Configuration.resourceGroup.name -ServerName $ResolvedResources.sqlServer.name -FirewallRuleName $ruleName -StartIpAddress $ip -EndIpAddress $ip -ErrorAction Stop;$entries.Add([pscustomobject]@{type='SqlFirewall';resource=$ResolvedResources.sqlServer.id;name=$ruleName;created=$true})}
            if(-not $WhatIfPreference){Save-NetworkJournal $path $journal}
        }
        if($policy.targets.keyVault -and $ResolvedResources.keyVault){
            $vault=Get-AzKeyVault -ResourceGroupName $Configuration.resourceGroup.name -VaultName $ResolvedResources.keyVault.name -ErrorAction Stop;$ranges=if($vault.NetworkAcls){@($vault.NetworkAcls.IpAddressRanges)}else{@()};$existing=$ranges|Where-Object{$_ -eq "$ip/32" -or $_ -eq $ip}
            if($existing){$entries.Add([pscustomobject]@{type='KeyVaultIpRule';resource=$ResolvedResources.keyVault.id;name="$ip/32";created=$false})}
            elseif($PSCmdlet.ShouldProcess($ResolvedResources.keyVault.name,"Add Key Vault network rule for $ip/32")){Add-AzKeyVaultNetworkRule -VaultName $ResolvedResources.keyVault.name -ResourceGroupName $Configuration.resourceGroup.name -IpAddressRange "$ip/32" -ErrorAction Stop|Out-Null;$entries.Add([pscustomobject]@{type='KeyVaultIpRule';resource=$ResolvedResources.keyVault.id;name="$ip/32";created=$true})}
            if(-not $WhatIfPreference){Save-NetworkJournal $path $journal}
        }
        if(($policy.targets.appServiceScm -or $policy.targets.appServiceMain) -and $ResolvedResources.appService.webApp){
            $site=$ResolvedResources.appService.webApp.name;$restrictionConfig=Get-AzWebAppAccessRestrictionConfig -ResourceGroupName $Configuration.resourceGroup.name -Name $site -ErrorAction Stop
            foreach($target in @(@{enabled=[bool]$policy.targets.appServiceMain;scm=$false;suffix='main'},@{enabled=[bool]$policy.targets.appServiceScm;scm=$true;suffix='scm'})|Where-Object enabled){
                if($target.scm -and $restrictionConfig.ScmSiteUseMainSiteRestrictionConfig -and @($entries|Where-Object{$_.type -eq 'AppServiceAccess' -and -not $_.targetScm -and $_.ipAddress -eq "$ip/32"}).Count){$entries.Add([pscustomobject]@{type='AppServiceAccess';resource=$ResolvedResources.appService.webApp.id;name='InheritedFromMain';created=$false;targetScm=$true;ipAddress="$ip/32"});continue}
                if($target.scm -and $restrictionConfig.ScmSiteUseMainSiteRestrictionConfig){$rules=@($restrictionConfig.MainSiteAccessRestrictions)}else{$rules=if($target.scm){@($restrictionConfig.ScmSiteAccessRestrictions)}else{@($restrictionConfig.MainSiteAccessRestrictions)}}
                if(-not $rules.Count){$entries.Add([pscustomobject]@{type='AppServiceAccess';resource=$ResolvedResources.appService.webApp.id;name='EndpointAlreadyOpen';created=$false;targetScm=[bool]$target.scm;ipAddress="$ip/32"});continue}
                $existing=@($rules|Where-Object{$_.Action -eq 'Allow' -and $_.IpAddress -in $ip,"$ip/32"})
                if($existing){$entries.Add([pscustomobject]@{type='AppServiceAccess';resource=$ResolvedResources.appService.webApp.id;name=$existing[0].RuleName;created=$false;targetScm=[bool]$target.scm;ipAddress="$ip/32"});continue}
                if($target.scm -and $restrictionConfig.ScmSiteUseMainSiteRestrictionConfig){throw "SCM inherits restricted main-site rules for '$site'. Enable DEPLOYMENT_ALLOW_APP_SERVICE_MAIN or add the client IP to an existing main-site rule."}
                $used=@($rules.Priority);$priority=1;while($used -contains $priority -and $priority -lt 1000){$priority++};if($priority -ge 1000){throw "No App Service access-restriction priority is available for '$site'."}
                $name="$ruleName-$($target.suffix)"
                if($PSCmdlet.ShouldProcess($site,"Add App Service $($target.suffix) access rule for $ip/32")){Add-AzWebAppAccessRestrictionRule -ResourceGroupName $Configuration.resourceGroup.name -WebAppName $site -Name $name -IpAddress "$ip/32" -Priority $priority -Action Allow -TargetScmSite:$target.scm -ErrorAction Stop|Out-Null;$entries.Add([pscustomobject]@{type='AppServiceAccess';resource=$ResolvedResources.appService.webApp.id;name=$name;created=$true;targetScm=[bool]$target.scm;ipAddress="$ip/32";priority=$priority})}
                if(-not $WhatIfPreference){Save-NetworkJournal $path $journal}
            }
        }
        $journal.status='Open';if(-not $WhatIfPreference){Save-NetworkJournal $path $journal}
        [pscustomobject]@{mode='PublicAllowList';clientIpv4Cidr="$ip/32";entries=@($entries);journalPath=$path;changesAllowed=$true}
    } catch {
        $openError=$_;$journal.status='OpenFailed';$journal.error=$openError.Exception.Message;if(-not $WhatIfPreference){Save-NetworkJournal $path $journal}
        if($policy.lifetime -eq 'Temporary' -and $entries.Count){
            try{Close-DeploymentNetworkAccess -Configuration $Configuration -NetworkAccess ([pscustomobject]@{entries=@($entries);journalPath=$path}) -ResolvedResources $ResolvedResources}catch{$journal.status='CleanupFailed';$journal.cleanupError=$_.Exception.Message;if(-not $WhatIfPreference){Save-NetworkJournal $path $journal};throw "Opening deployment access failed: $($openError.Exception.Message). Cleanup also failed: $($_.Exception.Message)"}
        }
        throw $openError
    }
}

function Close-DeploymentNetworkAccess {
    [CmdletBinding(SupportsShouldProcess)]param($Configuration,$NetworkAccess,$ResolvedResources)
    if($null -eq $NetworkAccess -or $Configuration.deploymentNetwork.lifetime -ne 'Temporary'){return}
    foreach($entry in @($NetworkAccess.entries|Where-Object created)){
        if($entry.type -eq 'SqlFirewall' -and $PSCmdlet.ShouldProcess($entry.name,'Remove owned SQL firewall rule')){Remove-AzSqlServerFirewallRule -ResourceGroupName $Configuration.resourceGroup.name -ServerName $ResolvedResources.sqlServer.name -FirewallRuleName $entry.name -Force -ErrorAction Stop|Out-Null}
        elseif($entry.type -eq 'KeyVaultIpRule' -and $PSCmdlet.ShouldProcess($entry.name,'Remove owned Key Vault IP rule')){Remove-AzKeyVaultNetworkRule -VaultName $ResolvedResources.keyVault.name -ResourceGroupName $Configuration.resourceGroup.name -IpAddressRange $entry.name -ErrorAction Stop|Out-Null}
        elseif($entry.type -eq 'AppServiceAccess' -and $PSCmdlet.ShouldProcess($entry.name,'Remove owned App Service access rule')){Remove-AzWebAppAccessRestrictionRule -ResourceGroupName $Configuration.resourceGroup.name -WebAppName $ResolvedResources.appService.webApp.name -Name $entry.name -TargetScmSite:$entry.targetScm -ErrorAction Stop|Out-Null}
    }
    if($NetworkAccess.journalPath -and(Test-Path -LiteralPath $NetworkAccess.journalPath)){$journal=ConvertTo-PlainHashtable (Get-Content -LiteralPath $NetworkAccess.journalPath -Raw|ConvertFrom-Json -Depth 30);$journal.status='Closed';$journal.closedAtUtc=(Get-Date).ToUniversalTime().ToString('o');Write-JsonFileAtomic $NetworkAccess.journalPath $journal}
}

Export-ModuleMember -Function Open-DeploymentNetworkAccess,Close-DeploymentNetworkAccess
