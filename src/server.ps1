<#
.SYNOPSIS
  Espanso Snippets Manager - local helper for Windows.

.DESCRIPTION
  Serves the editor page and reads/writes the .yml files in Espanso's match
  folder. Listens on localhost only and stops by itself when the editor
  window is closed. Runs on the Windows PowerShell 5.1 that ships with
  Windows (and on PowerShell 7). Nothing to install.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File server.ps1
  powershell -ExecutionPolicy Bypass -File server.ps1 -ConfigDir D:\Sync\espanso
#>
[CmdletBinding()]
param(
  [int]$Port = $(if ($env:ESM_PORT) { [int]$env:ESM_PORT } else { 47811 }),
  [string]$ConfigDir,
  [string]$BackupDir = $env:ESM_BACKUP_DIR,
  [switch]$NoBrowser,
  [switch]$PrintConfig
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$AppId       = 'espanso-snippets-manager'
$KeepBackups = 30
$Root        = Split-Path -Parent $MyInvocation.MyCommand.Path
$Utf8        = New-Object System.Text.UTF8Encoding($false)

# ----------------------------------------------------------------- folders
function Find-ConfigDir {
  foreach ($v in @($ConfigDir, $env:ESPANSO_CONFIG_DIR)) { if ($v) { return $v } }
  $cli = $null
  $cmd = Get-Command espanso -ErrorAction SilentlyContinue
  if ($cmd) { $cli = $cmd.Source }
  elseif ($env:LOCALAPPDATA -and (Test-Path (Join-Path $env:LOCALAPPDATA 'Programs\Espanso\espanso.cmd'))) {
    $cli = Join-Path $env:LOCALAPPDATA 'Programs\Espanso\espanso.cmd'
  }
  if ($cli) {
    try {
      $out = @(& $cli path config 2>$null) | Where-Object { $_ -and $_.Trim() } | Select-Object -Last 1
      if ($out) {
        $candidate = ($out -replace '^\s*config:\s*', '').Trim()
        if (Test-Path -LiteralPath (Join-Path $candidate 'match')) { return $candidate }
      }
    } catch { Write-Verbose "espanso path failed: $_" }
  }
  Join-Path $env:APPDATA 'espanso'
}

$EspansoDir = Find-ConfigDir
$MatchDir   = Join-Path $EspansoDir 'match'
if (-not $BackupDir) { $BackupDir = Join-Path $env:LOCALAPPDATA 'Espanso Snippets Manager\backups' }

if ($PrintConfig) {
  [ordered]@{ config = $EspansoDir; match = $MatchDir; backups = $BackupDir } | ConvertTo-Json
  return
}

function Open-UI([string]$url) {
  if ($NoBrowser) { return }
  $argList = "--app=$url --window-size=1240,800"
  $candidates = @(
    @(${env:ProgramFiles(x86)}, 'Microsoft\Edge\Application\msedge.exe'),
    @($env:ProgramFiles,        'Microsoft\Edge\Application\msedge.exe'),
    @($env:ProgramFiles,        'Google\Chrome\Application\chrome.exe'),
    @($env:LOCALAPPDATA,        'Google\Chrome\Application\chrome.exe')
  )
  foreach ($c in $candidates) {
    if (-not $c[0]) { continue }
    $exe = Join-Path $c[0] $c[1]
    if (Test-Path -LiteralPath $exe) { Start-Process $exe $argList; return }
  }
  Start-Process $url
}

# ----------------------------------------------------------------- start (or reuse) the listener
$listener = $null
for ($p = $Port; $p -lt $Port + 10; $p++) {
  try {
    $r = Invoke-WebRequest "http://localhost:$p/api/ping" -UseBasicParsing -TimeoutSec 1
    if ($r.Content -match $AppId) { Open-UI "http://localhost:$p/"; return }
  } catch { Write-Verbose "port $p is free or busy: $_" }
  try {
    $l = New-Object System.Net.HttpListener
    $l.Prefixes.Add("http://localhost:$p/")
    $l.Start()
    $listener = $l; $Port = $p; break
  } catch { Write-Verbose "cannot listen on ${p}: $_" }
}
if (-not $listener) { throw 'No free port found for Espanso Snippets Manager.' }
$Url = "http://localhost:$Port/"
Write-Output "Espanso Snippets Manager running at $Url"
Write-Output "Match folder: $MatchDir"
Open-UI $Url

# ----------------------------------------------------------------- helpers
function Send-Text($ctx, [int]$code, [string]$type, [string]$body) {
  $bytes = $Utf8.GetBytes($body)
  $ctx.Response.StatusCode = $code
  $ctx.Response.ContentType = "$type; charset=utf-8"
  $ctx.Response.Headers.Add('Cache-Control', 'no-store')
  $ctx.Response.Headers.Add('X-Content-Type-Options', 'nosniff')
  $ctx.Response.ContentLength64 = $bytes.Length
  $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $ctx.Response.OutputStream.Close()
}
function Send-Json($ctx, [int]$code, $obj) { Send-Text $ctx $code 'application/json' (ConvertTo-Json $obj -Depth 6 -Compress) }

function Get-MtimeMs([string]$path) {
  [int64](((Get-Item -LiteralPath $path).LastWriteTimeUtc - [datetime]'1970-01-01').TotalMilliseconds)
}
function Read-Utf8([string]$path) { [IO.File]::ReadAllText($path, $Utf8) }

function Resolve-MatchFile([string]$name) {
  if (-not $name) { throw 'Missing file name' }
  $parts = $name.Replace('\', '/').Split('/')
  if ($name -notmatch '\.ya?ml$') { throw 'Invalid file name' }
  foreach ($seg in $parts) {
    if ($seg -eq '' -or $seg -eq '.' -or $seg -eq '..' -or $seg -notmatch '^[\w\- .]+$') { throw 'Invalid file name' }
  }
  if ($parts[0] -eq 'packages') { throw 'Invalid file name' }
  $full = [IO.Path]::GetFullPath((Join-Path $MatchDir ($parts -join '\')))
  $base = [IO.Path]::GetFullPath($MatchDir).TrimEnd('\') + '\'
  if (-not $full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid file name' }
  $full
}

# Emits one hashtable per file. Callers collect with @(...): returning a wrapped
# array (",$x") makes Windows PowerShell 5.1 serialize it as {"value":[],"Count":n}.
function Get-MatchFiles {
  if (-not (Test-Path -LiteralPath $MatchDir)) { return }
  $base = [IO.Path]::GetFullPath($MatchDir).TrimEnd('\') + '\'
  Get-ChildItem -LiteralPath $MatchDir -File -Recurse | Where-Object { $_.Extension -match '^\.ya?ml$' } | ForEach-Object {
    $rel = $_.FullName.Substring($base.Length).Replace('\', '/')
    if ($rel -notmatch '^packages/') {
      @{ name = $rel; mtime = (Get-MtimeMs $_.FullName); text = (Read-Utf8 $_.FullName) }
    }
  }
}

function Save-Backup([string]$path, [string]$name) {
  if (-not (Test-Path -LiteralPath $path)) { return }
  if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
  $flat  = $name.Replace('/', '__')
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
  Copy-Item -LiteralPath $path (Join-Path $BackupDir "$flat.$stamp.bak") -Force
  Get-ChildItem -LiteralPath $BackupDir -Filter "$flat.*.bak" | Sort-Object LastWriteTime -Descending |
    Select-Object -Skip $KeepBackups | Remove-Item -Force -ErrorAction SilentlyContinue
}

function Read-Body($ctx) {
  $sr = New-Object System.IO.StreamReader($ctx.Request.InputStream, $Utf8)
  try { $sr.ReadToEnd() } finally { $sr.Close() }
}

# ----------------------------------------------------------------- routes
function Invoke-Route($ctx) {
  $req  = $ctx.Request
  $path = $req.Url.AbsolutePath
  $verb = $req.HttpMethod

  # Only answer requests addressed to this app on localhost (blocks DNS rebinding).
  if ($req.Headers['Host'] -ne "localhost:$Port") { Send-Text $ctx 403 'text/plain' 'Forbidden'; return }
  # Anything that changes state must carry our custom header (blocks cross-site requests).
  if ($verb -ne 'GET' -and $path -ne '/api/quit' -and $req.Headers['X-Editor'] -ne '1') {
    Send-Text $ctx 403 'text/plain' 'Forbidden'; return
  }

  if ($verb -eq 'GET' -and $path -eq '/') {
    Send-Text $ctx 200 'text/html' (Read-Utf8 (Join-Path $Root 'index.html')); return
  }
  if ($verb -eq 'GET' -and $path -eq '/api/ping') { Send-Json $ctx 200 @{ app = $AppId }; return }
  if ($verb -eq 'GET' -and $path -eq '/api/status') {
    $running = [bool](Get-Process -Name 'espansod', 'espanso' -ErrorAction SilentlyContinue)
    Send-Json $ctx 200 @{ running = $running; matchDir = $MatchDir; backupDir = $BackupDir }; return
  }
  if ($verb -eq 'GET' -and $path -eq '/api/files') {
    $files = @(Get-MatchFiles)
    Send-Json $ctx 200 @{ files = $files }; return
  }
  if ($path -eq '/api/file') {
    $name = $req.QueryString['name']
    try { $file = Resolve-MatchFile $name } catch { Send-Json $ctx 400 @{ error = $_.Exception.Message }; return }
    $exists = Test-Path -LiteralPath $file
    if ($verb -eq 'GET') {
      if (-not $exists) { Send-Json $ctx 404 @{ error = 'Not found' }; return }
      Send-Json $ctx 200 @{ name = $name; mtime = (Get-MtimeMs $file); text = (Read-Utf8 $file) }; return
    }
    if ($verb -eq 'PUT') {
      $create   = $req.Headers['X-Create'] -eq '1'
      $expected = $req.Headers['X-Expected-Mtime']
      if ($create -and $exists) { Send-Json $ctx 409 @{ error = 'exists' }; return }
      if (-not $create -and -not $exists) { Send-Json $ctx 404 @{ error = 'Not found' }; return }
      if ($exists -and $expected -and $req.Headers['X-Force'] -ne '1' -and ([string](Get-MtimeMs $file)) -ne $expected) {
        Send-Json $ctx 409 @{ error = 'changed'; mtime = (Get-MtimeMs $file); text = (Read-Utf8 $file) }; return
      }
      $text = Read-Body $ctx
      $dir = Split-Path -Parent $file
      if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
      Save-Backup $file $name
      $tmp = "$file.tmp"
      [IO.File]::WriteAllText($tmp, $text, $Utf8)
      Move-Item -LiteralPath $tmp -Destination $file -Force
      Send-Json $ctx 200 @{ ok = $true; mtime = (Get-MtimeMs $file) }; return
    }
  }
  if ($verb -eq 'POST' -and $path -eq '/api/quit') {
    $script:quitAt = (Get-Date).AddSeconds(4); Send-Json $ctx 200 @{ ok = $true }; return
  }
  if ($verb -eq 'POST' -and $path -eq '/api/openfolder') {
    if (-not (Test-Path -LiteralPath $MatchDir)) { New-Item -ItemType Directory -Path $MatchDir -Force | Out-Null }
    Start-Process explorer.exe "`"$MatchDir`""; Send-Json $ctx 200 @{ ok = $true }; return
  }
  Send-Text $ctx 404 'text/plain' 'Not found'
}

# ----------------------------------------------------------------- main loop
$script:quitAt = $null
$lastHit = Get-Date
try {
  while ($listener.IsListening) {
    $ar = $listener.BeginGetContext($null, $null)
    while (-not $ar.AsyncWaitHandle.WaitOne(1000)) {
      if ($script:quitAt -and (Get-Date) -gt $script:quitAt) { return }
      if (((Get-Date) - $lastHit).TotalHours -gt 8) { return }
    }
    $ctx = $listener.EndGetContext($ar)
    $lastHit = Get-Date
    if ($ctx.Request.Url.AbsolutePath -ne '/api/quit') { $script:quitAt = $null }
    try { Invoke-Route $ctx }
    catch { try { Send-Json $ctx 500 @{ error = $_.Exception.Message } } catch { Write-Verbose "reply failed: $_" } }
  }
} finally {
  $listener.Stop()
  $listener.Close()
}
