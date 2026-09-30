BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot '../../scripts/modules/resources/KeyVault.psm1') -Force
}
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../scripts/modules/Common.psm1') -Force
    Import-Module Az.KeyVault
}
Describe 'Key Vault creation command contract' {
    It 'uses only parameters supported by the installed New-AzKeyVault cmdlet' {
        $path=Join-Path $PSScriptRoot '../../scripts/modules/resources/KeyVault.psm1'
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
        $assignment=$ast.Find({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$parameters'},$true)
        $table=$assignment.Find({param($node) $node -is [Management.Automation.Language.HashtableAst]},$true)
        $command=Get-Command New-AzKeyVault -Module Az.KeyVault
        $supported=@($command.Parameters.Keys)+@($command.Parameters.Values|ForEach-Object Aliases)
        foreach($pair in $table.KeyValuePairs){
            $name=$pair.Item1.SafeGetValue()
            $supported | Should -Contain $name -Because "the creation parameter $name must bind to New-AzKeyVault"
        }
        $command.Parameters.Keys | Should -Contain 'DisableRbacAuthorization'
    }
}
Describe 'Key Vault resolution' {
    InModuleScope KeyVault {
        BeforeEach {
            Mock Import-Module {}
            $configuration=@{resources=@{keyVault=@{mode='Auto';name='test-vault'}};resourceGroup=@{name='test-rg'};location='eastus';subscriptionId='subscription';tags=@{};keyVault=@{enableRbac=$true}}
            $expectedVault=[pscustomobject]@{ResourceId='vault-id';VaultName='test-vault';VaultUri='https://test-vault.vault.azure.net/';Location='eastus';EnableRbacAuthorization=$true}
            $script:readCount=0
            Mock Get-AzKeyVault { $script:readCount++; if($script:readCount -gt 1){$expectedVault} }
            Mock New-AzKeyVault { $expectedVault }
        }
        It 'creates with RBAC enabled and re-reads the resulting vault' {
            $result=Resolve-KeyVault -Configuration $configuration
            $result.action | Should -Be 'Create'
            $result.id | Should -Be 'vault-id'
            Should -Invoke New-AzKeyVault -Times 1 -Exactly -ParameterFilter { -not $DisableRbacAuthorization -and $EnablePurgeProtection }
            Should -Invoke Get-AzKeyVault -Times 2 -Exactly
        }
        It 'stops if the newly created vault does not report RBAC enabled' {
            $expectedVault.EnableRbacAuthorization=$false
            { Resolve-KeyVault -Configuration $configuration } | Should -Throw '*did not report Azure RBAC*'
        }
        It 'reuses an existing RBAC vault without creating it' {
            Mock Get-AzKeyVault { $expectedVault }
            (Resolve-KeyVault -Configuration $configuration).action | Should -Be 'Reuse'
            Should -Invoke New-AzKeyVault -Times 0 -Exactly
        }
        It 'rejects an existing access-policy vault without changing it' {
            $expectedVault.EnableRbacAuthorization=$false
            Mock Get-AzKeyVault { $expectedVault }
            { Resolve-KeyVault -Configuration $configuration } | Should -Throw '*does not use Azure RBAC*'
            Should -Invoke New-AzKeyVault -Times 0 -Exactly
        }
        It 'does not create a vault during preview' {
            $result=Resolve-KeyVault -Configuration $configuration -WhatIf
            $result.preview | Should -BeTrue
            Should -Invoke New-AzKeyVault -Times 0 -Exactly
        }
        It 'does not create a missing vault in ReuseOnly' {
            { Resolve-KeyVault -Configuration $configuration -ReuseOnly } | Should -Throw '*does not exist*'
            Should -Invoke New-AzKeyVault -Times 0 -Exactly
        }
    }
}
