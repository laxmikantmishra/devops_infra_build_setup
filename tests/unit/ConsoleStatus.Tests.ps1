BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../scripts/modules/Common.psm1') -Force
}

Describe 'Console status output' {
    It 'writes timestamped status to the information stream, not the result pipeline' {
        $result = Write-DeploymentStatus -Stage Subscription -Status Read -Message 'Retrieving subscription...' -InformationVariable messages
        $result | Should -BeNullOrEmpty
        $messages.Count | Should -Be 1
        $messages[0].MessageData | Should -Match '^\[\d{2}:\d{2}:\d{2}Z\] \[READ\] \[Subscription\] Retrieving subscription'
    }

    It 'keeps captured workflow results usable while messages remain visible' {
        $result = & {
            Write-DeploymentStatus -Stage ResourceGroup -Status Create -Message 'Creating resource group sandbox...'
            [pscustomobject]@{Status='Succeeded';ArtifactPath='bootstrap.json'}
        }
        @($result).Count | Should -Be 1
        $result.Status | Should -Be 'Succeeded'
        $result.ArtifactPath | Should -Be 'bootstrap.json'
    }

    It 'persists orchestrator events without writing data payloads to console' {
        $run = New-RunContext -Environment sandbox -Operation Bootstrap -OutputDirectory $TestDrive -WhatIf
        Add-RunEvent -RunContext $run -Level Info -Message 'Checking providers...' -Data @{internalDetail='not-for-console'} -InformationVariable messages
        $run.Events.Count | Should -Be 1
        $run.Events[0].message | Should -Be 'Checking providers...'
        ($messages.MessageData -join '') | Should -Not -Match 'not-for-console'
    }

    It 'reports preview completion without publishing or claiming a successful apply' {
        $run = New-RunContext -Environment sandbox -Operation Provisioning -OutputDirectory $TestDrive -WhatIf
        $report = Complete-RunReport -RunContext $run -Status Preview -InformationVariable messages
        $report.status | Should -Be 'Preview'
        $report.whatIf | Should -BeTrue
        Test-Path $run.Directory | Should -BeFalse
        ($messages.MessageData -join '') | Should -Match '\[PLAN\].*Preview after'
        ($messages.MessageData -join '') | Should -Not -Match '\[SUCCESS\]|Run reports:'
    }

    It 'reports a failed run as failed and includes its report directory' {
        $run = New-RunContext -Environment sandbox -Operation Deployment -OutputDirectory $TestDrive
        $report = Complete-RunReport -RunContext $run -Status Failed -ErrorMessage 'Test failure' -InformationVariable messages
        $report.status | Should -Be 'Failed'
        ($messages.MessageData -join '') | Should -Match '\[ERROR\].*Failed after'
        ($messages.MessageData -join '') | Should -Not -Match '\[SUCCESS\]'
        Test-Path (Join-Path $run.Directory 'run-report.json') | Should -BeTrue
    }
}
