Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-TargetNetwork { param($Configuration) Get-AzVirtualNetwork -ResourceGroupName $Configuration.resourceGroup.name -Name $Configuration.resources.network.name -ErrorAction SilentlyContinue }

function Resolve-WorkerNatGateway {
    [CmdletBinding(SupportsShouldProcess)]param($Configuration,$NetworkMode,[switch]$ReuseOnly)
    $pipName="$($Configuration.naming.resourceNamePrefix)-PIP-NAT-01";$natName="$($Configuration.naming.resourceNamePrefix)-NAT-01"
    $pip=Get-AzPublicIpAddress -ResourceGroupName $Configuration.resourceGroup.name -Name $pipName -ErrorAction SilentlyContinue
    $nat=Get-AzNatGateway -ResourceGroupName $Configuration.resourceGroup.name -Name $natName -ErrorAction SilentlyContinue
    if((-not $pip -or -not $nat) -and ($NetworkMode -eq 'Existing' -or $ReuseOnly)){throw 'Existing network must include the configured worker NAT gateway and public IP.'}
    if(-not $pip -and $PSCmdlet.ShouldProcess($pipName,'Create worker NAT public IP')){$pip=New-AzPublicIpAddress -ResourceGroupName $Configuration.resourceGroup.name -Name $pipName -Location $Configuration.location -Sku Standard -AllocationMethod Static -Tag $Configuration.tags -ErrorAction Stop}
    if(-not $nat -and $pip -and $PSCmdlet.ShouldProcess($natName,'Create worker NAT gateway')){$nat=New-AzNatGateway -ResourceGroupName $Configuration.resourceGroup.name -Name $natName -Location $Configuration.location -Sku Standard -PublicIpAddress $pip -Tag $Configuration.tags -ErrorAction Stop}
    if(-not $nat -and -not $WhatIfPreference){throw 'Worker NAT gateway could not be resolved or created.'}
    [pscustomobject]@{name=$natName;id=if($nat){$nat.Id}else{$null};resource=$nat;publicIpName=$pipName;publicIpId=if($pip){$pip.Id}else{$null};outboundIp=if($pip){$pip.IpAddress}else{$null}}
}

