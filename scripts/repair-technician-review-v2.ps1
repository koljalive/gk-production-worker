param([string]$EnvFile = '.\.env')
$ErrorActionPreference = 'Stop'

$values = @{}
Get-Content $EnvFile | Where-Object { $_ -match '^[^#].*=' } | ForEach-Object {
    $parts = $_ -split '=', 2
    $values[$parts[0].Trim()] = $parts[1].Trim()
}
foreach ($name in @('GK_SITE_URL', 'GK_UNIFIED_API_TOKEN', 'GK_CONTROL_TOKEN')) {
    if ([string]::IsNullOrWhiteSpace($values[$name])) { throw "$name fehlt." }
}

$site = $values.GK_SITE_URL.TrimEnd('/')
$unifiedHeaders = @{ Authorization = 'Bearer ' + $values.GK_UNIFIED_API_TOKEN }
$controlHeaders = @{ Authorization = 'Bearer ' + $values.GK_CONTROL_TOKEN }
$signalMediaId = 29146
$fiberMediaId = 29147
$routerMediaId = 23278

function Read-Post([long]$Id) {
    $bytes = [Text.Encoding]::UTF8.GetBytes((@{ id = $Id } | ConvertTo-Json -Compress))
    Invoke-RestMethod ($site + '/wp-json/gk-unified-api/v1/read-post') -Method Post -Headers $unifiedHeaders -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 60
}

function Save-Post([long]$Id, [string]$Content) {
    $bytes = [Text.Encoding]::UTF8.GetBytes((@{ id = $Id; content = $Content } | ConvertTo-Json -Compress))
    $result = Invoke-RestMethod ($site + '/wp-json/gk-unified-api/v1/update-post') -Method Post -Headers $unifiedHeaders -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 60
    if ($result.updated -ne $true) { throw "Update nicht bestätigt: $Id" }
    $check = Read-Post $Id
    if ([string]$check.content -cne $Content) { throw "Speicherprüfung fehlgeschlagen: $Id" }
}

function Set-Featured([long]$Id, [long]$MediaId) {
    $bytes = [Text.Encoding]::UTF8.GetBytes((@{ post_id = $Id; attachment_id = $MediaId } | ConvertTo-Json -Compress))
    Invoke-RestMethod ($site + '/wp-json/gk-control/v1/media/set-featured') -Method Post -Headers $controlHeaders -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 60 | Out-Null
}

function Get-Media([long]$MediaId) {
    Invoke-RestMethod ($site + "/wp-json/wp/v2/media/$MediaId`?_fields=id,source_url,alt_text") -TimeoutSec 60
}

function Remove-Wrong-Figures([string]$Html) {
    $pattern = '(?is)<figure\b[^>]*>.*?<img\b[^>]*(?:koax|koax_huep|gk-symbol-koax|gkap-dsl-apl-kupfer-hausanschluss)[^>]*>.*?</figure>'
    $result = [regex]::Replace($Html, $pattern, '')
    [regex]::Replace($result, '(?is)<img\b[^>]*(?:koax|koax_huep|gk-symbol-koax|gkap-dsl-apl-kupfer-hausanschluss)[^>]*>', '')
}

function Remove-Duplicate-Figures([string]$Html, [string]$FeaturedUrl) {
    $seen = @{}
    if (-not [string]::IsNullOrWhiteSpace($FeaturedUrl)) { $seen[(($FeaturedUrl -split '\?')[0]).ToLowerInvariant()] = $true }
    $result = $Html
    foreach ($figure in @([regex]::Matches($Html, '(?is)<figure\b[^>]*>.*?</figure>'))) {
        $match = [regex]::Match($figure.Value, '(?is)<img\b[^>]*\bsrc=["''](?<src>[^"'']+)')
        if (-not $match.Success) { continue }
        $key = (([Net.WebUtility]::HtmlDecode($match.Groups['src'].Value) -split '\?')[0]).ToLowerInvariant()
        if ($seen.ContainsKey($key)) { $result = $result.Replace($figure.Value, '') } else { $seen[$key] = $true }
    }
    $result
}

$signal = Get-Media $signalMediaId
$fiber = Get-Media $fiberMediaId
$router = Get-Media $routerMediaId
$targets = @(
    @{ slug = 'apl-tae-signalweg'; featured = $signalMediaId },
    @{ slug = 'ftth-anschlussarten-erklaert'; featured = $fiberMediaId },
    @{ slug = 'gf-ap-erklaert'; featured = 28070 },
    @{ slug = 'router-im-keller'; featured = $routerMediaId }
)

$all = @()
foreach ($kind in @('posts', 'pages')) {
    $page = 1
    do {
        try {
            $batch = @(Invoke-RestMethod ($site + "/wp-json/wp/v2/$kind`?status=publish&per_page=100&page=$page&_fields=id,slug,link,featured_media,title") -TimeoutSec 60)
        } catch {
            if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 400) { $batch = @() } else { throw }
        }
        $all += $batch
        $page++
    } while ($batch.Count -eq 100)
}

$root = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $root ("backups\technician-review-v2-$stamp")
$reportDir = Join-Path $root 'reports'
$evidenceDir = Join-Path $root 'evidence'
New-Item $backupDir, $reportDir, $evidenceDir -ItemType Directory -Force | Out-Null
$rows = @()

