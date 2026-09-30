Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Invoke-InfrastructureWorkflow {
 [CmdletBinding(SupportsShouldProcess)]param($Configuration,$RunContext,[switch]$ReuseOnly,[pscredential]$SqlAdministratorCredential,[pscredential]$VmAdministratorCredential)
 Add-RunEvent $RunContext Info "[1/10] Resolving bootstrap resource group..."
 $group=Resolve-ResourceGroup -Configuration $Configuration -ReuseOnly -WhatIf:$WhatIfPreference
 Add-RunEvent $RunContext $(if($WhatIfPreference){'Plan'}else{'Success'}) "[1/10] Bootstrap resource group resolution completed."
 Add-RunEvent $RunContext Info "[2/10] Resolving shared managed identity..."
 $identity=Resolve-ManagedIdentity -Configuration $Configuration -ReuseOnly -WhatIf:$WhatIfPreference
 Add-RunEvent $RunContext $(if($WhatIfPreference){'Plan'}else{'Success'}) "[2/10] Shared managed identity resolution completed."
 Add-RunEvent $RunContext Info "[3/10] Resolving virtual network and supporting resources..."
 $network=Resolve-Network -Configuration $Configuration -ReuseOnly:$ReuseOnly -WhatIf:$WhatIfPreference
 Add-RunEvent $RunContext $(if($WhatIfPreference){'Plan'}else{'Success'}) "[3/10] Virtual network and supporting resources resolution completed."
 Add-RunEvent $RunContext Info "[4/10] Resolving log analytics and application insights..."
 $monitoring=Resolve-Monitoring -Configuration $Configuration -ReuseOnly:$ReuseOnly -WhatIf:$WhatIfPreference
 Add-RunEvent $RunContext $(if($WhatIfPreference){'Plan'}else{'Success'}) "[4/10] Log Analytics and Application Insights resolution completed."
 Add-RunEvent $RunContext Info "[5/10] Resolving key vault..."
 $vault=Resolve-KeyVault -Configuration $Configuration -ReuseOnly:$ReuseOnly -WhatIf:$WhatIfPreference
 Add-RunEvent $RunContext $(if($WhatIfPreference){'Plan'}else{'Success'}) "[5/10] Key Vault resolution completed."
 Add-RunEvent $RunContext Info "[6/10] Resolving deployment artifact storage..."
 $storage=Resolve-DeploymentStorage -Configuration $Configuration -ReuseOnly:$ReuseOnly -WhatIf:$WhatIfPreference
 Add-RunEvent $RunContext $(if($WhatIfPreference){'Plan'}else{'Success'}) "[6/10] Deployment artifact storage resolution completed."
 Add-RunEvent $RunContext Info "[7/10] Resolving sql server..."
 $sql=Resolve-SqlServer -Configuration $Configuration -SqlAdministratorCredential $SqlAdministratorCredential -ReuseOnly:$ReuseOnly -WhatIf:$WhatIfPreference
 Add-RunEvent $RunContext $(if($WhatIfPreference){'Plan'}else{'Success'}) "[7/10] SQL server resolution completed."
 Add-RunEvent $RunContext Info "[8/10] Resolving sql databases..."
 $databases=@(Resolve-SqlDatabases -Configuration $Configuration -SqlServer $sql -ReuseOnly:$ReuseOnly -WhatIf:$WhatIfPreference)
 Add-RunEvent $RunContext $(if($WhatIfPreference){'Plan'}else{'Success'}) "[8/10] SQL databases resolution completed."
 Add-RunEvent $RunContext Info "[9/10] Resolving app service plan and web app..."
 $app=Resolve-AppService -Configuration $Configuration -ManagedIdentity $identity -Monitoring $monitoring -ReuseOnly:$ReuseOnly -WhatIf:$WhatIfPreference
 Add-RunEvent $RunContext $(if($WhatIfPreference){'Plan'}else{'Success'}) "[9/10] App Service plan and web app resolution completed."
 Add-RunEvent $RunContext Info "[10/10] Resolving worker virtual machine..."
 $vm=Resolve-WorkerVm -Configuration $Configuration -Network $network -ManagedIdentity $identity -VmAdministratorCredential $VmAdministratorCredential -ReuseOnly:$ReuseOnly -WhatIf:$WhatIfPreference
 Add-RunEvent $RunContext $(if($WhatIfPreference){'Plan'}else{'Success'}) "[10/10] Worker virtual machine resolution completed."
 [pscustomobject]@{resourceGroup=$group;managedIdentity=$identity;network=$network;monitoring=$monitoring;keyVault=$vault;deploymentStorage=$storage;sqlServer=$sql;databases=$databases;appService=$app;workerVm=$vm}
}
Export-ModuleMember -Function Invoke-InfrastructureWorkflow
