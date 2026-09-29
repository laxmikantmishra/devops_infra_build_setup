Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Resolve-SqlDatabases {
 [CmdletBinding(SupportsShouldProcess)]param($Configuration,$SqlServer,[switch]$ReuseOnly)
 Import-Module Az.Sql -ErrorAction Stop;$results=@()
 foreach($db in $Configuration.databases){$existing=Get-AzSqlDatabase -ResourceGroupName $Configuration.resourceGroup.name -ServerName $SqlServer.name -DatabaseName $db.name -ErrorAction SilentlyContinue;$id="$($SqlServer.id)/databases/$($db.name)"
  if($existing){$results+=[pscustomobject]@{key=$db.key;action='Reuse';name=$db.name;id=$existing.ResourceId;edition=$existing.Edition;serviceObjective=$existing.CurrentServiceObjectiveName;resource=$existing};continue}
  if($db.mode -eq 'Existing' -or $ReuseOnly){throw "Database '$($db.name)' does not exist."}
  $edition=if(Test-StringPresent $db.edition){$db.edition}else{$Configuration.sql.defaultEdition};$objective=if(Test-StringPresent $db.serviceObjective){$db.serviceObjective}else{$Configuration.sql.defaultServiceObjective}
  if($PSCmdlet.ShouldProcess($db.name,"Create Azure SQL database on $($SqlServer.name)")){$existing=New-AzSqlDatabase -ResourceGroupName $Configuration.resourceGroup.name -ServerName $SqlServer.name -DatabaseName $db.name -Edition $edition -RequestedServiceObjectiveName $objective -Tags $Configuration.tags -ErrorAction Stop;$results+=[pscustomobject]@{key=$db.key;action='Create';name=$db.name;id=$existing.ResourceId;edition=$existing.Edition;serviceObjective=$existing.CurrentServiceObjectiveName;resource=$existing}}else{$results+=[pscustomobject]@{key=$db.key;action='Create';name=$db.name;id=$id;edition=$edition;serviceObjective=$objective;preview=$true}}
 };$results
}
Export-ModuleMember -Function Resolve-SqlDatabases
