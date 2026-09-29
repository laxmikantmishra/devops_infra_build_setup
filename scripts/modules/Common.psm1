Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-RunContext {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Environment,[Parameter(Mandatory)][string]$Operation,[Parameter(Mandatory)][string]$OutputDirectory,[switch]$WhatIf)
    $runId = '{0}-{1}-{2}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'), $Operation.ToLowerInvariant(), ([guid]::NewGuid().ToString('N').Substring(0,8))
    $root = if ([IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory } else { Join-Path (Get-Location) $OutputDirectory }
    $runDirectory = Join-Path (Join-Path $root $Environment) $runId
    if (-not $WhatIf) { [void](New-Item -ItemType Directory -Path $runDirectory -Force) }
    [pscustomobject]@{ RunId=$runId; Environment=$Environment; Operation=$Operation; StartedAtUtc=(Get-Date).ToUniversalTime().ToString('o'); Directory=$runDirectory; WhatIf=[bool]$WhatIf; Events=[Collections.Generic.List[object]]::new() }
}

function Add-RunEvent {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$RunContext,[Parameter(Mandatory)][ValidateSet('Info','Warning','Error','Plan','Success')][string]$Level,[Parameter(Mandatory)][string]$Message,[hashtable]$Data=@{})
    $RunContext.Events.Add([pscustomobject][ordered]@{ timestampUtc=(Get-Date).ToUniversalTime().ToString('o'); level=$Level; message=$Message; data=$Data })
    $color = switch ($Level) { Error {'Red'} Warning {'Yellow'} Success {'Green'} Plan {'Cyan'} default {'Gray'} }
    Write-Host ('[{0}] {1}' -f $Level.ToUpperInvariant(),$Message) -ForegroundColor $color
}

function Write-JsonFileAtomic {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$InputObject,[ValidateRange(2,100)][int]$Depth=50)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) { [void](New-Item -ItemType Directory -Path $directory -Force) }
    $temporary = Join-Path $directory ('.{0}.{1}.tmp' -f [IO.Path]::GetFileName($Path),[guid]::NewGuid().ToString('N'))
    try { $InputObject | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $temporary -Encoding utf8NoBOM; Move-Item -LiteralPath $temporary -Destination $Path -Force }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue } }
}

function Get-FileSha256 { param([Parameter(Mandatory)][string]$Path) if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "File not found: $Path" }; (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

function Get-ScriptsSha256 {
    param([Parameter(Mandatory)][string]$ScriptsRoot)
    $files = Get-ChildItem -LiteralPath $ScriptsRoot -Recurse -File | Where-Object Extension -in '.ps1','.psm1' | Sort-Object FullName
    $sha=[Security.Cryptography.SHA256]::Create(); try { $builder=[Text.StringBuilder]::new(); foreach($file in $files){[void]$builder.Append($file.FullName.Substring($ScriptsRoot.Length)).Append(':').Append((Get-FileSha256 $file.FullName)).Append("`n")}; ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($builder.ToString())))).Replace('-','').ToLowerInvariant() } finally {$sha.Dispose()}
}

function ConvertTo-PlainHashtable {
    [CmdletBinding()] param([Parameter(ValueFromPipeline)]$InputObject)
    process {
        if ($null -eq $InputObject) { return $null }
        if ($InputObject -is [Collections.IDictionary]) { $r=[ordered]@{}; foreach($k in $InputObject.Keys){$r[[string]$k]=ConvertTo-PlainHashtable $InputObject[$k]}; return $r }
        if ($InputObject -is [Management.Automation.PSCustomObject]) { $r=[ordered]@{}; foreach($p in $InputObject.PSObject.Properties){$r[$p.Name]=ConvertTo-PlainHashtable $p.Value}; return $r }
        if ($InputObject -is [Collections.IEnumerable] -and $InputObject -isnot [string]) { return @($InputObject | ForEach-Object { ConvertTo-PlainHashtable $_ }) }
        return $InputObject
    }
}

