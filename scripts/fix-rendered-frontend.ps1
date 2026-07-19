param(
  [string]$EnvFile = '.\.env',
  [ValidateSet('Preview','Apply')][string]$Mode = 'Preview',
  [string]$Confirm = ''
)

$ErrorActionPreference = 'Stop'
if ($Mode -eq 'Apply' -and $Confirm -cne 'GERENDERTES FRONTEND BEREINIGEN') { throw 'Bestaetigung fehlt.' }

$v = @{}
Get-Content $EnvFile | Where-Object { $_ -match '^[^#].*=' } | ForEach-Object {
  $p = $_ -split '=', 2
  $v[$p[0].Trim()] = $p[1].Trim()
}
foreach ($name in @('GK_SITE_URL','GK_UNIFIED_API_TOKEN')) {
  if ([string]::IsNullOrWhiteSpace($v[$name])) { throw "$name fehlt." }
}

$site = $v.GK_SITE_URL.TrimEnd('/')
$headers = @{ Authorization = 'Bearer ' + $v.GK_UNIFIED_API_TOKEN }
$items = @()
foreach ($kind in @('posts','pages')) {
  $page = 1
  do {
    try {
      $batch = @(Invoke-RestMethod ($site + "/wp-json/wp/v2/$kind`?status=publish&per_page=100&page=$page&_fields=id,title,link") -TimeoutSec 45)
      if ($batch.Count -eq 1 -and $batch[0] -is [Array]) { $batch = @($batch[0]) }
    } catch {
      if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 400) { $batch = @() } else { throw }
    }
    $items += $batch
    $page++
  } while ($batch.Count -eq 100)
}

$signal = Invoke-RestMethod ($site + '/wp-json/wp/v2/media/28085?_fields=source_url,alt_text') -TimeoutSec 45
$style = '<style id="gk-frontend-dedup">.gk9-authorbox,.gk9-tarifcheck{display:none!important}</style>'
$root = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $root ("backups\frontend-fix-$stamp")
$reportDir = Join-Path $root 'reports'
New-Item $reportDir -ItemType Directory -Force | Out-Null
if ($Mode -eq 'Apply') { New-Item $backupDir -ItemType Directory -Force | Out-Null }
$rows = @()

foreach ($item in ($items | Sort-Object { [long]$_.id } -Unique)) {
  $id = [long]$item.id
  $title = [Net.WebUtility]::HtmlDecode([string]$item.title.rendered)
  $request = [Text.Encoding]::UTF8.GetBytes((@{ id = $id } | ConvertTo-Json -Compress))
  $post = Invoke-RestMethod ($site + '/wp-json/gk-unified-api/v1/read-post') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $request
  $old = [string]$post.content
  $new = $old
  $reasons = New-Object Collections.Generic.List[string]

  if ($new -notmatch 'id=["'']gk-frontend-dedup["'']') {
    $new = $style + $new
    $reasons.Add('HIDE_LEGACY_DYNAMIC_BLOCKS')
  }

  if ($new -match '(?is)<article\b[^>]*class=["''][^"'']*gk-auto-article[^"'']*["''][^>]*>.*?<h2>\s*FAQ\s*</h2>') {
    $new = [regex]::Replace($new, '(?is)(<article\b[^>]*class=["''][^"'']*gk-auto-article[^"'']*["''][^>]*>.*?)<h2>\s*FAQ\s*</h2>.*?</article>', '$1</article>', 1)
    $reasons.Add('REMOVE_DUPLICATE_INLINE_FAQ')
  }

  if ($title -match '(?i)DSL.?Bauteile|DSL.?Signalweg|APL.*TAE|TAE.*APL|Endleitung|Hausverkabelung') {
    $alt = [Net.WebUtility]::HtmlEncode($(if ([string]::IsNullOrWhiteSpace([string]$signal.alt_text)) { 'DSL-Signalweg von DSLAM und MFG ueber APL und TAE bis zum Router.' } else { [string]$signal.alt_text }))
    $figure = '<figure class="gk-article-visual gk-verified-signal-path"><img src="' + [string]$signal.source_url + '" alt="' + $alt + '" loading="lazy"><figcaption>DSL-Signalweg: DSLAM, MFG, APL, TAE und Router.</figcaption></figure>'
    if ($new -match '(?is)<figure\b[^>]*class=["''][^"'']*gk-article-visual[^"'']*["''][^>]*>.*?</figure>') {
      $new = [regex]::Replace($new, '(?is)<figure\b[^>]*class=["''][^"'']*gk-article-visual[^"'']*["''][^>]*>.*?</figure>', [Text.RegularExpressions.MatchEvaluator]{ param($m) $figure }, 1)
    } else {
      $new = $figure + $new
    }
    $reasons.Add('VERIFIED_DSL_SIGNAL_PATH')
  }

  if ($new -ceq $old) { continue }
  $status = 'READY'
  if ($Mode -eq 'Apply') {
    [IO.File]::WriteAllText((Join-Path $backupDir ("post-$id.html")), $old, [Text.UTF8Encoding]::new($false))
    $payload = [Text.Encoding]::UTF8.GetBytes((@{ id = $id; content = $new } | ConvertTo-Json -Compress))
    $updated = Invoke-RestMethod ($site + '/wp-json/gk-unified-api/v1/update-post') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $payload
    if ($updated.updated -ne $true) { throw "Update nicht bestaetigt: $id" }
    $verify = Invoke-RestMethod ($site + '/wp-json/gk-unified-api/v1/read-post') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $request
    $saved = [string]$verify.content
    if ($saved -notmatch 'gk-frontend-dedup') { throw "Frontend-Stil nicht gespeichert: $id" }
    if ($reasons.Contains('VERIFIED_DSL_SIGNAL_PATH') -and $saved -notmatch 'gk-verified-signal-path') { throw "Signalweg nicht gespeichert: $id" }
    $status = 'UPDATED_AND_VERIFIED'
  }
  $rows += [pscustomobject]@{ id=$id; title=$title; status=$status; reasons=($reasons -join ',') }
  Write-Host ("$id $status")
}

if ($Mode -eq 'Apply' -and $rows.Count) {
  $cache = Invoke-RestMethod ($site + '/wp-json/gk-unified-api/v1/clear-cache') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('{}'))
  if ($cache.cache_cleared -ne $true) { throw 'Cache nicht geleert.' }
}
$rows | Export-Csv (Join-Path $reportDir ("frontend-fix-$Mode-$stamp.csv")) -NoTypeInformation -Encoding UTF8
Write-Host ("FERTIG: Modus=$Mode | Aktualisiert=$($rows.Count)")
