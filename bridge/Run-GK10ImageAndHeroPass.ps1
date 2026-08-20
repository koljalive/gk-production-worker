Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PlainSecret([string]$Path) {
  $s = Get-Content $Path | ConvertTo-SecureString
  $p = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($p) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p) }
}

function Invoke-WpJson([string]$Method,[string]$Path,[hashtable]$Headers,[object]$Body=$null) {
  $url = 'https://glasfaser-kompass.de/wp-json' + $Path
  $p = @{ Uri=$url; Method=$Method; Headers=$Headers; UseBasicParsing=$true; TimeoutSec=180 }
  if ($null -ne $Body) {
    $json = $Body | ConvertTo-Json -Depth 50 -Compress
    $p.Body = [Text.Encoding]::UTF8.GetBytes($json)
    $p.ContentType = 'application/json; charset=utf-8'
  }
  $r = Invoke-WebRequest @p
  if ([string]::IsNullOrWhiteSpace([string]$r.Content)) { return $null }
  return ([string]$r.Content | ConvertFrom-Json)
}

function Find-MediaByFilename([string]$Search,[string]$FilenamePart,[hashtable]$Headers) {
  $q = [Uri]::EscapeDataString($Search)
  $items = @(Invoke-WpJson 'GET' ("/wp/v2/media?context=edit&per_page=100&search=$q&_fields=id,title,source_url,alt_text,mime_type") $Headers)
  return ($items | Where-Object { ([string]$_.source_url).Contains($FilenamePart) } | Select-Object -First 1)
}

