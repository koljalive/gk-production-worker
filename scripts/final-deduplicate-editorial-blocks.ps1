param(
  [ValidateSet('Preview','Apply')][string]$Mode = 'Preview'
)

$ErrorActionPreference = 'Stop'
$site = $env:GK_SITE_URL.TrimEnd('/')
$token = $env:GK_UNIFIED_API_TOKEN
if ([string]::IsNullOrWhiteSpace($site) -or [string]::IsNullOrWhiteSpace($token)) {
  throw 'GK_SITE_URL und GK_UNIFIED_API_TOKEN sind erforderlich.'
}

$headers = @{ Authorization = 'Bearer ' + $token }
$root = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $root ('backups\final-editorial-dedup-' + $stamp)
$reportDir = Join-Path $root 'reports'
New-Item $reportDir -ItemType Directory -Force | Out-Null
if ($Mode -eq 'Apply') {
  New-Item $backupDir -ItemType Directory -Force | Out-Null
}

function Read-Content([long]$id) {
  $body = [Text.Encoding]::UTF8.GetBytes((@{ id = $id } | ConvertTo-Json -Compress))
  Invoke-RestMethod ($site + '/wp-json/gk-unified-api/v1/read-post') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 90
}

function Save-Content([long]$id, [string]$content) {
  $body = [Text.Encoding]::UTF8.GetBytes((@{ id = $id; content = $content } | ConvertTo-Json -Compress))
  $result = Invoke-RestMethod ($site + '/wp-json/gk-unified-api/v1/update-post') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 90
  if ($result.updated -ne $true) {
    throw "Speicherung nicht bestätigt: $id"
  }
  $saved = [string](Read-Content $id).content
  if ($saved -cne $content) {
    throw "Readback stimmt nicht bytegenau überein: $id"
  }
}

function Visible-Text([string]$html) {
  $text = [regex]::Replace($html, '(?is)<script\b.*?</script>|<style\b.*?</style>|<!--.*?-->', ' ')
  $text = [regex]::Replace($text, '(?is)<[^>]+>', ' ')
  ([Net.WebUtility]::HtmlDecode($text) -replace '\s+', ' ').Trim()
}

function Repair-Mojibake([string]$html) {
  $value = $html
  $replacements = [ordered]@{
    'Ã¤' = 'ä'; 'Ã¶' = 'ö'; 'Ã¼' = 'ü'; 'Ã„' = 'Ä'; 'Ã–' = 'Ö'; 'Ãœ' = 'Ü'
    'ÃŸ' = 'ß'; 'Â ' = ' '; 'Â§' = '§'
  }
  foreach ($entry in $replacements.GetEnumerator()) {
    $value = $value.Replace([string]$entry.Key, [string]$entry.Value)
  }
  $value
}

function Merge-Official-Sources([string]$html, [ref]$changed) {
  $pattern = '(?is)<h2\b[^>]*>\s*Offizielle Quellen\s*</h2>\s*<ul\b[^>]*>(?<list>.*?)</ul>'
  $matches = [regex]::Matches($html, $pattern)
  if ($matches.Count -le 1) {
    return $html
  }

  $items = New-Object Collections.Generic.List[string]
  $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($match in $matches) {
    foreach ($li in [regex]::Matches($match.Groups['list'].Value, '(?is)<li\b[^>]*>.*?</li>')) {
      $href = [regex]::Match($li.Value, '(?is)href\s*=\s*["''](?<url>[^"'']+)["'']').Groups['url'].Value.TrimEnd('/')
      $key = if ($href) { $href } else { Visible-Text $li.Value }
      if ($key -and $seen.Add($key)) {
        $items.Add($li.Value.Trim())
      }
    }
  }
  if ($items.Count -lt 2) {
    return $html
  }

  $merged = '<h2>Offizielle Quellen</h2><ul>' + ($items -join '') + '</ul>'
  $first = $matches[0]
  $without = [regex]::Replace($html, $pattern, '')
  $insertAt = [Math]::Min($first.Index, $without.Length)
  $result = $without.Insert($insertAt, $merged)
  $changed.Value = $true
  $result
}

