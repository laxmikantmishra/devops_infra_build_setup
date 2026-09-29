BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../scripts/modules/Common.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '../../scripts/modules/Configuration.psm1') -Force
}

Describe 'Environment configuration parsing' {
    It 'parses the complete sandbox example without evaluating it' {
        $configuration=Import-EnvironmentConfiguration (Join-Path $PSScriptRoot '../../config/sandbox.env.example')
        $configuration.environment | Should -Be 'sandbox'
        $configuration.location | Should -Be 'eastus'
        $configuration.resources.deploymentStorage.name | Should -Be 'aeyeuswarmssbxst01'
        $configuration.databases.Count | Should -Be 2
    }

    It 'rejects an unknown key' {
        $path=Join-Path $TestDrive 'unknown.env';Set-Content $path "ENVIRONMENT=sandbox`nUNKNOWN_VALUE=x"
        { Read-EnvFile $path } | Should -Throw '*Unknown env key*'
    }

    It 'rejects a duplicate key' {
        $path=Join-Path $TestDrive 'duplicate.env';Set-Content $path "ENVIRONMENT=sandbox`nENVIRONMENT=prod"
        { Read-EnvFile $path } | Should -Throw '*Duplicate env key*'
    }

    It 'rejects expression syntax' {
        $path=Join-Path $TestDrive 'expression.env';Set-Content $path 'ENVIRONMENT=$(Get-Secret)'
        { Read-EnvFile $path } | Should -Throw '*unsupported expression syntax*'
    }

    It 'validates the bootstrap contract after IDs are supplied' {
        $configuration=Import-EnvironmentConfiguration (Join-Path $PSScriptRoot '../../config/sandbox.env.example')
        $configuration.tenantId='11111111-1111-1111-1111-111111111111';$configuration.subscriptionId='22222222-2222-2222-2222-222222222222'
        Test-EnvironmentConfiguration $configuration Bootstrap | Should -BeTrue
    }

    It 'validates a complete Linux provisioning contract' {
        $configuration=Import-EnvironmentConfiguration (Join-Path $PSScriptRoot '../../config/sandbox.env.example')
        $configuration.tenantId='11111111-1111-1111-1111-111111111111';$configuration.subscriptionId='22222222-2222-2222-2222-222222222222'
        $configuration.deploymentNetwork.clientIpv4Cidr='8.8.8.8/32';$configuration.sql.product='AzureSqlDatabase';$configuration.sql.entraAdminDisplayName='Sql Admins';$configuration.sql.entraAdminObjectId='33333333-3333-3333-3333-333333333333'
        $configuration.application.web.operatingSystem='Linux';$configuration.application.web.runtime='DOTNETCORE|8.0';$configuration.application.worker.operatingSystem='Linux';$configuration.application.worker.executable='Swarms.Worker'
        $keyPath=Join-Path $TestDrive 'worker.pub';Set-Content $keyPath 'ssh-ed25519 AAAATEST';$configuration.application.worker.sshPublicKeyPath=$keyPath
        Test-EnvironmentConfiguration $configuration Provisioning | Should -BeTrue
    }
}
