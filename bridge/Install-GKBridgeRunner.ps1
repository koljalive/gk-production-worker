param(
    [string]$RegistrationToken
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoUrl = 'https://github.com/koljalive/gk-production-worker'
$installDir = 'C:\GKBridgeRunner'
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Bitte PowerShell als Administrator starten und dieses Skript erneut ausführen.'
}

New-Item -ItemType Directory -Force -Path $installDir | Out-Null
Set-Location $installDir

if (-not (Test-Path (Join-Path $installDir '.runner'))) {
    if ([string]::IsNullOrWhiteSpace($RegistrationToken)) {
        $RegistrationToken = Read-Host 'GitHub Runner Registration Token'
    }
    if ([string]::IsNullOrWhiteSpace($RegistrationToken)) { throw 'Kein Registration Token angegeben.' }

    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/actions/runner/releases/latest' -Headers @{ 'User-Agent'='GKBridgeInstaller' } -TimeoutSec 60
    $asset = $release.assets | Where-Object { $_.name -match '^actions-runner-win-x64-.*\.zip$' } | Select-Object -First 1
    if (-not $asset) { throw 'Aktuelles Windows-x64 Runner-Paket wurde nicht gefunden.' }

    $zip = Join-Path $installDir $asset.name
    Write-Host "Downloading $($asset.name)..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing -TimeoutSec 300
    Write-Host 'Extracting runner...'
    Expand-Archive -Path $zip -DestinationPath $installDir -Force
    Remove-Item $zip -Force

    & (Join-Path $installDir 'config.cmd') --url $repoUrl --token $RegistrationToken --name "GK-BRIDGE-$env:COMPUTERNAME" --labels 'gk-bridge' --work '_work' --unattended --replace
    if ($LASTEXITCODE -ne 0) { throw "Runner-Konfiguration fehlgeschlagen: ExitCode $LASTEXITCODE" }
} else {
    Write-Host 'Runner ist bereits registriert. Vorhandene Konfiguration wird verwendet.'
}

$runCmd = Join-Path $installDir 'run.cmd'
if (-not (Test-Path $runCmd)) { throw "Runner-Startdatei fehlt: $runCmd" }

# Remove the scheduled-task variant. On some Windows setups the runner listener exits
# immediately when hosted by Task Scheduler despite a successful task result.
Unregister-ScheduledTask -TaskName 'GK Bridge Runner' -Confirm:$false -ErrorAction SilentlyContinue

# Persist at interactive user logon through the Startup folder instead.
$startupDir = [Environment]::GetFolderPath('Startup')
$launcher = Join-Path $startupDir 'GK-Bridge-Runner.cmd'
$launcherContent = "@echo off`r`ncd /d `"$installDir`"`r`ncall `"$runCmd`"`r`n"
[IO.File]::WriteAllText($launcher, $launcherContent, (New-Object Text.ASCIIEncoding))

# Stop stale listener/worker processes and launch one visible/minimized listener now.
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -like "$installDir*" -and $_.Name -match 'Runner\.(Listener|Worker)\.exe' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', ('"{0}"' -f $launcher)) -WindowStyle Minimized
Start-Sleep -Seconds 6

$listener = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -like "$installDir*" -and $_.Name -eq 'Runner.Listener.exe' } |
    Select-Object -First 1

Write-Host ''
Write-Host 'GK Bridge Runner eingerichtet.' -ForegroundColor Green
Write-Host "Repository: $repoUrl"
Write-Host 'Label: gk-bridge'
Write-Host "Runner directory: $installDir"
Write-Host "Startup launcher: $launcher"
Write-Host "Runner user: $currentUser"
if ($listener) {
    Write-Host "Listener state: RUNNING (PID $($listener.ProcessId))" -ForegroundColor Green
} else {
    Write-Host 'Listener state: NOT RUNNING' -ForegroundColor Red
    Write-Host 'Der Runner-Listener ist unmittelbar wieder beendet worden.'
}