function Rename-Duplicate-Headings([string]$html, [ref]$changed) {
  $counts = @{}
  $pattern = '(?is)<h(?<level>[2-6])\b(?<attrs>[^>]*)>(?<body>.*?)</h\k<level>>'
  [regex]::Replace($html, $pattern, {
    param($match)
    $label = (Visible-Text $match.Groups['body'].Value).ToLowerInvariant()
    if (-not $label) {
      return $match.Value
    }
    if (-not $counts.ContainsKey($label)) {
      $counts[$label] = 1
      return $match.Value
    }
    $counts[$label]++
    if ($label -eq 'häufige fragen') {
      $replacement = if ($counts[$label] -eq 2) { 'Weitere häufige Fragen' } else { 'Zusätzliche Fragen' }
      $changed.Value = $true
      return '<h' + $match.Groups['level'].Value + $match.Groups['attrs'].Value + '>' + $replacement + '</h' + $match.Groups['level'].Value + '>'
    }
    return $match.Value
  })
}

function Remove-Exact-Duplicate-Paragraphs([string]$html, [ref]$changed) {
  $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  [regex]::Replace($html, '(?is)<p\b[^>]*>.*?</p>', {
    param($match)
    $text = Visible-Text $match.Value
    if ($text.Length -lt 80) {
      return $match.Value
    }
    if ($seen.Add($text)) {
      return $match.Value
    }
    $changed.Value = $true
    return ''
  })
}

$items = @()
foreach ($kind in @('posts','pages')) {
  for ($page = 1; $page -le 20; $page++) {
    try {
      $batch = @(Invoke-RestMethod ($site + "/wp-json/wp/v2/$kind`?status=publish&per_page=100&page=$page&_fields=id,slug,title") -TimeoutSec 90)
    } catch {
      if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 400) {
        break
      }
      throw
    }
    if ($batch.Count -eq 1 -and $batch[0] -is [Array]) {
      $batch = @($batch[0])
    }
    if (-not $batch.Count) {
      break
    }
    $items += @($batch | ForEach-Object {
      [pscustomobject]@{
        id = [long]$_.id
        slug = [string]$_.slug
        title = [Net.WebUtility]::HtmlDecode([string]$_.title.rendered)
        kind = $kind
      }
    })
    if ($batch.Count -lt 100) {
      break
    }
  }
}
if ($items.Count -lt 300) {
  throw "Unvollständige Inventur: $($items.Count)"
}

$rows = New-Object Collections.Generic.List[object]
foreach ($item in $items) {
  $original = [string](Read-Content $item.id).content
  $updated = Repair-Mojibake $original
  $mojibakeChanged = $updated -cne $original
  $sourceChanged = $false
  $updated = Merge-Official-Sources $updated ([ref]$sourceChanged)
  $headingChanged = $false
  $updated = Rename-Duplicate-Headings $updated ([ref]$headingChanged)
  $paragraphChanged = $false
  $updated = Remove-Exact-Duplicate-Paragraphs $updated ([ref]$paragraphChanged)
  $updated = $updated.Trim()

  if ($updated -ceq $original) {
    continue
  }
  if ([string]::IsNullOrWhiteSpace((Visible-Text $updated))) {
    throw "Bereinigung würde leeren Inhalt erzeugen: $($item.id)"
  }
  if ($Mode -eq 'Apply') {
    [IO.File]::WriteAllText((Join-Path $backupDir ("post-$($item.id)-$($item.slug).html")), $original, [Text.UTF8Encoding]::new($false))
    Save-Content $item.id $updated
  }
  $rows.Add([pscustomobject]@{
    id = $item.id
    kind = $item.kind
    slug = $item.slug
    title = $item.title
    status = if ($Mode -eq 'Apply') { 'UPDATED_AND_READBACK_VERIFIED' } else { 'READY' }
    sources_merged = $sourceChanged
    headings_renamed = $headingChanged
    paragraphs_removed = $paragraphChanged
    mojibake_repaired = $mojibakeChanged
  })
}

if ($Mode -eq 'Apply') {
  $cache = Invoke-RestMethod ($site + '/wp-json/gk-unified-api/v1/clear-cache') -Method Post -Headers $headers -ContentType 'application/json' -Body '{}' -TimeoutSec 90
  if ($cache.cache_cleared -ne $true) {
    throw 'Cache-Leerung nicht bestätigt.'
  }
}

$rows | Export-Csv (Join-Path $reportDir ("final-editorial-dedup-$Mode-$stamp.csv")) -NoTypeInformation -Encoding UTF8
Write-Host ("FERTIG: Modus=$Mode | Inventar=$($items.Count) | Aktualisiert=$($rows.Count) | Fehler=0")