function Resolve-Network {
    [CmdletBinding(SupportsShouldProcess)]param($Configuration,[switch]$ReuseOnly)
    Import-Module Az.Network -ErrorAction Stop
    $desired=$Configuration.resources.network;$vnet=Get-TargetNetwork $Configuration
    if($vnet){
        if($vnet.Location -ne $Configuration.location){throw "VNet '$($desired.name)' is in '$($vnet.Location)', expected '$($Configuration.location)'."}
        $worker=$vnet.Subnets|Where-Object Name -eq $Configuration.network.workerSubnetName;$app=$vnet.Subnets|Where-Object Name -eq $Configuration.network.appSubnetName
        if(-not $worker -or -not $app){throw 'Existing VNet is missing required worker/app subnets.'}
        if($worker.AddressPrefix -ne $Configuration.network.workerSubnetPrefix -or $app.AddressPrefix -ne $Configuration.network.appSubnetPrefix){throw 'Existing VNet subnet prefixes do not match configuration.'}
        $workerServices=@($worker.ServiceEndpoints|ForEach-Object Service);$appServices=@($app.ServiceEndpoints|ForEach-Object Service);$appDelegations=@($app.Delegations|ForEach-Object ServiceName)
        if($workerServices -notcontains 'Microsoft.Sql' -or $appServices -notcontains 'Microsoft.Sql'){throw 'Existing worker and app subnets must enable the Microsoft.Sql service endpoint.'}
        if($appDelegations -notcontains 'Microsoft.Web/serverFarms'){throw 'Existing app subnet must be delegated to Microsoft.Web/serverFarms.'}
        $nat=Resolve-WorkerNatGateway -Configuration $Configuration -NetworkMode $desired.mode -ReuseOnly:$ReuseOnly -WhatIf:$WhatIfPreference
        $workerNatId=if($worker.NatGateway){$worker.NatGateway.Id}else{$null};$appNatId=if($app.NatGateway){$app.NatGateway.Id}else{$null}
        if($workerNatId -ne $nat.id -or $appNatId -ne $nat.id){
            if($desired.mode -eq 'Existing' -or $ReuseOnly){throw 'Existing worker and app subnets must be attached to the configured NAT gateway.'}
            if($PSCmdlet.ShouldProcess($vnet.Name,'Attach workload NAT gateway to worker and app subnets')){$worker.NatGateway=[Microsoft.Azure.Commands.Network.Models.PSResourceId]::new();$worker.NatGateway.Id=$nat.id;$app.NatGateway=[Microsoft.Azure.Commands.Network.Models.PSResourceId]::new();$app.NatGateway.Id=$nat.id;$vnet=Set-AzVirtualNetwork -VirtualNetwork $vnet -ErrorAction Stop;$worker=$vnet.Subnets|Where-Object Name -eq $Configuration.network.workerSubnetName;$app=$vnet.Subnets|Where-Object Name -eq $Configuration.network.appSubnetName}
        }
        return [pscustomobject]@{action='Reuse';resource=$vnet;id=$vnet.Id;name=$vnet.Name;location=$vnet.Location;workerSubnetId=$worker.Id;appSubnetId=$app.Id;natGateway=$nat}
    }
    if($desired.mode -eq 'Existing' -or $ReuseOnly){throw "Required VNet '$($desired.name)' does not exist."}
    $nat=Resolve-WorkerNatGateway -Configuration $Configuration -NetworkMode $desired.mode -ReuseOnly:$ReuseOnly -WhatIf:$WhatIfPreference
    $delegation=New-AzDelegation -Name 'webapp-delegation' -ServiceName 'Microsoft.Web/serverFarms'
    $worker=New-AzVirtualNetworkSubnetConfig -Name $Configuration.network.workerSubnetName -AddressPrefix $Configuration.network.workerSubnetPrefix -ServiceEndpoint 'Microsoft.Sql'
    $app=New-AzVirtualNetworkSubnetConfig -Name $Configuration.network.appSubnetName -AddressPrefix $Configuration.network.appSubnetPrefix -ServiceEndpoint 'Microsoft.Sql' -Delegation $delegation
    if($PSCmdlet.ShouldProcess($desired.name,'Create VNet and subnets')){
        $vnet=New-AzVirtualNetwork -ResourceGroupName $Configuration.resourceGroup.name -Name $desired.name -Location $Configuration.location -AddressPrefix $Configuration.network.addressPrefix -Subnet @($worker,$app) -Tag $Configuration.tags -Force -ErrorAction Stop
        $worker=$vnet.Subnets|Where-Object Name -eq $Configuration.network.workerSubnetName;$app=$vnet.Subnets|Where-Object Name -eq $Configuration.network.appSubnetName;$worker.NatGateway=[Microsoft.Azure.Commands.Network.Models.PSResourceId]::new();$worker.NatGateway.Id=$nat.id;$app.NatGateway=[Microsoft.Azure.Commands.Network.Models.PSResourceId]::new();$app.NatGateway.Id=$nat.id;$vnet=Set-AzVirtualNetwork -VirtualNetwork $vnet -ErrorAction Stop
        $worker=$vnet.Subnets|Where-Object Name -eq $Configuration.network.workerSubnetName;$app=$vnet.Subnets|Where-Object Name -eq $Configuration.network.appSubnetName
        return [pscustomobject]@{action='Create';resource=$vnet;id=$vnet.Id;name=$vnet.Name;location=$vnet.Location;workerSubnetId=$worker.Id;appSubnetId=$app.Id;natGateway=$nat}
    }
    $base="/subscriptions/$($Configuration.subscriptionId)/resourceGroups/$($Configuration.resourceGroup.name)/providers/Microsoft.Network/virtualNetworks/$($desired.name)";[pscustomobject]@{action='Create';id=$base;name=$desired.name;location=$Configuration.location;workerSubnetId="$base/subnets/$($Configuration.network.workerSubnetName)";appSubnetId="$base/subnets/$($Configuration.network.appSubnetName)";natGateway=$nat;preview=$true}
}

Export-ModuleMember -Function Get-TargetNetwork,Resolve-Network
