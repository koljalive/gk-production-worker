Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PlainSecret([string]$Path) {
    $secure = Get-Content $Path | ConvertTo-SecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Invoke-Wp([string]$Method, [string]$Path, [hashtable]$Headers, [object]$Body = $null) {
    $uri = 'https://glasfaser-kompass.de/wp-json' + $Path
    $params = @{ Uri = $uri; Method = $Method; Headers = $Headers; UseBasicParsing = $true; TimeoutSec = 180 }
    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 50 -Compress
        $params.Body = [Text.Encoding]::UTF8.GetBytes($json)
        $params.ContentType = 'application/json; charset=utf-8'
    }
    $response = Invoke-WebRequest @params
    if ([string]::IsNullOrWhiteSpace([string]$response.Content)) { return $null }
    return ([string]$response.Content | ConvertFrom-Json)
}

function Is-Schematic([string]$Url) {
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    return $Url -match 'exec-|diagram|schema|signalweg|illustr|infograf|bauformen|collage|skizze|\.svg(?:\?|$)'
}

function Get-ImageStem([string]$Url) {
    if ([string]::IsNullOrWhiteSpace($Url)) { return '' }
    try { $name = [IO.Path]::GetFileNameWithoutExtension(([Uri]$Url).AbsolutePath) }
    catch { $name = [IO.Path]::GetFileNameWithoutExtension($Url) }
    return ([regex]::Replace([string]$name, '-\d+x\d+$', '')).ToLowerInvariant()
}

function Get-ImageSources([string]$Html) {
    $sources = @()
    foreach ($match in [regex]::Matches($Html, '<img\b[^>]*>', 'IgnoreCase')) {
        $src = [regex]::Match($match.Value, '\bsrc=["'']([^"'']+)["'']', 'IgnoreCase')
        if ($src.Success) { $sources += @([string]$src.Groups[1].Value) }
    }
    return @($sources)
}

function Get-SchematicSources([string]$Html) {
    return @(Get-ImageSources $Html | Where-Object { Is-Schematic $_ })
}

function Get-Category([string]$TitleSlug, [string]$Raw) {
    $groups = [ordered]@{
        wifi   = 'wlan|wi-fi|wifi|mesh|repeater|access point|homeoffice'
        router = 'router|fritz|speedport'
        fiber  = 'glasfaser|gf-ap|gf-ta|gfta|ont|ftth|fiber|spleiss|spleiß'
        field  = 'techniker|telekom|apl|tae|dsl|kupfer|leitung|störung|montage|installation'
    }
    $scores = @{}
    foreach ($name in $groups.Keys) {
        $score = 0
        if ($TitleSlug -match $groups[$name]) { $score += 4 }
        if ($Raw -match $groups[$name]) { $score += 1 }
        $scores[$name] = $score
    }
    $max = ($scores.Values | Measure-Object -Maximum).Maximum
    if ($max -lt 1) { return $null }
    $winners = @($scores.Keys | Where-Object { $scores[$_] -eq $max })
    if ($winners.Count -ne 1) { return $null }
    return [string]$winners[0]
}

function Get-MediaId([string]$Category) {
    switch ($Category) {
        'wifi'   { return 29403 }
        'router' { return 29397 }
        'fiber'  { return 29401 }
        'field'  { return 29398 }
        default  { return 0 }
    }
}

function Replace-SchematicImages([string]$Raw, [string]$ReplacementUrl, [string]$Alt, [ref]$Count) {
    $Count.Value = 0
    $regex = [regex]::new('<img\b[^>]*>', 'IgnoreCase')
    return $regex.Replace($Raw, {
        param($match)
        $tag = $match.Value
        $srcMatch = [regex]::Match($tag, '\bsrc=["'']([^"'']+)["'']', 'IgnoreCase')
        if ((-not $srcMatch.Success) -or (-not (Is-Schematic ([string]$srcMatch.Groups[1].Value)))) { return $tag }
        $Count.Value++
        $updated = [regex]::Replace($tag, '\bsrc=["''][^"'']+["'']', ('src="' + $ReplacementUrl + '"'), 'IgnoreCase')
        $updated = [regex]::Replace($updated, '\s+srcset=["''][^"'']*["'']', '', 'IgnoreCase')
        $updated = [regex]::Replace($updated, '\s+sizes=["''][^"'']*["'']', '', 'IgnoreCase')
        $encodedAlt = [System.Net.WebUtility]::HtmlEncode($Alt)
        if ([regex]::IsMatch($updated, '\balt=["''][^"'']*["'']', 'IgnoreCase')) {
            $updated = [regex]::Replace($updated, '\balt=["''][^"'']*["'']', ('alt="' + $encodedAlt + '"'), 'IgnoreCase')
        } else {
            $updated = $updated -replace '>$', (' alt="' + $encodedAlt + '">')
        }
        return $updated
    })
}

