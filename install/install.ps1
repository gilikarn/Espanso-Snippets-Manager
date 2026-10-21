<#
.SYNOPSIS
  Installs Espanso Snippets Manager for the current Windows user (no admin needed).

.DESCRIPTION
  Copies the app to %LOCALAPPDATA%\Programs\Espanso Snippets Manager, adds
  Start menu and desktop shortcuts, and registers an uninstaller under
  Settings > Apps. Run it from an extracted release folder, or straight from
  the web:

    irm https://raw.githubusercontent.com/gilikarn/Espanso-Snippets-Manager/main/install/install.ps1 | iex

.PARAMETER Version
  Release tag to install (for example v1.0.0). Defaults to the latest release.

.PARAMETER NoDesktopShortcut
  Only add the Start menu shortcut.

.PARAMETER Launch
  Open the app when installation finishes.
#>
[CmdletBinding()]
param(
  [string]$Version = 'latest',
  [switch]$NoDesktopShortcut,
  [switch]$Launch
)

$ErrorActionPreference = 'Stop'
$Repo     = 'gilikarn/Espanso-Snippets-Manager'
$AppName  = 'Espanso Snippets Manager'
$LinkName = 'Espanso Snippets'
$Dest     = Join-Path $env:LOCALAPPDATA "Programs\$AppName"
$RegKey   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\EspansoSnippetsManager'

function Write-Step([string]$msg) { Write-Host "  $msg" }

# 1. Find the files: next to this script (extracted release) or download them.
$src = $null
$tmp = $null
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'index.html')) -and (Test-Path (Join-Path $PSScriptRoot 'server.ps1'))) {
  $src = $PSScriptRoot
} else {
  $url = if ($Version -eq 'latest') { "https://github.com/$Repo/releases/latest/download/espanso-snippets-manager.zip" }
         else { "https://github.com/$Repo/releases/download/$Version/espanso-snippets-manager.zip" }
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ("esm-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tmp | Out-Null
  Write-Step "Downloading $url"
  $prev = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
  try { Invoke-WebRequest $url -OutFile (Join-Path $tmp 'esm.zip') -UseBasicParsing } finally { $ProgressPreference = $prev }
  Expand-Archive -Path (Join-Path $tmp 'esm.zip') -DestinationPath $tmp -Force
  $src = Join-Path $tmp 'espanso-snippets-manager'
}

Write-Host "Installing $AppName"

# 2. Ask a running copy to close so its files can be replaced.
for ($p = 47811; $p -lt 47821; $p++) {
  try { Invoke-WebRequest "http://localhost:$p/api/quit" -Method POST -UseBasicParsing -TimeoutSec 1 | Out-Null } catch { Write-Verbose "nothing on $p" }
}

# 3. Copy the files.
New-Item -ItemType Directory -Path $Dest -Force | Out-Null
$files = 'index.html', 'server.ps1', 'server.py', 'install.ps1', 'uninstall.ps1', 'icon.ico', 'icon.png', 'icon.svg', 'LICENSE', 'README.md', 'VERSION'
foreach ($f in $files) {
  $from = Join-Path $src $f
  if (Test-Path -LiteralPath $from) { Copy-Item -LiteralPath $from -Destination $Dest -Force }
}
Get-ChildItem -LiteralPath $Dest -File | Unblock-File
Write-Step "Copied the app to $Dest"

# 4. Shortcuts.
$ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$shell = New-Object -ComObject WScript.Shell
function New-AppShortcut([string]$folder) {
  if (-not (Test-Path -LiteralPath $folder)) { return }
  $lnk = $shell.CreateShortcut((Join-Path $folder "$LinkName.lnk"))
  $lnk.TargetPath       = $ps
  $lnk.Arguments        = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Dest\server.ps1`""
  $lnk.WorkingDirectory = $Dest
  $lnk.WindowStyle      = 7
  $lnk.IconLocation     = "$Dest\icon.ico"
  $lnk.Description      = 'Edit your Espanso snippets'
  $lnk.Save()
  Write-Step "Added shortcut: $($lnk.FullName)"
}
New-AppShortcut (Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs')
if (-not $NoDesktopShortcut) { New-AppShortcut ([Environment]::GetFolderPath('Desktop')) }

# 5. Register with Settings > Apps so it can be removed like any other app.
$ver = '0.0.0'
$verFile = Join-Path $Dest 'VERSION'
if (Test-Path -LiteralPath $verFile) { $ver = (Get-Content -LiteralPath $verFile -Raw).Trim() }
New-Item -Path $RegKey -Force | Out-Null
$props = @{
  DisplayName     = $AppName
  DisplayVersion  = $ver
  Publisher       = 'Espanso Snippets Manager contributors'
  DisplayIcon     = "$Dest\icon.ico"
  InstallLocation = $Dest
  URLInfoAbout    = "https://github.com/$Repo"
  UninstallString = "`"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$Dest\uninstall.ps1`""
}
foreach ($k in $props.Keys) { New-ItemProperty -Path $RegKey -Name $k -Value $props[$k] -PropertyType String -Force | Out-Null }
New-ItemProperty -Path $RegKey -Name NoModify -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $RegKey -Name NoRepair -Value 1 -PropertyType DWord -Force | Out-Null

if ($tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host "Done. Open '$LinkName' from the Start menu$(if (-not $NoDesktopShortcut) { ' or your desktop' })."
if (-not (Test-Path (Join-Path $env:APPDATA 'espanso\match'))) {
  Write-Warning "Espanso's match folder wasn't found. Install Espanso from https://espanso.org/install/ first."
}
if ($Launch) {
  Start-Process $ps -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Dest\server.ps1`"" -WindowStyle Hidden
}
