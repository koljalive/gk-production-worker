param(
    [ValidateSet('Preview','Apply')][string]$Mode = 'Preview',
    [string]$Confirm = '',
    [string]$EnvFile = '.\.env',
    [string]$StoreId = 'glasfaserkomp-21',
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

function Add-AmazonTracking([string]$Html, [string]$Tag) {
    return [regex]::Replace($Html, '(?is)<a\b(?<attrs>[^>]*)>', {
        param($match)
        $attrs = $match.Groups['attrs'].Value
        $hrefMatch = [regex]::Match($attrs, '(?is)\bhref\s*=\s*(?<q>["''])(?<url>.*?)\k<q>')
        if (-not $hrefMatch.Success) { return $match.Value }
        $decoded = [Net.WebUtility]::HtmlDecode($hrefMatch.Groups['url'].Value)
        $uri = $null
        if (-not [Uri]::TryCreate($decoded, [UriKind]::Absolute, [ref]$uri)) { return $match.Value }
        if ($uri.Scheme -ne 'https' -or ($uri.Host -ne 'amazon.de' -and $uri.Host -ne 'www.amazon.de')) { return $match.Value }

        $builder = New-Object UriBuilder($uri)
        $pairs = New-Object Collections.Generic.List[string]
        foreach ($part in $builder.Query.TrimStart('?').Split('&', [StringSplitOptions]::RemoveEmptyEntries)) {
            if (($part -split '=', 2)[0] -ne 'tag') { $pairs.Add($part) }
        }
        $pairs.Add('tag=' + [Uri]::EscapeDataString($Tag))
        $builder.Query = [string]::Join('&', $pairs)
        $newUrl = [Net.WebUtility]::HtmlEncode($builder.Uri.AbsoluteUri)
        $attrs = $attrs.Remove($hrefMatch.Groups['url'].Index, $hrefMatch.Groups['url'].Length).Insert($hrefMatch.Groups['url'].Index, $newUrl)

        $relMatch = [regex]::Match($attrs, '(?is)\brel\s*=\s*(?<q>["''])(?<value>.*?)\k<q>')
        $tokens = New-Object Collections.Generic.List[string]
        if ($relMatch.Success) {
            foreach ($token in ($relMatch.Groups['value'].Value -split '\s+')) {
                if ($token -and -not $tokens.Contains($token.ToLowerInvariant())) { $tokens.Add($token.ToLowerInvariant()) }
            }
        }
        foreach ($required in @('sponsored','nofollow')) { if (-not $tokens.Contains($required)) { $tokens.Add($required) } }
        $newRel = [string]::Join(' ', $tokens)
        if ($relMatch.Success) {
            $attrs = $attrs.Remove($relMatch.Groups['value'].Index, $relMatch.Groups['value'].Length).Insert($relMatch.Groups['value'].Index, $newRel)
        } else {
            $attrs += ' rel="' + $newRel + '"'
        }
        return '<a' + $attrs + '>'
    })
}

function Assert-Tracked([string]$Html, [string]$Tag) {
    $amazon = [regex]::Matches($Html, '(?is)<a\b[^>]*\bhref\s*=\s*["''](?<url>.*?)["''][^>]*>') | Where-Object {
        $u = $null; [Uri]::TryCreate([Net.WebUtility]::HtmlDecode($_.Groups['url'].Value), [UriKind]::Absolute, [ref]$u) -and $u.Host -in @('amazon.de','www.amazon.de')
    }
    foreach ($link in $amazon) {
        $tagPattern = '(?i)(?:^|[?&])tag=' + [regex]::Escape([Uri]::EscapeDataString($Tag)) + '(?:&|$)'
        if ([Net.WebUtility]::HtmlDecode($link.Groups['url'].Value) -notmatch $tagPattern) { throw 'Amazon-Link ohne korrekte Store-ID gefunden.' }
        $rel = [regex]::Match($link.Value, '(?is)\brel\s*=\s*["''](?<v>.*?)["'']').Groups['v'].Value
        if ($rel -notmatch '(?i)(?:^|\s)sponsored(?:\s|$)' -or $rel -notmatch '(?i)(?:^|\s)nofollow(?:\s|$)') { throw 'Amazon-Link ohne sponsored/nofollow gefunden.' }
    }
    return @($amazon).Count
}

if ($SelfTest) {
    $sample = '<p><a class="buy" href="https://www.amazon.de/s?k=router&amp;x=1" rel="noopener">Router</a></p><a href="https://example.org/">X</a>'
    $once = Add-AmazonTracking $sample $StoreId
    $twice = Add-AmazonTracking $once $StoreId
    if ($once -cne $twice) { throw 'Selbsttest fehlgeschlagen: Verarbeitung ist nicht idempotent.' }
    if ((Assert-Tracked $once $StoreId) -ne 1) { throw 'Selbsttest fehlgeschlagen: Amazon-Link nicht erkannt.' }
    if ($once -notmatch 'example\.org') { throw 'Selbsttest fehlgeschlagen: Fremdlink verändert.' }
    Write-Host 'PASS Amazon-Affiliate-Selbsttest'
    exit 0
}

if ($Mode -eq 'Apply' -and $Confirm -cne 'AMAZON AFFILIATE AKTUALISIEREN') { throw 'Apply erfordert -Confirm "AMAZON AFFILIATE AKTUALISIEREN".' }
if (-not (Test-Path -LiteralPath $EnvFile)) { throw "ENV-Datei fehlt: $EnvFile" }
$envValues = @{}
Get-Content -LiteralPath $EnvFile | Where-Object { $_ -match '^[^#].*=' } | ForEach-Object { $p = $_ -split '=',2; $envValues[$p[0].Trim()] = $p[1].Trim() }
foreach ($name in @('GK_SITE_URL','GK_SITE_AUDIT_TOKEN','GK_UNIFIED_API_TOKEN')) { if ([string]::IsNullOrWhiteSpace($envValues[$name])) { throw "$name fehlt." } }

$site = $envValues['GK_SITE_URL'].TrimEnd('/')
$auditHeaders = @{ Authorization = 'Bearer ' + $envValues['GK_SITE_AUDIT_TOKEN'] }
$unifiedHeaders = @{ Authorization = 'Bearer ' + $envValues['GK_UNIFIED_API_TOKEN'] }
$auditBase = $site + '/wp-json/gk-site-audit/v1/'
$unifiedBase = $site + '/wp-json/gk-unified-api/v1/'
$root = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $root ('backups\amazon-affiliate-' + $stamp)
$reportDir = Join-Path $root 'reports'
New-Item $reportDir -ItemType Directory -Force | Out-Null
if ($Mode -eq 'Apply') { New-Item $backupDir -ItemType Directory -Force | Out-Null }

$items = New-Object Collections.Generic.List[object]
$page = 1
do {
    $batch = @(Invoke-RestMethod ($auditBase + 'items?page=' + $page + '&per_page=100') -Headers $auditHeaders)
    if ($batch.Count -eq 1 -and $null -ne $batch[0].items) { $batch = @($batch[0].items) }
    foreach ($item in $batch) { if ($item.id) { $items.Add($item) } }
    $page++
} while ($batch.Count -eq 100)

$results = New-Object Collections.Generic.List[object]
foreach ($queueItem in ($items | Sort-Object {[long]$_.id} -Unique)) {
    $id = [long]$queueItem.id
    $body = [Text.Encoding]::UTF8.GetBytes((@{id=$id} | ConvertTo-Json -Compress))
    $post = Invoke-RestMethod ($unifiedBase + 'read-post') -Method Post -Headers $unifiedHeaders -ContentType 'application/json; charset=utf-8' -Body $body
    $old = [string]$post.content
    $new = Add-AmazonTracking $old $StoreId
    $count = Assert-Tracked $new $StoreId
    if ($count -eq 0 -or $new -ceq $old) { continue }
    $status = 'READY'
    if ($Mode -eq 'Apply') {
        [IO.File]::WriteAllText((Join-Path $backupDir ("post-$id.html")), $old, [Text.UTF8Encoding]::new($false))
        $payload = [Text.Encoding]::UTF8.GetBytes((@{id=$id;content=$new} | ConvertTo-Json -Compress))
        $updated = Invoke-RestMethod ($unifiedBase + 'update-post') -Method Post -Headers $unifiedHeaders -ContentType 'application/json; charset=utf-8' -Body $payload
        if ($updated.updated -ne $true) { throw "Aktualisierung für Beitrag $id nicht bestätigt." }
        $verify = Invoke-RestMethod ($unifiedBase + 'read-post') -Method Post -Headers $unifiedHeaders -ContentType 'application/json; charset=utf-8' -Body $body
        if ([string]$verify.content -cne $new) { throw "Speicherprüfung für Beitrag $id fehlgeschlagen." }
        Assert-Tracked ([string]$verify.content) $StoreId | Out-Null
        $status = 'UPDATED_AND_VERIFIED'
    }
    $results.Add([pscustomobject]@{ id=$id; title=[string]$post.title; amazon_links=$count; status=$status })
    Write-Host ("${id}: $status | Amazon-Links=$count | " + [string]$post.title)
}

if ($Mode -eq 'Apply' -and $results.Count -gt 0) {
    $cache = Invoke-RestMethod ($unifiedBase + 'clear-cache') -Method Post -Headers $unifiedHeaders -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('{}'))
    if ($cache.cache_cleared -ne $true) { throw 'Cache-Leerung nicht bestätigt.' }
}
$report = Join-Path $reportDir ('amazon-affiliate-' + $Mode.ToLowerInvariant() + '-' + $stamp + '.csv')
$results | Export-Csv $report -NoTypeInformation -Encoding UTF8
Write-Host ("FERTIG: Modus=$Mode | Beiträge=" + $results.Count + ' | Store-ID=' + $StoreId)
Write-Host ('Bericht: ' + $report)
if ($Mode -eq 'Apply') { Write-Host ('Backups: ' + $backupDir) }
