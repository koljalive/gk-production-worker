$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
dotnet restore .\GkProductionWorker.sln
if ($LASTEXITCODE -ne 0) { throw "dotnet restore fehlgeschlagen (Exitcode $LASTEXITCODE)." }
dotnet run --project .\tests\GkProductionWorker.Tests\GkProductionWorker.Tests.csproj -c Release
if ($LASTEXITCODE -ne 0) { throw "Tests fehlgeschlagen (Exitcode $LASTEXITCODE). Es wird kein Paket erstellt." }
dotnet publish .\src\GkProductionWorker\GkProductionWorker.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o .\artifacts\win-x64
if ($LASTEXITCODE -ne 0) { throw "dotnet publish fehlgeschlagen (Exitcode $LASTEXITCODE)." }
Copy-Item .\config.example.json .\artifacts\win-x64\config.example.json
Copy-Item .\README.md .\artifacts\win-x64\README.md
Compress-Archive -Path .\artifacts\win-x64\* -DestinationPath .\artifacts\gk-production-worker-6.0.0-win-x64.zip -Force
Write-Host "Fertig: artifacts\gk-production-worker-6.0.0-win-x64.zip"
