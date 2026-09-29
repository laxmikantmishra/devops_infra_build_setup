Set-StrictMode -Version Latest
function New-ProvisioningPlan { param($Configuration,[switch]$ReuseOnly) $order=@('resourceGroup','managedIdentity','network','logAnalytics','applicationInsights','keyVault','deploymentStorage','sqlServer','databases','appServicePlan','webApp','workerVm','accessAndConfiguration');@($order|ForEach-Object{[pscustomobject]@{step=$_;intent=if($ReuseOnly){'Validate'}else{'ResolveOrCreate'}}}) }
Export-ModuleMember -Function New-ProvisioningPlan