function Backup-Object([int]$PageId,[object]$Object) {
  $dir = 'C:\GKBridge\backups\gk10'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $path = Join-Path $dir ("page-$PageId-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-before.json')
  [IO.File]::WriteAllText($path, ($Object | ConvertTo-Json -Depth 50), (New-Object Text.UTF8Encoding($false)))
  return $path
}

function Replace-HeroImage([string]$Html,[string]$NewSrc,[string]$NewAlt,[ref]$OldSrcRef) {
  # Only touch the first explicitly editorial/hero figure. Leave technical diagrams elsewhere intact.
  $pattern = '(?is)(<figure[^>]*class="[^"]*(?:gkpr-hero-media|gk-editorial-illustration)[^"]*"[^>]*>.*?<img\s+[^>]*src=")([^"]+)("[^>]*)(alt=")([^"]*)("[^>]*>.*?</figure>)'
  $m = [regex]::Match($Html,$pattern)
  if (-not $m.Success) { return $Html }
  $oldSrc = $m.Groups[2].Value
  # Replace only generated/schematic hero images; do not overwrite a real photograph.
  if ($oldSrc -notmatch '(?i)(\.svg(?:\?|$)|/exec-|diagram|schema|signalweg|illustr|bauformen|collage)') { return $Html }
  $OldSrcRef.Value = $oldSrc
  $replacement = $m.Groups[1].Value + $NewSrc + $m.Groups[3].Value + $m.Groups[4].Value + $NewAlt + $m.Groups[6].Value
  return $Html.Substring(0,$m.Index) + $replacement + $Html.Substring($m.Index + $m.Length)
}

$secretDir = Join-Path $env:APPDATA 'GK-MCP-Tunnel'
$user = (Get-Content (Join-Path $secretDir 'wp-user.txt') -Raw).Trim()
$pass = Get-PlainSecret (Join-Path $secretDir 'wp-password.dat')
try { $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$user`:$pass")) }
finally { Remove-Variable pass -ErrorAction SilentlyContinue }
$headers = @{ Authorization="Basic $basic"; Accept='application/json' }
Remove-Variable basic -ErrorAction SilentlyContinue

$router = Find-MediaByFilename 'FRITZ' 'fritzbox-7590-reales-routerfoto' $headers
$ftth   = Find-MediaByFilename 'FTTH' 'ftth-abschluss-reales-foto' $headers
$wifi   = Find-MediaByFilename 'WLAN' 'wlan-access-point-reales-foto' $headers
$splice = Find-MediaByFilename 'Spleiss' 'glasfaser-spleissmuffe-reales-foto' $headers

if (-not $router) { throw 'Real router photograph not found.' }
if (-not $ftth)   { throw 'Real FTTH photograph not found.' }
if (-not $wifi)   { throw 'Real WLAN photograph not found.' }
if (-not $splice) { throw 'Real fiber splice photograph not found.' }

$targets = @(
  @{ id=21004; media=$ftth;   alt='Realer FTTH-Glasfaserabschluss an einer Wand'; url='https://glasfaser-kompass.de/glasfaser/' },
  @{ id=21006; media=$router; alt='Echte FRITZ!Box mit sichtbaren Netzwerk- und Anschlussports'; url='https://glasfaser-kompass.de/router/' },
  @{ id=21007; media=$wifi;   alt='Realer WLAN Access Point an einer Wand'; url='https://glasfaser-kompass.de/wlan-heimnetz/' },
  @{ id=21021; media=$wifi;   alt='Realer WLAN Access Point an einer Wand'; url='https://glasfaser-kompass.de/wlan-kaufberatung/' },
  @{ id=21041; media=$wifi;   alt='Realer WLAN Access Point an einer Wand'; url='https://glasfaser-kompass.de/wlan-repeater-kaufberatung-2026/' },
  @{ id=21043; media=$wifi;   alt='Realer WLAN Access Point an einer Wand'; url='https://glasfaser-kompass.de/mesh-system-kaufberatung-2026/' },
  @{ id=21022; media=$ftth;   alt='Realer FTTH-Glasfaserabschluss an einer Wand'; url='https://glasfaser-kompass.de/glasfaser-hardware/' },
  @{ id=21967; media=$splice; alt='Geöffnete reale Glasfaser-Spleißmuffe mit sichtbaren Glasfasern'; url='https://glasfaser-kompass.de/telekom-readiness/' }
)

$changes = @()
foreach ($t in $targets) {
  $before = Invoke-WpJson 'GET' ("/wp/v2/pages/$($t.id)?context=edit&_fields=id,modified,status,link,title,featured_media,content") $headers
  if (-not $before) { continue }
  $backup = Backup-Object $t.id $before
  $raw = [string]$before.content.raw
  $oldHero = $null
  $newRaw = Replace-HeroImage $raw ([string]$t.media.source_url) ([string]$t.alt) ([ref]$oldHero)
  $payload = [ordered]@{ featured_media=[int]$t.media.id }
  if ($newRaw -ne $raw) { $payload.content = $newRaw }
  Invoke-WpJson 'POST' ("/wp/v2/pages/$($t.id)") $headers $payload | Out-Null
  $after = Invoke-WpJson 'GET' ("/wp/v2/pages/$($t.id)?context=edit&_fields=id,modified,status,link,title,featured_media,content") $headers
  if ([int]$after.featured_media -ne [int]$t.media.id) { throw "Featured image verification failed on $($t.id)" }
  if ($oldHero -and ([string]$after.content.raw).Contains($oldHero)) { throw "Hero image verification failed on $($t.id)" }
  $changes += [ordered]@{
    id=$t.id; title=[string]$after.title.raw; url=[string]$after.link;
    old_featured=[int]$before.featured_media; new_featured=[int]$after.featured_media;
    old_hero=$oldHero; new_photo=[string]$t.media.source_url;
    content_changed=($newRaw -ne $raw); backup=$backup; verified=$true
  }
}

# Verify what visitors actually receive, cache-busted.
$public = @()
$stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
foreach ($c in $changes) {
  try {
    $sep = if ($c.url.Contains('?')) {'&'} else {'?'}
    $r = Invoke-WebRequest -Uri ($c.url + $sep + 'gk10img=' + $stamp) -UseBasicParsing -TimeoutSec 120
    $html = [string]$r.Content
    $public += [ordered]@{
      id=$c.id; url=$c.url; status=[int]$r.StatusCode;
      new_photo_visible=$html.Contains($c.new_photo);
      old_hero_still_visible=([bool]$c.old_hero -and $html.Contains([string]$c.old_hero))
    }
  } catch {
    $public += [ordered]@{ id=$c.id; url=$c.url; status=0; error=$_.Exception.Message }
  }
}

$out = [ordered]@{
  generated_at_utc=(Get-Date).ToUniversalTime().ToString('o');
  success=$true;
  media=[ordered]@{router=$router;ftth=$ftth;wifi=$wifi;splice=$splice};
  changes=$changes;
  public=$public
}
$outPath = Join-Path $env:GITHUB_WORKSPACE 'bridge/gk10-image-hero-result.json'
[IO.File]::WriteAllText($outPath, ($out | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding($false)))
Write-Host "GK10 image/hero pass complete: $($changes.Count) pages verified."
