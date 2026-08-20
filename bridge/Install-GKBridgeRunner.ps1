param(
    [string]$RegistrationToken
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoUrl = 'https://github.com/koljalive/gk-production-worker'
$installDir = 'C:\GKBridgeRunner'
$taskName = 'GK Bridge Runner'
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

Write-Host 'Installing persistent Windows logon task for current user...'
$action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument ('/c "{0}"' -f $runCmd) -WorkingDirectory $installDir
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 20 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -like "$installDir*" -and $_.Name -match 'Runner\.(Listener|Worker)\.exe' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 5

$task = Get-ScheduledTask -TaskName $taskName
$info = Get-ScheduledTaskInfo -TaskName $taskName

Write-Host ''
Write-Host 'GK Bridge Runner eingerichtet.' -ForegroundColor Green
Write-Host "Repository: $repoUrl"
Write-Host 'Label: gk-bridge'
Write-Host "Runner directory: $installDir"
Write-Host "Scheduled task: $taskName"
Write-Host "Task user: $currentUser"
Write-Host "Task state: $($task.State)"
Write-Host "Last task result: $($info.LastTaskResult)"
