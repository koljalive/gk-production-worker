param(
    [string]$EnvFile = '.\.env',
    [ValidateSet('Preview','Apply')][string]$Mode = 'Preview',
    [string]$Confirm = ''
)

$ErrorActionPreference = 'Stop'
if ($Mode -eq 'Apply' -and $Confirm -cne 'DSL ALTINHALTE NORMALISIEREN') {
    throw 'Bestätigung fehlt.'
}

$values = @{}
Get-Content $EnvFile |
    Where-Object { $_ -match '^[^#].*=' } |
    ForEach-Object {
        $parts = $_ -split '=', 2
        $values[$parts[0].Trim()] = $parts[1].Trim()
    }

foreach ($name in @('GK_SITE_URL','GK_UNIFIED_API_TOKEN')) {
    if ([string]::IsNullOrWhiteSpace($values[$name])) { throw "$name fehlt." }
}

$site = $values['GK_SITE_URL'].TrimEnd('/')
$headers = @{ Authorization = 'Bearer ' + $values['GK_UNIFIED_API_TOKEN'] }
$root = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $root ('backups\dsl-legacy-normalize-' + $stamp)
$reportDir = Join-Path $root 'reports'
New-Item $reportDir -ItemType Directory -Force | Out-Null
if ($Mode -eq 'Apply') { New-Item $backup -ItemType Directory -Force | Out-Null }

$pairs = @(
    @{ Canonical=3012; Legacy=5003; CanonicalHash='43855c197359d5fcaca5ce01b21a2edaea6a1813773cf58337a15ed497553f0f'; LegacyHash='d2bc811173cfb81de8cee441adf6e4dd8ee4b9965dfec75ad0f3501cb4e413bf'; Topic='TAL' },
    @{ Canonical=3013; Legacy=5004; CanonicalHash='e080d77b279466f9a8a28f969b91f1c21d032320f10028d6701c2d689748b7c5'; LegacyHash='02818da33fb46c974e2b21504e9e98c62cc86afe2c9e2417cf273071e8cf2210'; Topic='KVz' },
    @{ Canonical=3014; Legacy=5005; CanonicalHash='e747e42f187f5b7691eca6c02985a60a0ba28e3797820086a303950741f63620'; LegacyHash='ad185a68b3bbf23fe87f316cc635b3c0db317f9a22cff03ba2bf434cd9867d0b'; Topic='HVt' },
    @{ Canonical=3016; Legacy=5007; CanonicalHash='b1e7016e2b886d7e644522629e28af6615239b43fc2eb04fe856851518674329'; LegacyHash='edfd105385d5c470eea602c5d8efc8d8e59b3cbed29fb6fdfc160b0d01a662e8'; Topic='Vectoring' },
    @{ Canonical=3017; Legacy=5008; CanonicalHash='69b2e752dc5617e1e8a92f6a9f2ee2b96a93bf4926d779c81131fe1ca1f2d852'; LegacyHash='73e1cd5ef710ed45bac267b1d89b8d5ed95cacc6be3320152623970605f85641'; Topic='Supervectoring' }
)

function Read-Post([long]$Id) {
    $body = [Text.Encoding]::UTF8.GetBytes((@{ id=$Id } | ConvertTo-Json -Compress))
    Invoke-RestMethod ($site + '/wp-json/gk-unified-api/v1/read-post') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 60
}

function Get-Hash([string]$Content) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Content)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

$rows = @()
foreach ($pair in $pairs) {
    $canonical = Read-Post $pair.Canonical
    $legacy = Read-Post $pair.Legacy
    $canonicalContent = [string]$canonical.content
    $legacyContent = [string]$legacy.content
    $canonicalHash = Get-Hash $canonicalContent
    $legacyHash = Get-Hash $legacyContent

    if ($canonicalHash -cne $pair.CanonicalHash -or $legacyHash -cne $pair.LegacyHash) {
        $rows += [pscustomobject]@{
            topic=$pair.Topic; canonical=$pair.Canonical; legacy=$pair.Legacy
            status='SKIPPED_PRECONDITION'; canonical_hash=$canonicalHash; legacy_hash=$legacyHash
        }
        continue
    }

    $status = 'READY'
    if ($Mode -eq 'Apply') {
        [IO.File]::WriteAllText((Join-Path $backup "canonical-$($pair.Canonical).html"), $canonicalContent, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $backup "legacy-$($pair.Legacy).html"), $legacyContent, [Text.UTF8Encoding]::new($false))
        $payload = [Text.Encoding]::UTF8.GetBytes((@{ id=$pair.Legacy; content=$canonicalContent } | ConvertTo-Json -Compress))
        $updated = Invoke-RestMethod ($site + '/wp-json/gk-unified-api/v1/update-post') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $payload -TimeoutSec 60
        if ($updated.updated -ne $true) { throw "Update nicht bestätigt: $($pair.Legacy)" }
        $verify = Read-Post $pair.Legacy
        if ((Get-Hash ([string]$verify.content)) -cne $canonicalHash) { throw "Speicherprüfung fehlgeschlagen: $($pair.Legacy)" }
        $status = 'UPDATED_AND_VERIFIED'
    }

    $rows += [pscustomobject]@{
        topic=$pair.Topic; canonical=$pair.Canonical; legacy=$pair.Legacy
        status=$status; canonical_hash=$canonicalHash; legacy_hash=$legacyHash
    }
}

if ($Mode -eq 'Apply' -and @($rows | Where-Object status -eq 'UPDATED_AND_VERIFIED').Count) {
    $cache = Invoke-RestMethod ($site + '/wp-json/gk-unified-api/v1/clear-cache') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('{}')) -TimeoutSec 60
    if ($cache.cache_cleared -ne $true) { throw 'Cache nicht geleert.' }
}

$report = Join-Path $reportDir ('dsl-legacy-normalize-' + $Mode.ToLowerInvariant() + '-' + $stamp + '.csv')
$rows | Export-Csv $report -NoTypeInformation -Encoding UTF8
Write-Host ("FERTIG: Modus=$Mode | Aktualisiert=" + @($rows | Where-Object status -eq 'UPDATED_AND_VERIFIED').Count + " | Übersprungen=" + @($rows | Where-Object status -eq 'SKIPPED_PRECONDITION').Count)
