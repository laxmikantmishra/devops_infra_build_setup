BeforeDiscovery {
    $modules = Join-Path $PSScriptRoot '../../scripts/modules'
    foreach ($name in 'Common','Configuration','DeploymentManifest','Verification','DatabaseRelease','AccessAndConfiguration') {
        Import-Module (Join-Path $modules "$name.psm1") -Force
    }
    $source=Get-Content (Join-Path $modules 'resources/SqlServer.psm1') -Raw
    New-Module -Name SqlServerResource -ScriptBlock ([scriptblock]::Create($source)) | Import-Module -Force
}

BeforeAll {
    $modules = Join-Path $PSScriptRoot '../../scripts/modules'
    foreach ($name in 'Common','Configuration','DeploymentManifest','Verification','DatabaseRelease','AccessAndConfiguration') {
        Import-Module (Join-Path $modules "$name.psm1") -Force
    }
    Import-Module Az.Sql,SqlServer,Az.Accounts
}

Describe 'SQL authentication configuration' {
    BeforeEach {
        $configuration = Import-EnvironmentConfiguration (Join-Path $PSScriptRoot '../../config/sandbox.env.example')
        $configuration.tenantId='11111111-1111-1111-1111-111111111111'
        $configuration.subscriptionId='22222222-2222-2222-2222-222222222222'
        $configuration.deploymentNetwork.clientIpv4Cidr='8.8.8.8/32'
        $configuration.application.web.operatingSystem='Linux'
        $configuration.application.web.runtime='DOTNETCORE|8.0'
        $configuration.application.worker.operatingSystem='Linux'
        $configuration.application.worker.sshPublicKeyPath='/tmp/worker.pub'
    }

    It 'allows SQL provisioning without Entra administrator fields' {
        $configuration.sql.authenticationMode | Should -Be 'Sql'
        Test-EnvironmentConfiguration $configuration Provisioning | Should -BeTrue
    }
    It 'retains required administrator checks for Entra provisioning' {
        $configuration.sql.authenticationMode='Entra'
        { Test-EnvironmentConfiguration $configuration Provisioning } | Should -Throw '*SQL_ENTRA_ADMIN*'
    }
    It 'rejects unknown authentication modes' {
        $configuration.sql.authenticationMode='Passwordless'
        { Test-EnvironmentConfiguration $configuration Provisioning } | Should -Throw '*SQL_AUTHENTICATION_MODE*'
    }
    It 'preserves Entra behavior for old inputs without a mode' {
        Get-SqlAuthenticationMode @{sql=@{}} | Should -Be 'Entra'
        Get-SqlAuthenticationMode @{} | Should -Be 'Entra'
    }
    It 'preserves SQL mode through manifest conversion' {
        $manifest = @{environment='sandbox';tenantId=$configuration.tenantId;subscriptionId=$configuration.subscriptionId;location='eastus';resourceGroup=@{name='rg';resourceId='rg-id'};deploymentNetwork=@{};resources=@{webApp=@{healthPath='/'};workerVm=@{operatingSystem='Linux'}};application=@{worker=@{serviceName='worker';executable='worker';arguments='';healthCommand=''}};sql=@{authenticationMode='Sql'}}
        $converted=Convert-ManifestToConfiguration $manifest
        Get-SqlAuthenticationMode $converted | Should -Be 'Sql'
        $manifest.Remove('sql')
        Get-SqlAuthenticationMode (Convert-ManifestToConfiguration $manifest) | Should -Be 'Entra'
    }
}

Describe 'SQL server creation' {
    InModuleScope SqlServerResource {
        BeforeEach {
            Mock Import-Module {}
            Mock Get-AzSqlServer { $null }
            Mock New-AzSqlServer { [pscustomobject]@{ResourceId='server-id';ServerName='server';FullyQualifiedDomainName='server.database.windows.net';Location='eastus'} }
            Mock Set-AzSqlServerActiveDirectoryAdministrator {}
            $configuration=@{sql=@{product='AzureSqlDatabase';authenticationMode='Sql';entraAdminObjectId='old-id';entraAdminDisplayName='old-admin'};resources=@{sqlServer=@{mode='Auto';name='server'}};resourceGroup=@{name='rg'};location='eastus';tags=@{};subscriptionId='subscription'}
            $credential=[pscredential]::new('sqladmin',(ConvertTo-SecureString 'test-only' -AsPlainText -Force))
        }
        It 'creates with SQL credentials without assigning an Entra administrator' {
            $result=Resolve-SqlServer $configuration -SqlAdministratorCredential $credential -InformationVariable messages
            ($messages.MessageData -join " ") | Should -Match '\[READ\].*Retrieving SQL server'
            ($messages.MessageData -join " ") | Should -Match '\[CREATE\].*Create Azure SQL logical server'
            $result.action | Should -Be 'Create'
            Should -Invoke New-AzSqlServer -Times 1 -Exactly -ParameterFilter { $SqlAdministratorCredentials -eq $credential }
            Should -Invoke Set-AzSqlServerActiveDirectoryAdministrator -Times 0 -Exactly
        }
        It 'does not reset credentials or an administrator on reuse' {
            Mock Get-AzSqlServer { [pscustomobject]@{ResourceId='server-id';ServerName='server';FullyQualifiedDomainName='server.database.windows.net';Location='eastus'} }
            (Resolve-SqlServer $configuration -SqlAdministratorCredential $credential).action | Should -Be 'Reuse'
            Should -Invoke New-AzSqlServer -Times 0 -Exactly
            Should -Invoke Set-AzSqlServerActiveDirectoryAdministrator -Times 0 -Exactly
        }
        It 'does not create resources in preview' {
            $null=Resolve-SqlServer $configuration -SqlAdministratorCredential $credential -WhatIf -InformationVariable messages
            ($messages.MessageData -join " ") | Should -Not -Match '\[CREATE\]|\[SUCCESS\]'
            Should -Invoke New-AzSqlServer -Times 0 -Exactly
            Should -Invoke Set-AzSqlServerActiveDirectoryAdministrator -Times 0 -Exactly
        }
    }
}

