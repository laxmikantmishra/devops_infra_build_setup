BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../scripts/modules/Common.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '../../scripts/modules/NetworkAccess.psm1') -Force
}

Describe 'Deployment client IP validation' {
    BeforeEach {
        $configuration=[ordered]@{deploymentNetwork=[ordered]@{mode='PublicAllowList';clientIpv4Cidr=$null;lifetime='Temporary';targets=[ordered]@{sql=$false;keyVault=$false;appServiceScm=$true;appServiceMain=$false}}}
        $run=[pscustomobject]@{RunId='test-run';Directory=$TestDrive}
    }

    It 'rejects a private client address' {
        { Open-DeploymentNetworkAccess -Configuration $configuration -ResolvedResources @{} -RunContext $run -ClientIpv4 '10.2.3.4/32' -AllowChanges } | Should -Throw '*public, routable*'
    }

    It 'rejects a broad CIDR' {
        { Open-DeploymentNetworkAccess -Configuration $configuration -ResolvedResources @{} -RunContext $run -ClientIpv4 '8.8.8.0/24' -AllowChanges } | Should -Throw '*/32*'
    }
}
