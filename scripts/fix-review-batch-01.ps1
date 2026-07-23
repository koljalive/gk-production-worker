param(
    [string]$EnvFile = '.\.env',
    [ValidateSet('Preview','Apply')][string]$Mode = 'Preview',
    [string]$Confirm = ''
)
$ErrorActionPreference = 'Stop'
$ids = @(14006,16011,15004,15010,302,299,298,3020,288)
if ($Mode -eq 'Apply' -and $Confirm -cne 'BATCH 01 BEREINIGEN') { throw 'Bestätigung fehlt.' }
$v = @{}
Get-Content $EnvFile | Where-Object { $_ -match '^[^#].*=' } | ForEach-Object { $p=$_ -split '=',2; $v[$p[0].Trim()]=$p[1].Trim() }
foreach ($n in @('GK_SITE_URL','GK_UNIFIED_API_TOKEN')) { if ([string]::IsNullOrWhiteSpace($v[$n])) { throw "$n fehlt." } }
$site = $v['GK_SITE_URL'].TrimEnd('/')
$headers = @{ Authorization = 'Bearer ' + $v['GK_UNIFIED_API_TOKEN'] }
$root = if (Test-Path (Join-Path $PSScriptRoot '..\GkProductionWorker.sln')) { Split-Path -Parent $PSScriptRoot } else { $PSScriptRoot }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $root ('backups\batch-01-' + $stamp)
$reportDir = Join-Path $root 'reports'
New-Item $reportDir -ItemType Directory -Force | Out-Null
if ($Mode -eq 'Apply') { New-Item $backup -ItemType Directory -Force | Out-Null }
$rows = @()
foreach ($id in $ids) {
    $readBody = [Text.Encoding]::UTF8.GetBytes((@{id=$id} | ConvertTo-Json -Compress))
    $post = Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/read-post') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $readBody
    $old = [string]$post.content
    $new = $old
    $deep = [regex]::Matches($new,'(?is)<!--\s*GKKB53_DEEP_UPGRADE_START\s*-->.*?<!--\s*GKKB53_DEEP_UPGRADE_END\s*-->').Count
    $authority = [regex]::Matches($new,'(?is)<!--\s*GKKB53_AUTHORITY_UPGRADE_START\s*-->.*?<!--\s*GKKB53_AUTHORITY_UPGRADE_END\s*-->').Count
    $tail = [regex]::Matches($new,'(?is)<!--\s*gk_social_ready\s*-->.*\z').Count
    $image = [regex]::Matches($new,'(?is)<figure\b[^>]*>\s*<img\b[^>]*cropped-ChatGPT-Image-11\.-Juni-2026-02_25_44\.png[^>]*>.*?</figure>').Count
    $new = [regex]::Replace($new,'(?is)<!--\s*GKKB53_DEEP_UPGRADE_START\s*-->.*?<!--\s*GKKB53_DEEP_UPGRADE_END\s*-->','')
    $new = [regex]::Replace($new,'(?is)<!--\s*GKKB53_AUTHORITY_UPGRADE_START\s*-->.*?<!--\s*GKKB53_AUTHORITY_UPGRADE_END\s*-->','')
    $new = [regex]::Replace($new,'(?is)<!--\s*gk_social_ready\s*-->.*\z','')
    $new = [regex]::Replace($new,'(?is)<figure\b[^>]*>\s*<img\b[^>]*cropped-ChatGPT-Image-11\.-Juni-2026-02_25_44\.png[^>]*>.*?</figure>','')
    if ($new -ceq $old) { continue }
    if ([regex]::IsMatch($new,'GKKB53_(?:DEEP|AUTHORITY)_UPGRADE_START|cropped-ChatGPT-Image-11\.-Juni-2026-02_25_44\.png|gk_social_ready')) { throw "Nachprüfung vor Speicherung fehlgeschlagen: $id" }
    $status = 'READY'
    if ($Mode -eq 'Apply') {
        [IO.File]::WriteAllText((Join-Path $backup "post-$id.html"),$old,[Text.UTF8Encoding]::new($false))
        $payload = [Text.Encoding]::UTF8.GetBytes((@{id=$id;content=$new} | ConvertTo-Json -Compress))
        $updated = Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/update-post') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $payload
        if ($updated.updated -ne $true) { throw "Update nicht bestätigt: $id" }
        $verify = Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/read-post') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $readBody
        if ([string]$verify.content -cne $new) { throw "Speicherprüfung fehlgeschlagen: $id" }
        $status = 'UPDATED_AND_VERIFIED'
    }
    $rows += [pscustomobject]@{id=$id;title=[string]$post.title;deep_blocks=$deep;authority_blocks=$authority;generic_tails=$tail;wrong_images=$image;status=$status}
    Write-Host ("${id}: $status | Blöcke="+($deep+$authority+$tail)+' | Bilder='+$image)
}
if ($Mode -eq 'Apply' -and $rows.Count) {
    $cache = Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/clear-cache') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('{}'))
    if ($cache.cache_cleared -ne $true) { throw 'Cache nicht geleert' }
}
$rows | Export-Csv (Join-Path $reportDir ('batch-01-'+$Mode.ToLower()+'-'+$stamp+'.csv')) -NoTypeInformation -Encoding UTF8
Write-Host ('FERTIG: Modus='+$Mode+' | Beiträge='+$rows.Count)
