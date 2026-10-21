# Tests for src/server.ps1 (the Windows helper). Plain PowerShell, no modules needed.
# Run on Windows with either shell:
#   powershell -ExecutionPolicy Bypass -File tests\server.Tests.ps1
#   pwsh -File tests\server.Tests.ps1
$ErrorActionPreference = 'Stop'
$root     = Split-Path -Parent $PSScriptRoot
$server   = Join-Path $root 'src\server.ps1'
$fixtures = Join-Path $root 'tests\fixtures\espanso'
$tmp      = Join-Path ([IO.Path]::GetTempPath()) ("esm-ps-" + [guid]::NewGuid().ToString('N'))
$config   = Join-Path $tmp 'espanso'
$backups  = Join-Path $tmp 'backups'
$port     = Get-Random -Minimum 48000 -Maximum 49000
$base     = "http://localhost:$port"
$script:failures = 0

function Assert([bool]$cond, [string]$msg) {
  if ($cond) { Write-Host "  ok   $msg" }
  else {
    Write-Host "  FAIL $msg" -ForegroundColor Red
    if ($env:GITHUB_ACTIONS) { Write-Host "::error file=tests/server.Tests.ps1::$($PSVersionTable.PSEdition) - $msg" }
    $script:failures++
  }
}
function Call([string]$method, [string]$path, [string]$body, [hashtable]$headers) {
  $h = @{}
  if ($method -ne 'GET') { $h['X-Editor'] = '1' }
  if ($headers) { foreach ($k in $headers.Keys) { $h[$k] = $headers[$k] } }
  $req = @{ Uri = "$base$path"; Method = $method; Headers = $h; UseBasicParsing = $true }
  if ($method -ne 'GET' -and $body) { $req['Body'] = [Text.Encoding]::UTF8.GetBytes($body); $req['ContentType'] = 'text/plain; charset=utf-8' }
  try {
    $r = Invoke-WebRequest @req
    $text = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
    return @{ Status = [int]$r.StatusCode; Body = $text }
  } catch {
    $resp = $_.Exception.Response
    if (-not $resp) { throw }
    return @{ Status = [int]$resp.StatusCode; Body = '' }
  }
}

New-Item -ItemType Directory -Path $tmp | Out-Null
Copy-Item -Path $fixtures -Destination $config -Recurse

$psExe = (Get-Process -Id $PID).Path
$proc = Start-Process -FilePath $psExe -PassThru -WindowStyle Hidden -ArgumentList @(
  '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$server`"",
  '-NoBrowser', '-Port', $port, '-ConfigDir', "`"$config`"", '-BackupDir', "`"$backups`"")

try {
  $up = $false
  for ($i = 0; $i -lt 100 -and -not $up; $i++) {
    try { Invoke-WebRequest "$base/api/ping" -UseBasicParsing -TimeoutSec 1 | Out-Null; $up = $true } catch { Start-Sleep -Milliseconds 200 }
  }
  Assert $up 'server starts'
  if (-not $up) {
    if ($proc.HasExited) { Write-Host "server exited with code $($proc.ExitCode)" }
    throw 'server did not start'
  }

  Write-Host 'Reading'
  $r = Call GET '/api/ping'
  Assert ($r.Body -match 'espanso-snippets-manager') 'ping identifies the app'
  $r = Call GET '/api/files'
  $files = ($r.Body | ConvertFrom-Json).files
  $names = @($files | ForEach-Object { $_.name })
  $expected = @('_private.yml', 'base.yml', 'work.yml', 'work/email.yml')
  $missing = @($expected | Where-Object { $names -notcontains $_ })
  Assert ($names.Count -eq 4 -and $missing.Count -eq 0) "lists match files, hides packages ($($names -join ','))"
  $work = $files | Where-Object { $_.name -eq 'work.yml' }
  Assert ($work.text.Contains([string][char]0x30C4)) 'reads UTF-8 text'
  $r = Call GET '/'
  Assert ($r.Status -eq 200 -and $r.Body -match '<html') 'serves the page'

  Write-Host 'Writing'
  $new = "matches:`n  - trigger: ':x'`n    replace: " + [char]0x2713 + " ok`n"
  $r = Call PUT '/api/file?name=work.yml' $new @{ 'X-Expected-Mtime' = [string]$work.mtime }
  Assert ($r.Status -eq 200) 'saves a file'
  $onDisk = [IO.File]::ReadAllText((Join-Path $config 'match\work.yml'), (New-Object Text.UTF8Encoding($false)))
  Assert ($onDisk -eq $new) 'file content matches (UTF-8, no BOM)'
  $bytes = [IO.File]::ReadAllBytes((Join-Path $config 'match\work.yml'))
  Assert (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB)) 'no byte-order mark'
  Assert (@(Get-ChildItem $backups -Filter 'work.yml.*.bak').Count -eq 1) 'keeps a backup'

  $r = Call PUT '/api/file?name=work.yml' 'matches: []' @{ 'X-Expected-Mtime' = '1' }
  Assert ($r.Status -eq 409) 'detects changes made elsewhere'
  $r = Call PUT '/api/file?name=work.yml' 'matches: []' @{ 'X-Expected-Mtime' = '1'; 'X-Force' = '1' }
  Assert ($r.Status -eq 200) 'force overwrite works'

  $r = Call PUT '/api/file?name=personal%2Fhome.yml' 'matches: []' @{ 'X-Create' = '1' }
  Assert ($r.Status -eq 200 -and (Test-Path (Join-Path $config 'match\personal\home.yml'))) 'creates a file in a subfolder'
  $r = Call PUT '/api/file?name=personal%2Fhome.yml' 'matches: []' @{ 'X-Create' = '1' }
  Assert ($r.Status -eq 409) 'refuses to create over an existing file'
  $r = Call PUT '/api/file?name=missing.yml' 'matches: []' $null
  Assert ($r.Status -eq 404) 'refuses to write a missing file without X-Create'

  Write-Host 'Security'
  foreach ($bad in @('..%2Fescape.yml', 'notyaml.txt', 'packages%2Fdemo%2Fpackage.yml', 'a%2F..%2F..%2Fb.yml', 'C%3A%2Fx.yml')) {
    $r = Call PUT "/api/file?name=$bad" 'matches: []' @{ 'X-Create' = '1' }
    Assert ($r.Status -eq 400) "rejects name $bad"
  }
  Assert (-not (Test-Path (Join-Path $config 'escape.yml'))) 'nothing escaped the match folder'
  try {
    Invoke-WebRequest "$base/api/file?name=work.yml" -Method PUT -Body 'x' -UseBasicParsing | Out-Null
    Assert $false 'write without X-Editor header is refused'
  } catch { Assert ([int]$_.Exception.Response.StatusCode -eq 403) 'write without X-Editor header is refused' }

  Write-Host 'Lifecycle'
  $r = Call POST '/api/quit' '' $null
  Assert ($r.Status -eq 200) 'quit accepted'
  $stopped = $proc.WaitForExit(15000)
  Assert $stopped 'server stops after quit'
} catch {
  $script:failures++
  $where = "line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
  Write-Host "  ERROR $($_.Exception.Message) at $where" -ForegroundColor Red
  if ($env:GITHUB_ACTIONS) { Write-Host "::error file=tests/server.Tests.ps1,line=$($_.InvocationInfo.ScriptLineNumber)::$($PSVersionTable.PSEdition) - $($_.Exception.Message)" }
} finally {
  if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:failures) { Write-Host "$($script:failures) test(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All PowerShell server tests passed' -ForegroundColor Green
