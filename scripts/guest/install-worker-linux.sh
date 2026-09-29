#!/usr/bin/env bash
set -euo pipefail
declare ArtifactUri='' ClientId='' KeyVaultUri='' SqlServerFqdn='' SqlDatabasesJson='' ApplicationInsightsConnectionString='' ApplicationInsightsAuthenticationString='' ServiceName='' Executable='' Arguments='' HealthCommand='' ReleaseId=''
while (($#)); do key="$1"; shift; value="${1-}"; shift || true; key="${key#--}"; key="${key#-}"; printf -v "$key" '%s' "$value"; done
for value in ArtifactUri ClientId KeyVaultUri SqlServerFqdn SqlDatabasesJson ServiceName Executable ReleaseId; do [[ -n "${!value}" ]] || { echo "$value is required" >&2; exit 2; }; done
token_uri="http://169.254.169.254/metadata/identity/oauth2/token?api-version=2019-08-01&resource=https%3A%2F%2Fstorage.azure.com%2F&client_id=${ClientId}"
token="$(curl -fsS -H Metadata:true "$token_uri" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')"
[[ -n "$token" ]] || { echo 'Managed identity token acquisition failed.' >&2; exit 3; }
root='/opt/swarms-worker'; release="$root/releases/$ReleaseId"; archive="/tmp/worker-$ReleaseId.zip"
mkdir -p "$release"
curl -fsS -H "Authorization: Bearer $token" -H 'x-ms-version: 2023-11-03' "$ArtifactUri" -o "$archive"
command -v unzip >/dev/null || { echo 'unzip is required on the worker VM.' >&2; exit 4; }
unzip -oq "$archive" -d "$release"
binary="$release/$Executable"; [[ -f "$binary" ]] || { echo "Worker executable not found: $binary" >&2; exit 5; }; chmod +x "$binary"
service_unit="/etc/systemd/system/${ServiceName}.service"
escape_systemd() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
client_id_escaped="$(escape_systemd "$ClientId")"; vault_uri_escaped="$(escape_systemd "$KeyVaultUri")"
ai_connection_escaped="$(escape_systemd "$ApplicationInsightsConnectionString")"; ai_auth_escaped="$(escape_systemd "$ApplicationInsightsAuthenticationString")"
sql_server_escaped="$(escape_systemd "$SqlServerFqdn")"; sql_databases_escaped="$(escape_systemd "$SqlDatabasesJson")"
cat > "$service_unit" <<UNIT
[Unit]
Description=Swarms worker service
After=network-online.target
[Service]
Type=simple
WorkingDirectory=$release
Environment="AZURE_CLIENT_ID=$client_id_escaped"
Environment="KEY_VAULT_URI=$vault_uri_escaped"
Environment="SQL_SERVER_FQDN=$sql_server_escaped"
Environment="SQL_DATABASES_JSON=$sql_databases_escaped"
Environment="APPLICATIONINSIGHTS_CONNECTION_STRING=$ai_connection_escaped"
Environment="APPLICATIONINSIGHTS_AUTHENTICATION_STRING=$ai_auth_escaped"
ExecStart=$binary $Arguments
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable "$ServiceName"
systemctl restart "$ServiceName"
systemctl is-active --quiet "$ServiceName"
if [[ -n "$HealthCommand" ]]; then bash -lc "$HealthCommand"; fi
rm -f "$archive"