Describe 'SQL database access' {
    InModuleScope AccessAndConfiguration {
        It 'skips managed identity SQL setup for SQL authentication' {
            Mock Get-AzAccessToken { throw 'Entra token must not be requested' }
            Mock Invoke-Sqlcmd { throw 'SQL users must not be changed' }
            Set-SqlManagedIdentityUsers -Configuration @{sql=@{authenticationMode='Sql'}} -Resources @{}
            Should -Invoke Get-AzAccessToken -Times 0 -Exactly
            Should -Invoke Invoke-Sqlcmd -Times 0 -Exactly
        }
    }
    InModuleScope Verification {
        BeforeEach {
            Mock Get-Module { $true }
            Mock Import-Module {}
            Mock Get-AzAccessToken { throw 'Entra token must not be requested' }
            Mock Invoke-Sqlcmd { [pscustomobject]@{Connected=1} }
            $configuration=@{sql=@{authenticationMode='Sql'}}
            $resources=@{sqlServer=@{fullyQualifiedDomainName='server.database.windows.net'};databases=@(@{key='main';name='main';id='db-id'})}
            $credential=[pscredential]::new('sqladmin',(ConvertTo-SecureString 'test-only' -AsPlainText -Force))
        }
        It 'checks connectivity with SQL credentials without checking Entra principals' {
            $check=Test-SqlDatabaseAccess $configuration $resources -SqlAdministratorCredential $credential
            $check.ready | Should -BeTrue
            $check.name | Should -Be 'databaseSqlConnectivity:main'
            Should -Invoke Invoke-Sqlcmd -Times 1 -Exactly -ParameterFilter { $Credential -eq $credential -and $Query -eq 'SELECT 1 AS Connected' -and $Encrypt -eq 'Mandatory' }
            Should -Invoke Get-AzAccessToken -Times 0 -Exactly
        }
        It 'requires credentials rather than falling back to Entra' {
            { Test-SqlDatabaseAccess $configuration $resources } | Should -Throw '*SqlAdministratorCredential is required*'
            Should -Invoke Get-AzAccessToken -Times 0 -Exactly
        }
        It 'propagates connection failures instead of marking ready' {
            Mock Invoke-Sqlcmd { throw 'Login failed' }
            { Test-SqlDatabaseAccess $configuration $resources -SqlAdministratorCredential $credential } | Should -Throw '*Login failed*'
        }
    }
    InModuleScope DatabaseRelease {
        BeforeEach {
            Mock Get-Module { $true }
            Mock Import-Module {}
            Mock Get-AzAccessToken { throw 'Entra token must not be requested' }
            Mock Invoke-Sqlcmd {}
            $configuration=@{sql=@{authenticationMode='Sql'}}
            $resources=@{sqlServer=@{id='server-id';fullyQualifiedDomainName='server.database.windows.net'};databases=@(@{key='main';name='main'})}
            $credential=[pscredential]::new('sqladmin',(ConvertTo-SecureString 'test-only' -AsPlainText -Force))
            $artifact=Join-Path $TestDrive 'migration.sql'
            Set-Content $artifact 'SELECT 1;'
        }
        It 'executes a release with SQL credentials and no token' {
            $release=Publish-DatabaseRelease $configuration $resources $artifact -DatabaseCredential $credential
            $release.status | Should -Be 'Deployed'
            Should -Invoke Invoke-Sqlcmd -Times 1 -Exactly -ParameterFilter { $Credential -eq $credential -and -not $AccessToken }
            Should -Invoke Get-AzAccessToken -Times 0 -Exactly
            ($release | ConvertTo-Json -Depth 10) | Should -Not -Match 'test-only|sqladmin'
        }
        It 'rejects a release missing SQL credentials' {
            { Publish-DatabaseRelease $configuration $resources $artifact } | Should -Throw '*DatabaseCredential is required*'
            Should -Invoke Invoke-Sqlcmd -Times 0 -Exactly
            Should -Invoke Get-AzAccessToken -Times 0 -Exactly
        }
        It 'previews without credentials, tokens or SQL writes' {
            (Publish-DatabaseRelease $configuration $resources $artifact -WhatIf).status | Should -Be 'Preview'
            Should -Invoke Invoke-Sqlcmd -Times 0 -Exactly
            Should -Invoke Get-AzAccessToken -Times 0 -Exactly
        }
    }
}
