# AOU Hub Server - public bootstrap installer
# Downloads the latest signed/checksummed Setup, verifies SHA-256, installs
# silently, waits for the service, checks /health, and opens the dashboard.
# ASCII-only by design (PS 5.1 safe).

[CmdletBinding()]
param(
  [string]$ManifestUrl = "https://raw.githubusercontent.com/ssssoliman937-design/aouapp/main/server/latest.json",
  [switch]$Silent,
  [string]$Enroll = ""
)

$ErrorActionPreference = "Stop"
function Info($m){ Write-Host "[AOU] $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "[ OK ] $m" -ForegroundColor Green }
function Fail($m){ Write-Host "[FAIL] $m" -ForegroundColor Red }

# 1. detect Windows + architecture
$os = [System.Environment]::OSVersion.Version
if ($os.Major -lt 10) { Fail "Windows 10 or later required (found $os)."; exit 1 }
$arch = $env:PROCESSOR_ARCHITECTURE
if ($arch -ne "AMD64" -and $arch -ne "ARM64") { Fail "Unsupported architecture: $arch (need x64/ARM64)."; exit 1 }
Info "Windows $($os.Major).$($os.Minor) build $($os.Build), arch $arch"

# 2. elevate if not admin
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Info "Elevating to Administrator..."
  $psi = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`" -ManifestUrl `"$ManifestUrl`""
  if ($Silent) { $psi += " -Silent" }
  if ($Enroll) { $psi += " -Enroll `"$Enroll`"" }
  Start-Process powershell.exe -Verb RunAs -ArgumentList $psi
  exit 0
}

# 3. fetch metadata
Info "Fetching release metadata: $ManifestUrl"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$meta = Invoke-RestMethod -Uri $ManifestUrl -UseBasicParsing
if (-not $meta.setup_url -or -not $meta.sha256) { Fail "Manifest missing setup_url/sha256."; exit 1 }
Info "Latest: v$($meta.version) build $($meta.build)"

# 3b. minimum Windows gate from manifest (optional)
if ($meta.minimum_windows -and $os.Build -lt [int]$meta.minimum_windows) {
  Fail "This release needs Windows build $($meta.minimum_windows)+ (found $($os.Build))."; exit 1
}

# 4. download Setup
$tmp = Join-Path $env:TEMP ("AOUHubServer-Setup-" + $meta.version + ".exe")
Info "Downloading Setup..."
Invoke-WebRequest -Uri $meta.setup_url -OutFile $tmp -UseBasicParsing

# 5-7. verify SHA-256 - STOP on mismatch
$actual = (Get-FileHash -Algorithm SHA256 -Path $tmp).Hash.ToLower()
$expected = ([string]$meta.sha256).ToLower()
if ($actual -ne $expected) {
  Fail "SHA-256 MISMATCH - refusing to run installer."
  Fail "expected: $expected"
  Fail "actual:   $actual"
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  exit 2
}
Ok "SHA-256 verified: $actual"

# 8. run Setup (silent if requested)
$args = @()
if ($Silent) { $args += "/VERYSILENT"; $args += "/NORESTART" }
if ($Enroll) { $args += "/ENROLL=$Enroll" }
Info "Running installer..."
$p = Start-Process -FilePath $tmp -ArgumentList $args -Wait -PassThru
if ($p.ExitCode -ne 0) { Fail "Installer exit code $($p.ExitCode)."; exit $p.ExitCode }
Ok "Installer finished."

# 9. wait for the service
Info "Waiting for the AOUHubServer service..."
$svcOk = $false
for ($i=0; $i -lt 30; $i++) {
  $svc = Get-Service -Name "AOUHubServer" -ErrorAction SilentlyContinue
  if ($svc -and $svc.Status -eq "Running") { $svcOk = $true; break }
  Start-Sleep -Seconds 2
}
if ($svcOk) { Ok "Service is running." } else { Fail "Service did not reach Running (check Doctor)." }

# 10. health endpoint
try {
  $h = Invoke-RestMethod -Uri "http://127.0.0.1:8787/health" -TimeoutSec 10 -UseBasicParsing
  Ok "Health: $($h.status) (role $($h.role), v$($h.version), db $($h.db))"
} catch { Fail "Health endpoint not reachable yet: $($_.Exception.Message)" }

# 11. open dashboard
if (-not $Silent) { Start-Process "http://127.0.0.1:8787/" }

# 12. result
Remove-Item $tmp -Force -ErrorAction SilentlyContinue
if ($svcOk) { Ok "AOU Hub Server installed. Dashboard: http://127.0.0.1:8787/"; exit 0 }
else { Fail "Installed, but the service is not running. Run: AOUHubServer.exe doctor"; exit 3 }
