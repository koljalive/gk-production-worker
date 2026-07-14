param([string]$InstallDir = 'C:\GKProductionWorker')
$ErrorActionPreference = 'Stop'
$exe = Join-Path $InstallDir 'GkProductionWorker.exe'
$config = Join-Path $InstallDir 'config.json'
if (-not (Test-Path $exe)) { throw "Worker fehlt: $exe" }
if (-not (Test-Path $config)) { throw "Konfiguration fehlt: $config" }
$action = New-ScheduledTaskAction -Execute $exe -Argument "watch --confirm JA --config `"$config`"" -WorkingDirectory $InstallDir
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 3650)
Register-ScheduledTask -TaskName 'GKProductionWorker' -Description 'Automatische Prüfung und Korrektur für glasfaser-kompass.de' -Action $action -Trigger $trigger -Settings $settings -User 'SYSTEM' -RunLevel Highest -Force
Start-ScheduledTask -TaskName 'GKProductionWorker'
Write-Host 'Windows-Startaufgabe GKProductionWorker wurde installiert und gestartet.'
