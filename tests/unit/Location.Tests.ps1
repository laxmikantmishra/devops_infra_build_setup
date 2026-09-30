BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot '../../scripts/modules/resources/AppService.psm1') -Force
}
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../scripts/modules/Common.psm1') -Force
    Import-Module Az.Websites
}
Describe 'Azure location comparison' {
    It 'accepts display-name casing and whitespace: <Actual>' -ForEach @(
        @{Actual='East US'}, @{Actual='eastus'}, @{Actual='EAST US'}, @{Actual='  East US  '}
    ) {
        Test-AzureLocationMatch -Actual $Actual -Expected eastus | Should -BeTrue
    }
    It 'rejects different, global, missing, and invalid locations: <Actual>' -ForEach @(
        @{Actual='East US 2'}, @{Actual='West US'}, @{Actual='global'}, @{Actual=''}, @{Actual=$null}, @{Actual='East-US'}
    ) {
        Test-AzureLocationMatch -Actual $Actual -Expected eastus | Should -BeFalse
    }
    It 'does not consider two missing locations a match' {
        Test-AzureLocationMatch -Actual '' -Expected '' | Should -BeFalse
    }
}
Describe 'App Service display-name location regression' {
    InModuleScope AppService {
        BeforeEach {
            Mock Import-Module {}
            $configuration=@{
                resources=@{appServicePlan=@{name='test-plan';mode='Auto'};webApp=@{name='test-app';mode='Auto'}}
                resourceGroup=@{name='test-rg'};subscriptionId='test-sub';location='eastus'
                application=@{web=@{operatingSystem='Linux'}}
            }
            $identity=@{id='identity-id'}
            $planResourceId='/subscriptions/test-sub/resourceGroups/test-rg/providers/Microsoft.Web/serverfarms/test-plan'
            $existingPlan=[pscustomobject]@{Location='East US';Reserved=$true}
            $existingWeb=[pscustomobject]@{Location='East US';ServerFarmId=$planResourceId;DefaultHostName='test-app.azurewebsites.net'}
            Mock Get-AzAppServicePlan { $existingPlan }
            Mock Get-AzWebApp { $existingWeb }
            Mock Invoke-ArmPut { throw 'Existing resources must not be written' }
        }
        It 'reuses East US plan and web app without provisioning writes' {
            $result=Resolve-AppService -Configuration $configuration -ManagedIdentity $identity -Monitoring @{}
            $result.plan.id | Should -Be $planResourceId
            $result.webApp.hostName | Should -Be 'test-app.azurewebsites.net'
            $result.preview | Should -BeFalse
            Should -Invoke Invoke-ArmPut -Times 0 -Exactly
        }
        It 'rejects a genuinely different plan region without writes' {
            $existingPlan.Location='East US 2'
            { Resolve-AppService -Configuration $configuration -ManagedIdentity $identity -Monitoring @{} } | Should -Throw '*App Service Plan is in*expected*'
            Should -Invoke Invoke-ArmPut -Times 0 -Exactly
        }
        It 'rejects a genuinely different web app region without writes' {
            $existingWeb.Location='West US'
            { Resolve-AppService -Configuration $configuration -ManagedIdentity $identity -Monitoring @{} } | Should -Throw '*Web app is in*expected*'
            Should -Invoke Invoke-ArmPut -Times 0 -Exactly
        }
        It 'still rejects an incompatible operating system' {
            $existingPlan.Reserved=$false
            { Resolve-AppService -Configuration $configuration -ManagedIdentity $identity -Monitoring @{} } | Should -Throw '*operating system is incompatible*'
            Should -Invoke Invoke-ArmPut -Times 0 -Exactly
        }
    }
}