function Probe-Public([string]$Url, [string]$ExpectedImage = '') {
    try {
        $separator = if ($Url.Contains('?')) { '&' } else { '?' }
        $probeUrl = $Url + $separator + 'gkverify=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $headers = @{ 'Cache-Control' = 'no-cache'; 'Pragma' = 'no-cache' }
        $response = Invoke-WebRequest -Uri $probeUrl -Headers $headers -UseBasicParsing -TimeoutSec 120
        $html = [string]$response.Content
        $h1 = ([regex]::Matches($html, '<h1\b', 'IgnoreCase')).Count
        $images = @(Get-ImageSources $html)
        $schematicSources = @($images | Where-Object { Is-Schematic $_ })
        $expectedOk = $true
        if (-not [string]::IsNullOrWhiteSpace($ExpectedImage)) {
            $expectedStem = Get-ImageStem $ExpectedImage
            $expectedOk = $false
            foreach ($src in $images) {
                if ((Get-ImageStem $src) -eq $expectedStem) { $expectedOk = $true; break }
            }
        }
        return [pscustomobject]@{
            ok = $true
            http = [int]$response.StatusCode
            h1 = $h1
            schematic = $schematicSources.Count
            schematic_srcs = $schematicSources
            expected_image = $expectedOk
            image_count = $images.Count
            image_srcs = $images
        }
    } catch {
        return [pscustomobject]@{
            ok = $false; http = $null; h1 = $null; schematic = $null; schematic_srcs = @();
            expected_image = $false; image_count = 0; image_srcs = @(); error = $_.Exception.Message
        }
    }
}

function Purge([string]$Url) {
    try { Invoke-WebRequest -Uri $Url -Method PURGE -UseBasicParsing -TimeoutSec 60 | Out-Null } catch { }
}

function Wait-Probe([string]$Url, [string]$ExpectedImage) {
    $last = $null
    for ($i = 0; $i -lt 10; $i++) {
        $last = Probe-Public $Url $ExpectedImage
        if ($last.ok -and $last.http -eq 200 -and $last.h1 -eq 1 -and $last.schematic -eq 0 -and $last.expected_image) { return $last }
        Start-Sleep -Seconds 8
    }
    return $last
}

function Find-Chrome() {
    $candidates = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }
    return $null
}

function Save-Result([object]$Result, [string]$Workspace) {
    $Result.finished_utc = (Get-Date).ToUniversalTime().ToString('o')
    $path = Join-Path $Workspace 'bridge/multi-acceptance-pilot-result.json'
    [IO.File]::WriteAllText($path, ($Result | ConvertTo-Json -Depth 40), (New-Object Text.UTF8Encoding($false)))
}

$workspace = $env:GITHUB_WORKSPACE
$auditPath = Join-Path $workspace 'bridge/gk10-full-result.json'
if (-not (Test-Path $auditPath)) { throw 'Missing gk10-full-result.json' }
$audit = (Get-Content $auditPath -Raw) | ConvertFrom-Json
$candidates = @($audit.results | Where-Object { $_.score -lt 10 -and (($_.issues -contains 'h1_count_2') -or ([int]$_.suspicious_images -gt 0)) })
if ($candidates.Count -lt 1) { throw 'No pilot candidates found in full audit.' }

