param(
    [string]$RegistrationToken
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoUrl = 'https://github.com/koljalive/gk-production-worker'
$installDir = 'C:\GKBridgeRunner'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Bitte PowerShell als Administrator starten und dieses Skript erneut ausführen.'
}

if ([string]::IsNullOrWhiteSpace($RegistrationToken)) {
    $RegistrationToken = Read-Host 'GitHub Runner Registration Token'
}
if ([string]::IsNullOrWhiteSpace($RegistrationToken)) { throw 'Kein Registration Token angegeben.' }

New-Item -ItemType Directory -Force -Path $installDir | Out-Null
Set-Location $installDir

$release = Invoke-RestMethod -Uri 'https://api.github.com/repos/actions/runner/releases/latest' -Headers @{ 'User-Agent'='GKBridgeInstaller' } -TimeoutSec 60
$asset = $release.assets | Where-Object { $_.name -match '^actions-runner-win-x64-.*\.zip$' } | Select-Object -First 1
if (-not $asset) { throw 'Aktuelles Windows-x64 Runner-Paket wurde nicht gefunden.' }

$zip = Join-Path $installDir $asset.name
Write-Host "Downloading $($asset.name)..."
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing -TimeoutSec 300

Write-Host 'Extracting runner...'
Expand-Archive -Path $zip -DestinationPath $installDir -Force
Remove-Item $zip -Force

if (Test-Path (Join-Path $installDir '.runner')) {
    Write-Host 'Runner ist bereits konfiguriert. Vorhandene Konfiguration wird verwendet.'
} else {
    & (Join-Path $installDir 'config.cmd') --url $repoUrl --token $RegistrationToken --name "GK-BRIDGE-$env:COMPUTERNAME" --labels 'gk-bridge' --work '_work' --unattended --replace
    if ($LASTEXITCODE -ne 0) { throw "Runner-Konfiguration fehlgeschlagen: ExitCode $LASTEXITCODE" }
}

Write-Host 'Installing/starting Windows service...'
& (Join-Path $installDir 'svc.cmd') install
# install may report already installed; start regardless.
& (Join-Path $installDir 'svc.cmd') start

Write-Host ''
Write-Host 'GK Bridge Runner eingerichtet.' -ForegroundColor Green
Write-Host 'Repository: koljalive/gk-production-worker'
Write-Host 'Label: gk-bridge'
Write-Host 'Service directory: C:\GKBridgeRunner'
