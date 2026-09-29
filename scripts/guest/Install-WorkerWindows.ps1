#Requires -Version 5.1
param(
    [Parameter(Mandatory)][string]$ArtifactUri,
    [Parameter(Mandatory)][string]$ClientId,
    [Parameter(Mandatory)][string]$KeyVaultUri,
    [Parameter(Mandatory)][string]$SqlServerFqdn,
    [Parameter(Mandatory)][string]$SqlDatabasesJson,
    [string]$ApplicationInsightsConnectionString,
    [string]$ApplicationInsightsAuthenticationString,
    [Parameter(Mandatory)][string]$ServiceName,
    [Parameter(Mandatory)][string]$Executable,
    [string]$Arguments,
    [string]$HealthCommand,
    [Parameter(Mandatory)][string]$ReleaseId
)
$ErrorActionPreference='Stop'
$headers=@{Metadata='true'}
$tokenUri="http://169.254.169.254/metadata/identity/oauth2/token?api-version=2019-08-01&resource=https%3A%2F%2Fstorage.azure.com%2F&client_id=$([uri]::EscapeDataString($ClientId))"
$token=(Invoke-RestMethod -Uri $tokenUri -Headers $headers -Method Get).access_token
$root='C:\Apps\SwarmsWorker';$release=Join-Path $root "releases\$ReleaseId";$zip=Join-Path $env:TEMP "worker-$ReleaseId.zip"
New-Item -ItemType Directory -Path $release -Force|Out-Null
Invoke-WebRequest -Uri $ArtifactUri -Headers @{Authorization="Bearer $token";'x-ms-version'='2023-11-03'} -OutFile $zip
Expand-Archive -LiteralPath $zip -DestinationPath $release -Force
$binary=Join-Path $release $Executable;if(-not(Test-Path -LiteralPath $binary)){throw "Worker executable not found after extraction: $binary"}
$existing=Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if($existing){Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue;sc.exe config $ServiceName binPath= ('"{0}" {1}' -f $binary,$Arguments)|Out-Null}else{New-Service -Name $ServiceName -BinaryPathName ('"{0}" {1}' -f $binary,$Arguments) -StartupType Automatic|Out-Null}
$environment=@("AZURE_CLIENT_ID=$ClientId","KEY_VAULT_URI=$KeyVaultUri","SQL_SERVER_FQDN=$SqlServerFqdn","SQL_DATABASES_JSON=$SqlDatabasesJson")
if($ApplicationInsightsConnectionString){$environment+="APPLICATIONINSIGHTS_CONNECTION_STRING=$ApplicationInsightsConnectionString"}
if($ApplicationInsightsAuthenticationString){$environment+="APPLICATIONINSIGHTS_AUTHENTICATION_STRING=$ApplicationInsightsAuthenticationString"}
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName" -Name Environment -PropertyType MultiString -Value $environment -Force|Out-Null
Start-Service -Name $ServiceName
if((Get-Service -Name $ServiceName).Status -ne 'Running'){throw "Service '$ServiceName' did not start."}
if($HealthCommand){$health=Start-Process -FilePath $env:ComSpec -ArgumentList '/d','/s','/c',$HealthCommand -Wait -PassThru -NoNewWindow;if($health.ExitCode -ne 0){throw "Worker health command exited with code $($health.ExitCode)."}}
Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
