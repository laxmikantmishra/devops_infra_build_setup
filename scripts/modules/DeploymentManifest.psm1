Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-DeploymentManifest {
    param($Configuration,$Resources,$RunContext,$Provenance,[switch]$ReuseOnly,$Verification)
    [ordered]@{
        schemaVersion='1.0';artifactType='deployment-manifest';status='Ready';generatedAtUtc=(Get-Date).ToUniversalTime().ToString('o');runId=$RunContext.RunId
        environment=$Configuration.environment;tenantId=$Configuration.tenantId;subscriptionId=$Configuration.subscriptionId;location=$Configuration.location
        resourceGroup=[ordered]@{name=$Resources.resourceGroup.name;resourceId=$Resources.resourceGroup.id}
        resources=[ordered]@{
            managedIdentity=[ordered]@{name=$Resources.managedIdentity.name;resourceId=$Resources.managedIdentity.id;clientId=$Resources.managedIdentity.clientId;principalId=$Resources.managedIdentity.principalId}
            keyVault=[ordered]@{name=$Resources.keyVault.name;resourceId=$Resources.keyVault.id;vaultUri=$Resources.keyVault.vaultUri}
            deploymentStorage=[ordered]@{name=$Resources.deploymentStorage.name;resourceId=$Resources.deploymentStorage.id;blobEndpoint=$Resources.deploymentStorage.blobEndpoint;container=$Resources.deploymentStorage.container}
            applicationInsights=[ordered]@{name=$Resources.monitoring.applicationInsights.name;resourceId=$Resources.monitoring.applicationInsights.id;connectionString=$Resources.monitoring.applicationInsights.connectionString}
            logAnalytics=[ordered]@{name=$Resources.monitoring.logAnalytics.name;resourceId=$Resources.monitoring.logAnalytics.id}
            network=[ordered]@{name=$Resources.network.name;resourceId=$Resources.network.id;workerSubnetId=$Resources.network.workerSubnetId;appSubnetId=$Resources.network.appSubnetId;natGatewayResourceId=$Resources.network.natGateway.id;workloadOutboundIp=$Resources.network.natGateway.outboundIp}
            appServicePlan=[ordered]@{name=$Resources.appService.plan.name;resourceId=$Resources.appService.plan.id}
            webApp=[ordered]@{name=$Resources.appService.webApp.name;resourceId=$Resources.appService.webApp.id;hostName=$Resources.appService.webApp.hostName;healthPath=$Configuration.application.web.healthPath}
            workerVm=[ordered]@{name=$Resources.workerVm.name;resourceId=$Resources.workerVm.id;operatingSystem=$Resources.workerVm.operatingSystem;computerName=$Resources.workerVm.computerName;networkInterfaceId=$Resources.workerVm.networkInterfaceId;osDiskName=$Resources.workerVm.osDiskName}
            sqlServer=[ordered]@{name=$Resources.sqlServer.name;resourceId=$Resources.sqlServer.id;fullyQualifiedDomainName=$Resources.sqlServer.fullyQualifiedDomainName}
            databases=@($Resources.databases|ForEach-Object{[ordered]@{key=$_.key;name=$_.name;resourceId=$_.id}})
        }
        application=[ordered]@{worker=[ordered]@{serviceName=$Configuration.application.worker.serviceName;executable=$Configuration.application.worker.executable;arguments=$Configuration.application.worker.arguments;healthCommand=$Configuration.application.worker.healthCommand}}
        deploymentNetwork=[ordered]@{mode=$Configuration.deploymentNetwork.mode;clientIpv4Cidr=$Configuration.deploymentNetwork.clientIpv4Cidr;lifetime=$Configuration.deploymentNetwork.lifetime;targets=$Configuration.deploymentNetwork.targets;allowRuleChanges=(-not $ReuseOnly)}
        verification=$Verification;provenance=$Provenance
    }
}

function Import-DeploymentManifest {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$Path)
    $resolved=(Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $manifest=ConvertTo-PlainHashtable (Get-Content -LiteralPath $resolved -Raw|ConvertFrom-Json -Depth 100)
    if($manifest.schemaVersion -ne '1.0' -or $manifest.artifactType -ne 'deployment-manifest' -or $manifest.status -ne 'Ready'){throw 'Manifest must be a ready deployment-manifest with schemaVersion 1.0.'}
    foreach($field in 'tenantId','subscriptionId','environment','location'){if(-not(Test-StringPresent $manifest[$field])){throw "Manifest field '$field' is required."}}
    foreach($key in 'managedIdentity','deploymentStorage','webApp','workerVm','sqlServer'){Assert-AzureResourceId "manifest resources.$key.resourceId" $manifest.resources[$key].resourceId}
    $manifest['_sourcePath']=$resolved;$manifest['_sourceSha256']=Get-FileSha256 $resolved
    $manifest
}

function Convert-ManifestToConfiguration {
    param($Manifest)
    [ordered]@{schemaVersion='1.0';environment=$Manifest.environment;tenantId=$Manifest.tenantId;subscriptionId=$Manifest.subscriptionId;location=$Manifest.location;authentication=[ordered]@{mode='Interactive';clientId=$null;certificateThumbprint=$null};resourceGroup=[ordered]@{mode='Existing';name=$Manifest.resourceGroup.name;resourceId=$Manifest.resourceGroup.resourceId};deploymentNetwork=$Manifest.deploymentNetwork;application=[ordered]@{web=[ordered]@{healthPath=$Manifest.resources.webApp.healthPath};worker=$Manifest.application.worker};resources=$Manifest.resources}
}

Export-ModuleMember -Function New-DeploymentManifest,Import-DeploymentManifest,Convert-ManifestToConfiguration
