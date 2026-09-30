Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-DeploymentStorage {
    [CmdletBinding(SupportsShouldProcess)]
    param($Configuration, [switch]$ReuseOnly)

    Import-Module Az.Storage -ErrorAction Stop
    $desired = $Configuration.resources.deploymentStorage
    Write-DeploymentStatus -Stage DeploymentStorage -Status Read -Message "Retrieving deployment storage account $($desired.name)...";$account = Get-AzStorageAccount -ResourceGroupName $Configuration.resourceGroup.name -Name $desired.name -ErrorAction SilentlyContinue
    if($account){if($account.Location -ne $Configuration.location){throw "Deployment storage account '$($desired.name)' is in '$($account.Location)', expected '$($Configuration.location)'."};if($account.EnableHttpsTrafficOnly -eq $false){throw "Deployment storage account '$($desired.name)' must require HTTPS."};if($account.AllowBlobPublicAccess -eq $true){throw "Deployment storage account '$($desired.name)' must disable blob public access."}}
    if ($account) { Write-DeploymentStatus -Stage DeploymentStorage -Status Reuse -Message "Using existing storage account $($desired.name)." }
    if (-not $account) {
        if ($desired.mode -eq 'Existing' -or $ReuseOnly) { throw "Deployment storage account '$($desired.name)' does not exist." }
        if ($PSCmdlet.ShouldProcess($desired.name, 'Create deployment artifact storage account')) {Write-DeploymentStatus -Stage DeploymentStorage -Status Create -Message ("{0}: {1}..." -f 'Create deployment artifact storage account',$desired.name);
            $account = New-AzStorageAccount -ResourceGroupName $Configuration.resourceGroup.name -Name $desired.name -Location $Configuration.location -SkuName $Configuration.deploymentStorage.sku -Kind StorageV2 -EnableHttpsTrafficOnly $true -MinimumTlsVersion TLS1_2 -AllowBlobPublicAccess $false -Tag $Configuration.tags -ErrorAction Stop
        }
    }
    $id = if ($account) { $account.Id } else { "/subscriptions/$($Configuration.subscriptionId)/resourceGroups/$($Configuration.resourceGroup.name)/providers/Microsoft.Storage/storageAccounts/$($desired.name)" }
    [pscustomobject]@{ action=if($account){'Reuse'}else{'Create'}; id=$id; name=$desired.name; location=$Configuration.location; blobEndpoint="https://$($desired.name).blob.core.windows.net/"; container=$Configuration.deploymentStorage.container; resource=$account; preview=(-not $account) }
}

Export-ModuleMember -Function Resolve-DeploymentStorage
