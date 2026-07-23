param(
    [ValidateSet('Preview','Apply')][string]$Mode = 'Preview',
    [string]$Confirm = ''
)

$ErrorActionPreference = 'Stop'
if ($Mode -eq 'Apply' -and $Confirm -cne 'DSL DUBLETTEN ARCHIVIEREN') {
    throw 'Bestätigung fehlt.'
}

foreach ($name in @('GK_SITE_URL','GK_UNIFIED_API_TOKEN','WP_USERNAME','WP_APPLICATION_PASSWORD')) {
    if ([string]::IsNullOrWhiteSpace((Get-Item "env:$name" -ErrorAction SilentlyContinue).Value)) {
        throw "$name fehlt."
    }
}

$site = $env:GK_SITE_URL.TrimEnd('/')
$pairText = "$($env:WP_USERNAME):$($env:WP_APPLICATION_PASSWORD)"
$basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pairText))
$headers = @{ Authorization = "Basic $basic" }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$root = Split-Path -Parent $PSScriptRoot
$backupDir = Join-Path $root "backups\dsl-redirect-archive-$stamp"
$reportDir = Join-Path $root 'reports'
New-Item $backupDir -ItemType Directory -Force | Out-Null
New-Item $reportDir -ItemType Directory -Force | Out-Null

$pairs = @(
    @{ Source=5003; SourceSlug='tal-erklaert-voll'; Target=3012; TargetSlug='tal-erklaert' },
    @{ Source=5004; SourceSlug='kvz-erklaert-voll'; Target=3013; TargetSlug='kvz-erklaert' },
    @{ Source=5005; SourceSlug='hvt-erklaert-voll'; Target=3014; TargetSlug='hvt-erklaert' },
    @{ Source=5007; SourceSlug='vectoring-erklaert-voll'; Target=3016; TargetSlug='vectoring-erklaert' },
    @{ Source=5008; SourceSlug='supervectoring-erklaert-voll'; Target=3017; TargetSlug='supervectoring-erklaert' },
    @{ Source=11004; SourceSlug='erste-tae-pruefen-2'; Target=9005; TargetSlug='erste-tae-pruefen' },
    @{ Source=12003; SourceSlug='apl-pruefen-2'; Target=9004; TargetSlug='apl-pruefen' }
)

function Invoke-Wp([string]$Uri, [string]$Method = 'GET', [object]$Body = $null) {
    $args = @{
        Uri = $Uri
        Method = $Method
        Headers = $headers
        TimeoutSec = 60
    }
    if ($null -ne $Body) {
        $args.ContentType = 'application/json; charset=utf-8'
        $args.Body = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 20 -Compress))
    }
    Invoke-RestMethod @args
}

function Read-Post([long]$Id) {
    Invoke-Wp "$site/wp-json/wp/v2/posts/$Id`?context=edit"
}

function Clear-SiteCache {
    $cacheHeaders = @{ Authorization = "Bearer $($env:GK_UNIFIED_API_TOKEN)" }
    $result = Invoke-RestMethod -Uri "$site/wp-json/gk-unified-api/v1/clear-cache" -Method Post -Headers $cacheHeaders -ContentType 'application/json; charset=utf-8' -Body '{}' -TimeoutSec 60
    if ($result.cache_cleared -ne $true) { throw 'Cache-Leerung wurde nicht bestätigt.' }
}

function Assert-Post([object]$Post, [long]$Id, [string]$Slug, [string]$Status) {
    if ([long]$Post.id -ne $Id -or [string]$Post.slug -cne $Slug -or [string]$Post.status -cne $Status) {
        throw "Vorbedingung fehlgeschlagen: ID=$Id, erwartet $Slug/$Status, erhalten $($Post.slug)/$($Post.status)"
    }
}

function Get-LiveResponse([string]$Url) {
    try {
        Invoke-WebRequest -Uri $Url -MaximumRedirection 0 -SkipHttpErrorCheck -TimeoutSec 45
    } catch {
        if ($_.Exception.Response) { return $_.Exception.Response }
        throw
    }
}

$rows = @()
foreach ($pair in $pairs) {
    $source = Read-Post $pair.Source
    $target = Read-Post $pair.Target
    Assert-Post $source $pair.Source $pair.SourceSlug 'publish'
    Assert-Post $target $pair.Target $pair.TargetSlug 'publish'

    $sourceUrl = "$site/$($pair.SourceSlug)/"
    $targetUrl = "$site/$($pair.TargetSlug)/"
    $before = Get-LiveResponse $sourceUrl
    if ([int]$before.StatusCode -ne 200) {
        throw "Alt-URL liefert vor Änderung nicht 200: $sourceUrl ($([int]$before.StatusCode))"
    }

    $source | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $backupDir "source-$($pair.Source).json") -Encoding UTF8
    $target | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $backupDir "target-$($pair.Target).json") -Encoding UTF8

    $status = 'READY'
    if ($Mode -eq 'Apply') {
        Invoke-Wp "$site/wp-json/rankmath/v1/updateRedirection" 'POST' @{
            objectID = $pair.Source
            objectType = 'post'
            hasRedirect = $true
            redirectionUrl = $targetUrl
            redirectionType = '301'
        } | Out-Null

        Invoke-Wp "$site/wp-json/wp/v2/posts/$($pair.Source)" 'POST' @{ status = 'draft' } | Out-Null

        $verifySource = Read-Post $pair.Source
        Assert-Post $verifySource $pair.Source $pair.SourceSlug 'draft'
        Clear-SiteCache
        $live = Get-LiveResponse $sourceUrl
        $location = [string]$live.Headers.Location
        if ([int]$live.StatusCode -ne 301 -or $location.TrimEnd('/') -cne $targetUrl.TrimEnd('/')) {
            Invoke-Wp "$site/wp-json/wp/v2/posts/$($pair.Source)" 'POST' @{ status = 'publish' } | Out-Null
            Clear-SiteCache
            throw "Redirect-Prüfung fehlgeschlagen; Quelle wurde zurückveröffentlicht: $sourceUrl -> $([int]$live.StatusCode) $location"
        }
        $status = 'ARCHIVED_AND_301_VERIFIED'
    }

    $rows += [pscustomobject]@{
        source_id = $pair.Source
        source_url = $sourceUrl
        target_id = $pair.Target
        target_url = $targetUrl
        status = $status
    }
}

$report = Join-Path $reportDir "dsl-redirect-archive-$($Mode.ToLowerInvariant())-$stamp.csv"
$rows | Export-Csv $report -NoTypeInformation -Encoding UTF8
Write-Host "FERTIG: Modus=$Mode | Verifiziert=$(@($rows).Count)"
