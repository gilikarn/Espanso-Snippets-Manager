<#
.SYNOPSIS
  Removes Espanso Snippets Manager for the current Windows user.

.DESCRIPTION
  Deletes the app folder, its shortcuts and its Settings > Apps entry.
  Your Espanso snippets are never touched. Backups made by the app are kept
  unless you pass -RemoveBackups.
#>
[CmdletBinding()]
param([switch]$RemoveBackups)

$ErrorActionPreference = 'Stop'
$AppName  = 'Espanso Snippets Manager'
$LinkName = 'Espanso Snippets'
$Dest     = Join-Path $env:LOCALAPPDATA "Programs\$AppName"
$Data     = Join-Path $env:LOCALAPPDATA $AppName
$RegKey   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\EspansoSnippetsManager'

for ($p = 47811; $p -lt 47821; $p++) {
  try { Invoke-WebRequest "http://localhost:$p/api/quit" -Method POST -UseBasicParsing -TimeoutSec 1 | Out-Null } catch { Write-Verbose "nothing on $p" }
}
Start-Sleep -Seconds 1

foreach ($folder in @((Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs'), [Environment]::GetFolderPath('Desktop'))) {
  $lnk = Join-Path $folder "$LinkName.lnk"
  if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force }
}
if (Test-Path $RegKey) { Remove-Item -Path $RegKey -Recurse -Force }
if ($RemoveBackups -and (Test-Path -LiteralPath $Data)) { Remove-Item -LiteralPath $Data -Recurse -Force }

if (Test-Path -LiteralPath $Dest) {
  try { Remove-Item -LiteralPath $Dest -Recurse -Force }
  catch {
    # This script lives in that folder; finish the job once it has exited.
    Start-Process cmd.exe -ArgumentList "/c timeout /t 2 /nobreak >nul & rmdir /s /q `"$Dest`"" -WindowStyle Hidden
  }
}

Write-Host "$AppName was removed. Your Espanso snippets were not changed."
if (-not $RemoveBackups -and (Test-Path -LiteralPath $Data)) { Write-Host "Backups are still in $Data" }
