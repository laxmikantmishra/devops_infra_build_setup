Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Publish-DatabaseRelease {
    [CmdletBinding(SupportsShouldProcess)]param($Configuration,$Resources,[Parameter(Mandatory)][string]$ArtifactPath,[pscredential]$DatabaseCredential)
    if ((Get-SqlAuthenticationMode $Configuration) -eq 'Sql' -and -not $DatabaseCredential -and -not $WhatIfPreference) { throw 'DatabaseCredential is required for SQL-authenticated database releases.' }
    if(-not(Get-Module -ListAvailable SqlServer)){throw 'The SqlServer PowerShell module is required for database releases.'};Import-Module SqlServer -ErrorAction Stop
    $resolved=(Resolve-Path -LiteralPath $ArtifactPath -ErrorAction Stop).Path
    $isDirectory=Test-Path -LiteralPath $resolved -PathType Container;$rootScripts=if($isDirectory){@(Get-ChildItem -LiteralPath $resolved -File -Filter '*.sql'|Sort-Object Name)}else{@(Get-Item -LiteralPath $resolved)}
    if(-not $isDirectory -and @($rootScripts|Where-Object Extension -ne '.sql').Count){throw 'DatabaseArtifactPath must be a .sql file or a directory containing .sql files.'}
    $token=$null;if($null -eq $DatabaseCredential -and -not $WhatIfPreference){$tokenResult=Get-AzAccessToken -ResourceUrl 'https://database.windows.net' -ErrorAction Stop;$token=if($tokenResult.Token -is [securestring]){[Net.NetworkCredential]::new('',$tokenResult.Token).Password}else{[string]$tokenResult.Token}}
    $results=@();foreach($db in $Resources.databases){$scripts=@($rootScripts);if($isDirectory){$databaseDirectory=Join-Path $resolved $db.key;if(Test-Path -LiteralPath $databaseDirectory -PathType Container){$scripts+=@(Get-ChildItem -LiteralPath $databaseDirectory -File -Filter '*.sql'|Sort-Object Name)}};if(-not $scripts.Count){throw "No .sql migration files were found for database key '$($db.key)'."};foreach($script in $scripts){if($PSCmdlet.ShouldProcess("$($db.name)/$($script.Name)",'Execute database migration')){Write-DeploymentStatus -Stage DatabaseRelease -Status Update -Message ("{0}: {1}..." -f 'Execute database migration',"$($db.name)/$($script.Name)");$p=@{ServerInstance=$Resources.sqlServer.fullyQualifiedDomainName;Database=$db.name;InputFile=$script.FullName;Encrypt='Mandatory';ErrorAction='Stop'};if($DatabaseCredential){$p.Credential=$DatabaseCredential}else{$p.AccessToken=$token};Invoke-Sqlcmd @p|Out-Null};$scriptLabel=if($isDirectory){$script.FullName.Substring($resolved.Length).TrimStart([IO.Path]::DirectorySeparatorChar)}else{$script.Name};$results+=[pscustomobject]@{databaseKey=$db.key;database=$db.name;script=$scriptLabel;sha256=Get-FileSha256 $script.FullName;status=if($WhatIfPreference){'Preview'}else{'Applied'}}}}
    [pscustomobject]@{target='Database';resourceId=$Resources.sqlServer.id;items=$results;status=if($WhatIfPreference){'Preview'}else{'Deployed'}}
}
Export-ModuleMember -Function Publish-DatabaseRelease