function Test-StringPresent { param($Value) return ($null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value)) }
function ConvertTo-BooleanValue { param([string]$Name,$Value) if($Value -is [bool]){return $Value}; switch(([string]$Value).Trim().ToLowerInvariant()){'true'{return $true}'false'{return $false}default{throw "$Name must be true or false."}} }
function Assert-ValueInSet { param([string]$Name,$Value,[string[]]$Allowed,[switch]$AllowEmpty) if(-not(Test-StringPresent $Value)){if($AllowEmpty){return};throw "$Name is required."};if($Allowed -notcontains [string]$Value){throw "$Name must be one of: $($Allowed -join ', ')."} }
function Assert-AzureResourceId { param([string]$Name,[string]$Value,[switch]$AllowEmpty) if(-not(Test-StringPresent $Value)){if($AllowEmpty){return};throw "$Name is required."};if($Value -notmatch '^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/[^/]+/.+$'){throw "$Name is not a valid resource-group-scoped Azure resource ID."} }
function Get-ResourceIdPart { param([string]$ResourceId,[ValidateSet('SubscriptionId','ResourceGroupName','Provider','Type','Name')][string]$Part) $s=$ResourceId.Trim('/').Split('/');switch($Part){SubscriptionId{$s[1]}ResourceGroupName{$s[3]}Provider{$s[5]}Type{$s[-2]}Name{$s[-1]}} }
function Get-PublicIPv4FromCidr { param([string]$Cidr) if(-not(Test-StringPresent $Cidr)){throw 'A public IPv4 /32 CIDR is required.'};if($Cidr -notmatch '^((?:\d{1,3}\.){3}\d{1,3})/32$'){throw 'Client IP must be an IPv4 /32 CIDR.'};$parsed=$null;if(-not[Net.IPAddress]::TryParse($Matches[1],[ref]$parsed)-or $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork){throw 'Client IP must be a valid IPv4 address.'};$b=$parsed.GetAddressBytes();$reserved=($b[0] -in 0,10,127 -or $b[0] -ge 224 -or ($b[0] -eq 100 -and $b[1] -ge 64 -and $b[1] -le 127) -or ($b[0] -eq 169 -and $b[1] -eq 254) -or ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or ($b[0] -eq 192 -and (($b[1] -eq 168) -or ($b[1] -eq 0 -and $b[2] -eq 2))) -or ($b[0] -eq 198 -and (($b[1] -in 18,19) -or ($b[1] -eq 51 -and $b[2] -eq 100))) -or ($b[0] -eq 203 -and $b[1] -eq 0 -and $b[2] -eq 113));if($reserved){throw 'Client IP must be a public, routable IPv4 address; private and documentation ranges are not allowed.'};$parsed.ToString() }

function Complete-RunReport {
    param([Parameter(Mandatory)]$RunContext,[Parameter(Mandatory)][string]$Status,[string]$ErrorMessage)
    $report=[ordered]@{schemaVersion='1.0';runId=$RunContext.RunId;environment=$RunContext.Environment;operation=$RunContext.Operation;status=$Status;startedAtUtc=$RunContext.StartedAtUtc;completedAtUtc=(Get-Date).ToUniversalTime().ToString('o');whatIf=$RunContext.WhatIf;error=$ErrorMessage;events=@($RunContext.Events)}
    if(-not $RunContext.WhatIf){Write-JsonFileAtomic -Path (Join-Path $RunContext.Directory 'run-report.json') -InputObject $report};[pscustomobject]$report
}

Export-ModuleMember -Function New-RunContext,Add-RunEvent,Write-JsonFileAtomic,Get-FileSha256,Get-ScriptsSha256,ConvertTo-PlainHashtable,Test-StringPresent,ConvertTo-BooleanValue,Assert-ValueInSet,Assert-AzureResourceId,Get-ResourceIdPart,Get-PublicIPv4FromCidr,Complete-RunReport