$secretDir = Join-Path $env:APPDATA 'GK-MCP-Tunnel'
$user = (Get-Content (Join-Path $secretDir 'wp-user.txt') -Raw).Trim()
$pass = Get-PlainSecret (Join-Path $secretDir 'wp-password.dat')
try { $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$user`:$pass")) }
finally { Remove-Variable pass -ErrorAction SilentlyContinue }
$wpHeaders = @{ Authorization = "Basic $basic"; Accept = 'application/json' }
Remove-Variable basic -ErrorAction SilentlyContinue

$approvedMedia = @{}
foreach ($mediaId in 29397, 29398, 29401, 29403) {
    $approvedMedia[$mediaId] = Invoke-Wp 'GET' "/wp/v2/media/$($mediaId)?context=edit&_fields=id,title,source_url,alt_text,mime_type" $wpHeaders
}

$chrome = Find-Chrome
if (-not $chrome) { throw 'Chrome not found; visual acceptance evidence is mandatory.' }

$result = [ordered]@{
    started_utc = (Get-Date).ToUniversalTime().ToString('o')
    pilot_size = 8
    gate_version = 'multi-editorial-v4-preflight-map-rollback'
    failure_classes_guarded = @(
        'execution_policy', 'unsafe_media_semantics', 'powershell_interpolation', 'powershell_token_spacing',
        'stale_audit_state', 'non_idempotent_repair', 'responsive_image_variants', 'unmapped_public_schematic',
        'partial_write_without_rollback', 'missing_failure_evidence'
    )
    status = 'PREFLIGHT'
    preflight_checked = 0
    stale_skipped = 0
    blocked = 0
    selected = 0
    changed = 0
    verified = 0
    rollback_attempted = $false
    rollback_ok = $null
    blockers = @()
    plans = @()
    items = @()
    screenshots = @()
    finished_utc = $null
}

$plans = @()

foreach ($candidate in $candidates) {
    if ($plans.Count -ge 8) { break }
    $type = if ([string]$candidate.type -eq 'page') { 'pages' } else { 'posts' }
    $id = [int]$candidate.id
    $result.preflight_checked++

    try {
        $item = Invoke-Wp 'GET' "/wp/v2/$type/$($id)?context=edit&_fields=id,modified,slug,link,title,featured_media,content" $wpHeaders
        if ($null -eq $item) { throw 'WP edit object missing' }
        $url = [string]$item.link
        $pre = Probe-Public $url
        if ((-not $pre.ok) -or $pre.http -ne 200) {
            $result.blocked++
            $result.blockers += @([ordered]@{ id = $id; reason = 'public_probe_failed'; probe = $pre })
            continue
        }
        if ($pre.h1 -eq 1 -and $pre.schematic -eq 0) {
            $result.stale_skipped++
            continue
        }

        $raw = [string]$item.content.raw
        $title = [string]$item.title.raw
        $slug = [string]$item.slug
        $rawH1 = ([regex]::Matches($raw, '<h1\b', 'IgnoreCase')).Count
        $needsH1 = ($pre.h1 -ne 1)
        $needsImage = ([int]$pre.schematic -gt 0)

        if ($needsH1) {
            if ($pre.h1 -lt 2 -or $rawH1 -lt 1 -or (($pre.h1 - $rawH1) -ne 1)) {
                $result.blocked++
                $result.blockers += @([ordered]@{ id = $id; reason = 'h1_not_safely_mappable'; public_h1 = $pre.h1; raw_h1 = $rawH1 })
                continue
            }
        }

        $category = $null
        $replacementMedia = $null
        $replacementUrl = ''
        $replaceInline = $false
        $replaceFeatured = $false
        $rawSchematicSources = @(Get-SchematicSources $raw)
        $rawSchematicStems = @($rawSchematicSources | ForEach-Object { Get-ImageStem $_ } | Select-Object -Unique)
        $featuredId = [int]$item.featured_media
        $featuredSource = ''
        $featuredStem = ''
        $featuredIsSchematic = $false

        if ($featuredId -gt 0) {
            $featured = Invoke-Wp 'GET' "/wp/v2/media/$($featuredId)?context=edit&_fields=id,source_url,mime_type,title,alt_text" $wpHeaders
            if ($null -ne $featured) {
                $featuredSource = [string]$featured.source_url
                $featuredStem = Get-ImageStem $featuredSource
                $featuredIsSchematic = Is-Schematic $featuredSource
            }
        }

        if ($needsImage) {
            $category = Get-Category ("$title $slug") $raw
            if ([string]::IsNullOrWhiteSpace([string]$category)) {
                $result.blocked++
                $result.blockers += @([ordered]@{ id = $id; reason = 'image_category_ambiguous'; public_schematic = $pre.schematic_srcs })
                continue
            }
            $replacementId = Get-MediaId $category
            if ($replacementId -eq 0) {
                $result.blocked++
                $result.blockers += @([ordered]@{ id = $id; reason = 'no_approved_replacement_media'; category = $category })
                continue
            }
            $replacementMedia = $approvedMedia[$replacementId]
            if ($null -eq $replacementMedia -or ([string]$replacementMedia.mime_type) -notmatch '^image/' -or [string]::IsNullOrWhiteSpace([string]$replacementMedia.source_url) -or (Is-Schematic ([string]$replacementMedia.source_url))) {
                $result.blocked++
                $result.blockers += @([ordered]@{ id = $id; reason = 'replacement_media_invalid'; media_id = $replacementId })
                continue
            }
            $replacementUrl = [string]$replacementMedia.source_url

            $unmapped = @()
            foreach ($publicSource in @($pre.schematic_srcs)) {
                $stem = Get-ImageStem $publicSource
                $mapsInline = $rawSchematicStems -contains $stem
                $mapsFeatured = ($featuredIsSchematic -and -not [string]::IsNullOrWhiteSpace($featuredStem) -and $featuredStem -eq $stem)
                if (-not ($mapsInline -or $mapsFeatured)) { $unmapped += @($publicSource) }
                if ($mapsInline) { $replaceInline = $true }
                if ($mapsFeatured) { $replaceFeatured = $true }
            }
            if ($unmapped.Count -gt 0) {
                $result.blocked++
                $result.blockers += @([ordered]@{
                    id = $id; reason = 'unmapped_public_schematic'; public_schematic = $pre.schematic_srcs;
                    raw_schematic = $rawSchematicSources; featured_source = $featuredSource; unmapped = $unmapped
                })
                continue
            }
            if (-not ($replaceInline -or $replaceFeatured)) {
                $result.blocked++
                $result.blockers += @([ordered]@{ id = $id; reason = 'no_editable_image_mapping'; public_schematic = $pre.schematic_srcs })
                continue
            }
        }

        $plan = [pscustomobject]@{
            id = $id
            type = $type
            title = $title
            slug = $slug
            url = $url
            original_content = $raw
            original_featured_media = $featuredId
            needs_h1 = $needsH1
            raw_h1 = $rawH1
            needs_image = $needsImage
            category = $category
            replacement_media_id = if ($needsImage) { [int]$replacementMedia.id } else { 0 }
            replacement_url = $replacementUrl
            replace_inline = $replaceInline
            replace_featured = $replaceFeatured
            pre_probe = $pre
        }
        $plans += @($plan)
        $result.plans += @([ordered]@{
            id = $id; type = $type; title = $title; url = $url; needs_h1 = $needsH1; needs_image = $needsImage;
            category = $category; replacement_media_id = $plan.replacement_media_id; replace_inline = $replaceInline;
            replace_featured = $replaceFeatured; pre_probe = $pre
        })
    } catch {
        $result.blocked++
        $result.blockers += @([ordered]@{ id = $id; reason = 'preflight_exception'; error = $_.Exception.Message })
    }
}

$result.selected = $plans.Count
if ($plans.Count -lt 8) {
    $result.status = 'FAILED_PREFLIGHT_NOT_ENOUGH_SAFE_TARGETS'
    Save-Result $result $workspace
    throw "Preflight found only $($plans.Count) fully mapped safe targets; required 8. No production writes were made."
}

$backupDir = 'C:\GKBridge\backups'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
foreach ($plan in $plans) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = Join-Path $backupDir ("$($plan.type)-$($plan.id)-$stamp-v4-before.json")
    $backupObject = [ordered]@{
        id = $plan.id; type = $plan.type; url = $plan.url;
        featured_media = $plan.original_featured_media; content_raw = $plan.original_content
    }
    [IO.File]::WriteAllText($backupPath, ($backupObject | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
    $plan | Add-Member -NotePropertyName backup_path -NotePropertyValue $backupPath
}

$result.status = 'WRITING'
$changedPlans = @()

try {
    foreach ($plan in $plans) {
        $newContent = [string]$plan.original_content
        $h1Changed = $false
        $inlineChanged = 0

        if ($plan.needs_h1) {
            $before = $newContent
            $newContent = [regex]::Replace($newContent, '<h1\b([^>]*)>', '<h2$1>', 'IgnoreCase')
            $newContent = [regex]::Replace($newContent, '</h1\s*>', '</h2>', 'IgnoreCase')
            $h1Changed = ($newContent -ne $before)
            if (-not $h1Changed) { throw "Planned H1 repair did not change content for target $($plan.id)." }
        }

        if ($plan.replace_inline) {
            $alt = "Reales Foto passend zu $($plan.title)"
            $approved = $approvedMedia[[int]$plan.replacement_media_id]
            if (-not [string]::IsNullOrWhiteSpace([string]$approved.alt_text)) { $alt = [string]$approved.alt_text }
            $count = 0
            $newContent = Replace-SchematicImages $newContent ([string]$plan.replacement_url) $alt ([ref]$count)
            $inlineChanged = $count
            if ($inlineChanged -lt 1) { throw "Mapped inline schematic disappeared before write for target $($plan.id)." }
        }

        $body = [ordered]@{}
        if ($newContent -ne $plan.original_content) { $body.content = $newContent }
        if ($plan.replace_featured) { $body.featured_media = [int]$plan.replacement_media_id }
        if ($body.Count -lt 1) { throw "Empty write body for target $($plan.id)." }

        Invoke-Wp 'POST' "/wp/v2/$($plan.type)/$($plan.id)" $wpHeaders $body | Out-Null
        $changedPlans += @($plan)
        $result.changed++

        $verifyEdit = Invoke-Wp 'GET' "/wp/v2/$($plan.type)/$($plan.id)?context=edit&_fields=id,content,featured_media" $wpHeaders
        if ($null -eq $verifyEdit) { throw "WP write verification read failed for target $($plan.id)." }
        if ($plan.replace_inline -and @(Get-SchematicSources ([string]$verifyEdit.content.raw)).Count -gt 0) {
            throw "WP edit verification still contains schematic inline image for target $($plan.id)."
        }
        if ($plan.replace_featured -and [int]$verifyEdit.featured_media -ne [int]$plan.replacement_media_id) {
            throw "WP edit verification has wrong featured_media for target $($plan.id)."
        }

        Purge $plan.url
        $probe = Wait-Probe $plan.url ([string]$plan.replacement_url)
        $ok = $probe.ok -and $probe.http -eq 200 -and $probe.h1 -eq 1 -and $probe.schematic -eq 0 -and $probe.expected_image
        if (-not $ok) {
            throw "Public verification failed for target $($plan.id): h1=$($probe.h1), schematic=$($probe.schematic), expected=$($probe.expected_image)."
        }

        $safeName = "pilot-$($plan.id)"
        $desktop = Join-Path $workspace ("bridge/$safeName-desktop.png")
        $mobile = Join-Path $workspace ("bridge/$safeName-mobile.png")
        & $chrome --headless=new --disable-gpu --hide-scrollbars --window-size=1440,1200 --screenshot=$desktop $plan.url | Out-Null
        & $chrome --headless=new --disable-gpu --hide-scrollbars --window-size=390,844 --screenshot=$mobile $plan.url | Out-Null
        if ((-not (Test-Path $desktop)) -or (-not (Test-Path $mobile))) { throw "Screenshot evidence missing for target $($plan.id)." }

        $result.verified++
        $result.screenshots += @(
            [ordered]@{ id = $plan.id; viewport = 'desktop'; path = (Split-Path $desktop -Leaf) },
            [ordered]@{ id = $plan.id; viewport = 'mobile'; path = (Split-Path $mobile -Leaf) }
        )
        $result.items += @([ordered]@{
            id = $plan.id; type = $plan.type; title = $plan.title; url = $plan.url; backup = $plan.backup_path;
            h1_changed = $h1Changed; inline_images_replaced = $inlineChanged;
            featured_changed = $plan.replace_featured; media_id = $plan.replacement_media_id; probe = $probe; accepted = $true
        })
    }

    if ($result.verified -ne 8) { throw "Verification count is $($result.verified), expected 8." }
    if ($result.screenshots.Count -ne 16) { throw "Screenshot count is $($result.screenshots.Count), expected 16." }
    $result.status = 'PASSED'
    Save-Result $result $workspace
    Write-Host "V4 multi acceptance pilot passed: 8/8 verified, 16/16 screenshots."
}
catch {
    $failureMessage = $_.Exception.Message
    $result.status = 'FAILED_WRITE_OR_VERIFY_ROLLBACK'
    $result.rollback_attempted = $true
    $rollbackFailures = @()

    foreach ($plan in @($changedPlans | Select-Object -Reverse)) {
        try {
            $restore = [ordered]@{ content = [string]$plan.original_content; featured_media = [int]$plan.original_featured_media }
            Invoke-Wp 'POST' "/wp/v2/$($plan.type)/$($plan.id)" $wpHeaders $restore | Out-Null
            Purge $plan.url
            $result.items += @([ordered]@{ id = $plan.id; rollback = 'restored'; url = $plan.url })
        } catch {
            $rollbackFailures += @([ordered]@{ id = $plan.id; error = $_.Exception.Message })
        }
    }

    $result.rollback_ok = ($rollbackFailures.Count -eq 0)
    if ($rollbackFailures.Count -gt 0) { $result.items += @([ordered]@{ rollback_failures = $rollbackFailures }) }
    $result.items += @([ordered]@{ failure = $failureMessage })
    Save-Result $result $workspace
    throw "$failureMessage Rollback attempted=$($result.rollback_attempted) rollback_ok=$($result.rollback_ok)."
}
