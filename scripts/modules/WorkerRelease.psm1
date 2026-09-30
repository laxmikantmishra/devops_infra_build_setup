Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Publish-WorkerRelease {
    [CmdletBinding(SupportsShouldProcess)]
    param($Configuration,$Resources,[Parameter(Mandatory)][string]$ArtifactPath,[Parameter(Mandatory)][string]$GuestScriptsRoot)
    Import-Module Az.Storage,Az.Compute -ErrorAction Stop
    $path=(Resolve-Path -LiteralPath $ArtifactPath -ErrorAction Stop).Path
    if([IO.Path]::GetExtension($path) -ne '.zip'){throw 'WorkerArtifactPath must be a .zip package.'}
    $hash=Get-FileSha256 $path;$blobName="worker/$($hash.Substring(0,16))-$([IO.Path]::GetFileName($path))"
    $storageKey=$null;$context=$null;$uploaded=$false
    try {
        if($PSCmdlet.ShouldProcess($Resources.deploymentStorage.name,"Upload worker package as $blobName")){Write-DeploymentStatus -Stage WorkerRelease -Status Update -Message ("{0}: {1}..." -f "Upload worker package as $blobName",$Resources.deploymentStorage.name);
            $storageKey=(Get-AzStorageAccountKey -ResourceGroupName $Configuration.resourceGroup.name -Name $Resources.deploymentStorage.name -ErrorAction Stop)[0].Value
            $context=New-AzStorageContext -StorageAccountName $Resources.deploymentStorage.name -StorageAccountKey $storageKey
            Set-AzStorageBlobContent -File $path -Container $Resources.deploymentStorage.container -Blob $blobName -Context $context -Force -ErrorAction Stop|Out-Null;$uploaded=$true
        }
        $uri="$($Resources.deploymentStorage.blobEndpoint)$($Resources.deploymentStorage.container)/$blobName"
        $os=$Resources.workerVm.operatingSystem
        $guestScript=if($os -eq 'Windows'){Join-Path $GuestScriptsRoot 'Install-WorkerWindows.ps1'}else{Join-Path $GuestScriptsRoot 'install-worker-linux.sh'}
        if(-not(Test-Path -LiteralPath $guestScript -PathType Leaf)){throw "Worker guest installer not found: $guestScript"}
        if($PSCmdlet.ShouldProcess($Resources.workerVm.name,"Install worker package $hash")){Write-DeploymentStatus -Stage WorkerRelease -Status Update -Message ("{0}: {1}..." -f "Install worker package $hash",$Resources.workerVm.name);
            $databaseMap=@($Resources.databases|ForEach-Object{[ordered]@{key=$_.key;name=$_.name}})|ConvertTo-Json -Compress
            $parameters=@{ArtifactUri=$uri;ClientId=$Resources.managedIdentity.clientId;KeyVaultUri=$Resources.keyVault.vaultUri;SqlServerFqdn=$Resources.sqlServer.fullyQualifiedDomainName;SqlDatabasesJson=$databaseMap;ApplicationInsightsConnectionString=[string]$Resources.monitoring.applicationInsights.connectionString;ApplicationInsightsAuthenticationString="Authorization=AAD;ClientId=$($Resources.managedIdentity.clientId)";ServiceName=$Configuration.application.worker.serviceName;Executable=$Configuration.application.worker.executable;Arguments=[string]$Configuration.application.worker.arguments;HealthCommand=[string]$Configuration.application.worker.healthCommand;ReleaseId=$hash.Substring(0,16)}
            $command=if($os -eq 'Windows'){'RunPowerShellScript'}else{'RunShellScript'}
            $result=Invoke-AzVMRunCommand -ResourceGroupName $Configuration.resourceGroup.name -VMName $Resources.workerVm.name -CommandId $command -ScriptPath $guestScript -Parameter $parameters -ErrorAction Stop
            if($result.Status -and $result.Status -ne 'Succeeded'){throw "Worker installation Run Command status was '$($result.Status)'."}
        }
        [pscustomobject]@{target='Worker';artifactPath=$path;sha256=$hash;resourceId=$Resources.workerVm.id;status=if($WhatIfPreference){'Preview'}else{'Deployed'}}
    }
    finally {
        if($uploaded -and $context){Write-DeploymentStatus -Stage WorkerRelease -Status Cleanup -Message "Removing staged worker package from $($Resources.deploymentStorage.name)...";try{Remove-AzStorageBlob -Container $Resources.deploymentStorage.container -Blob $blobName -Context $context -Force -ErrorAction Stop|Out-Null}catch{throw "Worker release staging blob cleanup failed for '$blobName': $($_.Exception.Message)"}}
        $storageKey=$null
    }
}
Export-ModuleMember -Function Publish-WorkerRelease
