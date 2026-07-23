param(
    [string]$Repository = 'koljalive/gk-production-worker',
    [string]$Target = 'C:\gk-production-worker-github'
)
$ErrorActionPreference = 'Stop'
$source = Split-Path -Parent $PSScriptRoot
if (Test-Path $Target) { throw "Zielordner existiert bereits: $Target" }

gh auth status
if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI ist nicht angemeldet.' }
gh repo clone $Repository $Target
if ($LASTEXITCODE -ne 0) { throw 'Repository konnte nicht geklont werden.' }

Get-ChildItem -LiteralPath $source -Force | Where-Object {
    $_.Name -notin @('.git','bin','obj','artifacts')
} | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $Target -Recurse -Force
}

Set-Location $Target
git switch -c agent/verified-production-worker
git add --all
git commit -m 'Build verified GK Production Worker 6.0'
if ($LASTEXITCODE -ne 0) { throw 'Commit fehlgeschlagen.' }
git push --set-upstream origin agent/verified-production-worker
if ($LASTEXITCODE -ne 0) { throw 'Push fehlgeschlagen.' }

$body = @'
## Was geändert wurde

- vollständiger .NET-8-Production-Worker
- vertragstreue Site-Audit-API- und Unified-API-Clients
- OpenAI Web Search mit echten Quellenbelegen
- Quality Gates, No-Change-Schutz und Medienprüfung
- Backup, Precondition-Check, Nachprüfung und Cache-Leerung
- Windows-Build und GitHub-Actions-CI

## Verifikation

GitHub Actions kompiliert mit Warnungen als Fehler, führt Vertrags- und Sicherheitstests aus und erzeugt das Windows-x64-Artefakt.
'@
gh pr create --draft --base main --head agent/verified-production-worker --title 'Build verified GK Production Worker 6.0' --body $body
if ($LASTEXITCODE -ne 0) { throw 'Pull Request konnte nicht erstellt werden.' }
Write-Host 'Branch, Commit, Push und Draft-PR wurden erstellt. GitHub Actions läuft.'
