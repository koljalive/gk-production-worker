param(
  [ValidateSet('Inspect','Apply')][string]$Mode = 'Inspect',
  [string]$SiteUrl = $env:GK_SITE_URL,
  [string]$Username = $env:WP_USERNAME,
  [string]$ApplicationPassword = $env:WP_APPLICATION_PASSWORD
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SiteUrl) -or [string]::IsNullOrWhiteSpace($Username) -or [string]::IsNullOrWhiteSpace($ApplicationPassword)) { throw 'GK_SITE_URL, WP_USERNAME oder WP_APPLICATION_PASSWORD fehlt.' }
$site = $SiteUrl.TrimEnd('/')
$pair = '{0}:{1}' -f $Username,$ApplicationPassword
$basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
$headers = @{ Authorization = 'Basic ' + $basic }
$reportDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'reports'
New-Item $reportDir -ItemType Directory -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Get-PublicSnapshot {
  $url = $site + '/dsl-bauteile-im-haus/?gk_probe=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $response = Invoke-WebRequest $url -UseBasicParsing -Headers @{'Cache-Control'='no-cache'} -TimeoutSec 60
  $html = [string]$response.Content
  [pscustomobject]@{
    Status = [int]$response.StatusCode
    Gk9Author = [regex]::Matches($html,'(?i)class=["''][^"'']*gk9-authorbox').Count
    Gk9Affiliate = [regex]::Matches($html,'(?i)class=["''][^"'']*gk9-tarifcheck').Count
    GkprAuthor = [regex]::Matches($html,'(?i)class=["''][^"'']*gkpr-author').Count
    GkprAffiliate = [regex]::Matches($html,'(?i)class=["''][^"'']*gkpr-affiliate').Count
  }
}
function Set-PluginStatus([string]$plugin,[string]$status) {
  $encoded = [uri]::EscapeDataString($plugin)
  $payload = @{ status = $status } | ConvertTo-Json -Compress
  Invoke-RestMethod ($site + '/wp-json/wp/v2/plugins/' + $encoded) -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($payload)) -TimeoutSec 60
}
function Clear-GkCache {
  if (-not [string]::IsNullOrWhiteSpace($env:GK_UNIFIED_API_TOKEN)) {
    try {
      Invoke-RestMethod ($site + '/wp-json/gk-unified-api/v1/clear-cache') -Method Post -Headers @{Authorization='Bearer '+$env:GK_UNIFIED_API_TOKEN} -ContentType 'application/json' -Body '{}' -TimeoutSec 30 | Out-Null
    } catch { Write-Host ('Cache-Hinweis: ' + $_.Exception.Message) }
  }
}
$plugins = @(Invoke-RestMethod ($site + '/wp-json/wp/v2/plugins?context=edit&per_page=100') -Headers $headers -TimeoutSec 60)
$pluginRows = foreach($p in $plugins) {
  [pscustomobject]@{ Plugin=[string]$p.plugin; Name=[string]$p.name; Status=[string]$p.status; Description=([string]$p.description.raw) }
}
$pluginRows | Export-Csv (Join-Path $reportDir "wordpress-plugins-$stamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host ('PLUGIN_ACCESS=OK | PLUGINS=' + $pluginRows.Count)
$baseline = Get-PublicSnapshot
Write-Host ('BASELINE=' + ($baseline | ConvertTo-Json -Compress))

if ($Mode -eq 'Inspect') {
  $pluginRows | Where-Object { $_.Status -eq 'active' -and (($_.Plugin+' '+$_.Name+' '+$_.Description) -match '(?i)(gk|glasfaser|author|affiliate|production|render|template)') } | ForEach-Object { Write-Host ('CANDIDATE=' + ($_ | ConvertTo-Json -Compress)) }
  exit 0
}

$excluded = '(?i)(unified|control|site.?audit|wordfence|security|backup|cache|seo|woocommerce)'
$candidates = @($pluginRows | Where-Object {
  $_.Status -eq 'active' -and
  (($_.Plugin+' '+$_.Name+' '+$_.Description) -match '(?i)(gk|glasfaser|author|affiliate|production|render|template)') -and
  (($_.Plugin+' '+$_.Name) -notmatch $excluded)
})
if ($candidates.Count -eq 0) { throw 'Keine sicher eingrenzbare aktive Kandidaten-Erweiterung gefunden.' }

$results = New-Object System.Collections.Generic.List[object]
$kept = $false
foreach($candidate in $candidates) {
  Write-Host ('TEST_DEACTIVATE=' + $candidate.Plugin + ' | ' + $candidate.Name)
  Set-PluginStatus $candidate.Plugin 'inactive' | Out-Null
  Clear-GkCache
  Start-Sleep -Seconds 3
  try {
    $after = Get-PublicSnapshot
    $beforeGkpr = $baseline.GkprAuthor + $baseline.GkprAffiliate
    $afterGkpr = $after.GkprAuthor + $after.GkprAffiliate
    $afterGk9 = $after.Gk9Author + $after.Gk9Affiliate
    $accept = ($after.Status -eq 200 -and $afterGkpr -lt $beforeGkpr -and $afterGk9 -ge 2)
    $results.Add([pscustomobject]@{Plugin=$candidate.Plugin;Name=$candidate.Name;BeforeGkpr=$beforeGkpr;AfterGkpr=$afterGkpr;AfterGk9=$afterGk9;Accepted=$accept})
    if ($accept) {
      Write-Host ('KEPT_INACTIVE=' + $candidate.Plugin)
      $baseline = $after
      $kept = $true
      break
    }
  } finally {
    if (-not $kept) {
      Set-PluginStatus $candidate.Plugin 'active' | Out-Null
      Clear-GkCache
      Start-Sleep -Seconds 2
      Write-Host ('REACTIVATED=' + $candidate.Plugin)
    }
  }
}
$results | Export-Csv (Join-Path $reportDir "dynamic-plugin-test-$stamp.csv") -NoTypeInformation -Encoding UTF8
if (-not $kept) { throw 'Kein Kandidat entfernte ausschließlich die dynamischen Doppelblöcke; alle getesteten Plugins wurden reaktiviert.' }
$final = Get-PublicSnapshot
if ($final.Status -ne 200 -or ($final.GkprAuthor+$final.GkprAffiliate) -ne 0 -or ($final.Gk9Author+$final.Gk9Affiliate) -lt 2) { throw ('Öffentliche Abschlussprüfung fehlgeschlagen: '+($final|ConvertTo-Json -Compress)) }
Write-Host ('FERTIG=' + ($final | ConvertTo-Json -Compress))
