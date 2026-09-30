BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot '../../scripts/modules/Prerequisites.psm1') -Force
}
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../scripts/modules/Common.psm1') -Force
    Import-Module Az.Resources,Az.Accounts
}
Describe 'Provider metadata reads' {
    InModuleScope Prerequisites {
        BeforeEach {
            $context=[Microsoft.Azure.Commands.Profile.Models.Core.PSAzureContext]::new()
            $context.Name='provider-read-test-context'
            Mock Start-Sleep {}
            Mock Get-AzResourceProvider { [pscustomobject]@{ProviderNamespace='Microsoft.Sql';RegistrationState='Registered'} }
        }
        It 'uses the supplied context and returns only provider metadata' {
            $result=Get-DeploymentResourceProvider -Namespace Microsoft.Sql -Context $context
            $result.RegistrationState | Should -Be 'Registered'
            @($result).Count | Should -Be 1
            Should -Invoke Get-AzResourceProvider -Times 1 -Exactly -ParameterFilter { $DefaultProfile.DefaultContext.Name -eq 'provider-read-test-context' -and $ProviderNamespace -contains 'Microsoft.Sql' }
            Should -Invoke Start-Sleep -Times 0 -Exactly
        }
        It 'retries a stream transfer failure and then returns a complete result' {
            $script:attempt=0
            Mock Get-AzResourceProvider {
                $script:attempt++
                if($script:attempt -lt 3){throw [Net.Http.HttpRequestException]::new('Error while copying content to a stream.')}
                [pscustomobject]@{ProviderNamespace='Microsoft.Sql';RegistrationState='Registered'}
            }
            $result=Get-DeploymentResourceProvider -Namespace Microsoft.Sql -Context $context -InformationVariable messages
            $result.RegistrationState | Should -Be 'Registered'
            Should -Invoke Get-AzResourceProvider -Times 3 -Exactly
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter {$Seconds -eq 2}
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter {$Seconds -eq 4}
            ($messages.MessageData -join ' ') | Should -Match 'attempt 3/3'
            ($messages.MessageData -join ' ') | Should -Match '\[WARNING\].*retrying'
        }
        It 'fails after three attempts instead of reporting a missing provider' {
            Mock Get-AzResourceProvider { throw [Net.Http.HttpRequestException]::new('Error while copying content to a stream.') }
            { Get-DeploymentResourceProvider -Namespace Microsoft.Sql -Context $context } | Should -Throw '*after 3 attempts*No missing-provider assumption*'
            Should -Invoke Get-AzResourceProvider -Times 3 -Exactly
            Should -Invoke Start-Sleep -Times 2 -Exactly
        }
        It 'does not retry forbidden responses' {
            Mock Get-AzResourceProvider { throw [Net.Http.HttpRequestException]::new('Permission failure',$null,[Net.HttpStatusCode]::Forbidden) }
            { Get-DeploymentResourceProvider -Namespace Microsoft.Sql -Context $context } | Should -Throw '*Permission failure*'
            Should -Invoke Get-AzResourceProvider -Times 1 -Exactly
            Should -Invoke Start-Sleep -Times 0 -Exactly
        }
        It 'does not retry a certificate failure hidden by a stream exception' {
            Mock Get-AzResourceProvider { throw [Net.Http.HttpRequestException]::new('Error while copying content to a stream.',[Security.Authentication.AuthenticationException]::new('Remote certificate validation failed')) }
            { Get-DeploymentResourceProvider -Namespace Microsoft.Sql -Context $context } | Should -Throw '*copying content*'
            Should -Invoke Get-AzResourceProvider -Times 1 -Exactly
            Should -Invoke Start-Sleep -Times 0 -Exactly
        }
        It 'retries a 503 response' {
            Mock Get-AzResourceProvider { throw [Net.Http.HttpRequestException]::new('Service unavailable',$null,[Net.HttpStatusCode]::ServiceUnavailable) }
            { Get-DeploymentResourceProvider -Namespace Microsoft.Sql -Context $context } | Should -Throw '*after 3 attempts*'
            Should -Invoke Get-AzResourceProvider -Times 3 -Exactly
        }
        It 'rejects empty enumeration without treating it as absent' {
            Mock Get-AzResourceProvider { @() }
            { Get-DeploymentResourceProvider -Namespace Microsoft.Sql -Context $context } | Should -Throw '*returned no data*'
            Should -Invoke Get-AzResourceProvider -Times 1 -Exactly
        }
        It 'rejects conflicting registration states' {
            Mock Get-AzResourceProvider { @([pscustomobject]@{ProviderNamespace='Microsoft.Sql';RegistrationState='Registered'},[pscustomobject]@{ProviderNamespace='Microsoft.Sql';RegistrationState='NotRegistered'}) }
            { Get-DeploymentResourceProvider -Namespace Microsoft.Sql -Context $context } | Should -Throw '*conflicting registration states*'
        }
        It 'discards partial output from a failed attempt' {
            $script:attempt=0
            Mock Get-AzResourceProvider {
                $script:attempt++
                if($script:attempt -eq 1){
                    [pscustomobject]@{ProviderNamespace='Microsoft.Sql';RegistrationState='NotRegistered'}
                    throw [Net.Http.HttpRequestException]::new('Error while copying content to a stream.')
                }
                [pscustomobject]@{ProviderNamespace='Microsoft.Sql';RegistrationState='Registered'}
            }
            $result=Get-DeploymentResourceProvider -Namespace Microsoft.Sql -Context $context
            @($result).Count | Should -Be 1
            $result.RegistrationState | Should -Be 'Registered'
            Should -Invoke Get-AzResourceProvider -Times 2 -Exactly
        }
    }
}
