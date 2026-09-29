BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../scripts/modules/Common.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '../../scripts/modules/DeploymentManifest.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '../../scripts/modules/Planning.psm1') -Force
}

Describe 'Deployment artifacts' {
    It 'rejects a manifest that is not ready' {
        $path=Join-Path $TestDrive 'manifest.json'
        @{schemaVersion='1.0';artifactType='deployment-manifest';status='Preview'}|ConvertTo-Json|Set-Content $path
        { Import-DeploymentManifest $path } | Should -Throw '*must be a ready deployment-manifest*'
    }

    It 'creates an ordered reuse-only plan with no apply intent' {
        $plan=New-ProvisioningPlan -Configuration @{} -ReuseOnly
        $plan.Count | Should -BeGreaterThan 5
        @($plan|Where-Object intent -ne 'Validate').Count | Should -Be 0
    }
}

Describe 'Public script contracts' {
    It 'contains exactly the three operator entry scripts' {
        $scripts=@(Get-ChildItem (Join-Path $PSScriptRoot '../../scripts') -File -Filter '*.ps1')
        @($scripts.BaseName|Sort-Object) | Should -Be @('Bootstrap','Deployment','Provisioning')
    }

    It 'contains no NotImplementedException guard' {
        $content=Get-ChildItem (Join-Path $PSScriptRoot '../../scripts') -Recurse -File | Get-Content -Raw
        ($content -join "`n") | Should -Not -Match 'NotImplementedException'
    }
}