foreach ($target in $targets) {
    $item = $all | Where-Object slug -eq $target.slug | Select-Object -First 1
    if ($null -eq $item) { throw "Zielseite fehlt: $($target.slug)" }
    $post = Read-Post ([long]$item.id)
    $old = [string]$post.content
    $new = Remove-Wrong-Figures $old
    $reason = @()

    if ($target.slug -eq 'apl-tae-signalweg') {
        $new = [regex]::Replace($new, '(?is)<section\b[^>]*data-gk-object-path=["''][^"'']+["''][^>]*>.*?</section>', '')
        $new = [regex]::Replace($new, '(?is)<section\b[^>]*data-gk-dsl-signalweg=["''][^"'']+["''][^>]*>.*?</section>', '')
        $new = [regex]::Replace($new, '(?is)<section\b[^>]*class=["''][^"'']*(?:gkve72-wrap|gkkg73-wrap)[^"'']*["''][^>]*>.*?</section>', '')
        $guard = '<style id="gk-signalweg-v4-guard">.gkve72-wrap,.gkkg73-wrap{display:none!important}</style>'
        $section = '<section class="gk-object-path-corrected" data-gk-object-path="mfg-kvz-v4"><h2>Korrekter VDSL-/FTTC-Signalweg</h2><p><strong>MFG mit DSLAM/MSAN → KVz → Kupfer-Zugangsnetz → APL → Endleitung → erste TAE → DSL-Router</strong></p><p>Der DSLAM beziehungsweise MSAN ist die aktive Technik <strong>im Multifunktionsgehäuse</strong>. Das MFG ist daher keine eigene Signalstufe vor oder hinter dem DSLAM. Der Kabelverzweiger (KVz) ist ein separater passiver Verteilpunkt des Kupfernetzes. MFG und KVz werden als graue Straßengehäuse dargestellt.</p><figure class="gk-signalweg-v4"><img src="' + [string]$signal.source_url + '" alt="VDSL-Signalweg mit DSLAM oder MSAN im grauen MFG, danach grauer KVz, APL, Endleitung, erste TAE und Router." width="1200" height="630"><figcaption>DSLAM/MSAN im MFG → KVz → APL → Endleitung → erste TAE → Router.</figcaption></figure></section>'
        $new = $guard + $section + $new
        $reason += 'DSL_SIGNALWEG_AND_LEGACY_BLOCKS_REPAIRED'
    }

    if ($target.slug -eq 'ftth-anschlussarten-erklaert') {
        $new = Remove-Duplicate-Figures $new ([string]$fiber.source_url)
        $reason += 'COAX_REMOVED_FIBER_FEATURED'
    }

    if ($target.slug -eq 'router-im-keller') {
        $new = Remove-Duplicate-Figures $new ([string]$router.source_url)
        $reason += 'COAX_REMOVED_ROUTER_FEATURED'
    }

    if ($target.slug -eq 'gf-ap-erklaert') {
        $featured = Get-Media ([long]$target.featured)
        $new = Remove-Duplicate-Figures $new ([string]$featured.source_url)
        $reason += 'DUPLICATE_BODY_AND_FEATURED_IMAGES_REMOVED'
    }

    [IO.File]::WriteAllText((Join-Path $backupDir ("post-$($item.id)-$($target.slug).html")), $old, [Text.UTF8Encoding]::new($false))
    if ($new -cne $old) { Save-Post ([long]$item.id) $new }
    Set-Featured ([long]$item.id) ([long]$target.featured)
    $rows += [pscustomobject]@{ id = $item.id; slug = $target.slug; status = 'SAVED_AND_READBACK_VERIFIED'; reason = $reason -join ',' }
}

$cache = Invoke-RestMethod ($site + '/wp-json/gk-unified-api/v1/clear-cache') -Method Post -Headers $unifiedHeaders -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('{}')) -TimeoutSec 60
if ($cache.cache_cleared -ne $true) { throw 'Cache-Leerung nicht bestätigt.' }

$wrongToken = '(?i)(koax_huep|gk-symbol-koax|gkap-dsl-apl-kupfer-hausanschluss)'
foreach ($target in $targets) {
    $item = $all | Where-Object slug -eq $target.slug | Select-Object -First 1
    $url = [string]$item.link + '?gk_v4=' + (Get-Date -Format 'HHmmssfff')
    $html = [string](Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 60).Content
    [IO.File]::WriteAllText((Join-Path $evidenceDir ("$($target.slug).html")), $html, [Text.UTF8Encoding]::new($false))
    if ($html -match $wrongToken) { throw "Falsches Koaxialbild öffentlich vorhanden: $($target.slug)" }
    if ($target.slug -eq 'apl-tae-signalweg') {
        foreach ($required in @('data-gk-object-path="mfg-kvz-v4"', 'MFG mit DSLAM/MSAN', 'KVz', [string]$signal.source_url)) {
            if ($html -notmatch [regex]::Escape($required)) { throw "Signalweg öffentlich nicht nachgewiesen: $required" }
        }
    }
}

$rows | Export-Csv (Join-Path $reportDir ("technician-review-v2-$stamp.csv")) -NoTypeInformation -Encoding UTF8
Write-Host "FERTIG: Vier Zielseiten gespeichert, Cache geleert und öffentliches HTML verifiziert. Backups=$backupDir"
