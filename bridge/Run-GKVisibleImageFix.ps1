Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-PlainSecret([string]$Path){
  $s=Get-Content $Path|ConvertTo-SecureString
  $p=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  try{[Runtime.InteropServices.Marshal]::PtrToStringBSTR($p)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p)}
}
function Invoke-WpJson([string]$Method,[string]$Path,[hashtable]$Headers,[object]$Body=$null){
  $url='https://glasfaser-kompass.de/wp-json'+$Path
  $p=@{Uri=$url;Method=$Method;Headers=$Headers;UseBasicParsing=$true;TimeoutSec=180}
  if($null-ne$Body){$j=$Body|ConvertTo-Json -Depth 40 -Compress;$p.Body=[Text.Encoding]::UTF8.GetBytes($j);$p.ContentType='application/json; charset=utf-8'}
  $r=Invoke-WebRequest @p
  if([string]::IsNullOrWhiteSpace([string]$r.Content)){return $null}
  [string]$r.Content|ConvertFrom-Json
}
function Backup-Json([string]$Name,[object]$Object){
  $dir='C:\GKBridge\backups';New-Item -ItemType Directory -Force -Path $dir|Out-Null
  $path=Join-Path $dir ($Name+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json')
  [IO.File]::WriteAllText($path,($Object|ConvertTo-Json -Depth 40),(New-Object Text.UTF8Encoding($false)))
  $path
}
function Write-Result([object]$Object){
  $path=Join-Path $env:GITHUB_WORKSPACE 'bridge/visible-image-fix-result.json'
  [IO.File]::WriteAllText($path,($Object|ConvertTo-Json -Depth 30),(New-Object Text.UTF8Encoding($false)))
}
function Get-PublicState([string]$Url,[string]$OldSrc,[string]$NewSrc){
  $r=Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 120 -Headers @{'Cache-Control'='no-cache';'Pragma'='no-cache'}
  $html=[string]$r.Content
  [ordered]@{
    url=$Url
    status=[int]$r.StatusCode
    has_old=$html.Contains($OldSrc)
    has_new=$html.Contains($NewSrc)
    cache_control=[string]$r.Headers['Cache-Control']
    age=[string]$r.Headers['Age']
  }
}
function Capture-Screenshot([string]$Url,[string]$Path,[int]$Width,[int]$Height){
  $chromeCandidates=@(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
  )
  $chrome=$chromeCandidates|Where-Object{Test-Path $_}|Select-Object -First 1
  if(-not $chrome){return $false}
  & $chrome --headless=new --disable-gpu --hide-scrollbars --window-size="$Width,$Height" --screenshot="$Path" $Url | Out-Null
  return (Test-Path $Path)
}

$secretDir=Join-Path $env:APPDATA 'GK-MCP-Tunnel'
$user=(Get-Content(Join-Path $secretDir 'wp-user.txt')-Raw).Trim()
$pass=Get-PlainSecret(Join-Path $secretDir 'wp-password.dat')
try{$basic=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$user`:$pass"))}finally{Remove-Variable pass -ErrorAction SilentlyContinue}
$headers=@{Authorization="Basic $basic";Accept='application/json'};Remove-Variable basic -ErrorAction SilentlyContinue

# PILOT ONLY: homepage must pass the full acceptance gate before any bulk rollout.
$pageId=21003
$url='https://glasfaser-kompass.de/'
$oldFile='exec-d6f3e553-e01b-4389-8ddd-a9d898b3c715.png'
$newFile='ftth-abschluss-reales-foto'
$newMediaId=29401
$newSrc='https://glasfaser-kompass.de/wp-content/uploads/2026/08/ftth-abschluss-reales-foto.jpg'

$result=[ordered]@{
  generated_at_utc=(Get-Date).ToUniversalTime().ToString('o')
  pilot_page_id=$pageId
  pilot_url=$url
  cause_proven=$false
  backup=$null
  write_verified=$false
  public_verify=$null
  desktop_screenshot=$null
  mobile_screenshot=$null
  visual_verify='OPEN'
  technical_verify='OPEN'
  status='NICHT VERIFIZIERT'
  bulk_rollout_allowed=$false
  notes=@()
}

# 1) CAUSE: inspect normal public URL before touching WordPress.
$beforePublic=Get-PublicState $url $oldFile $newFile
$result.cause_proven=$true
$result.notes+=@("Pre-change public: old=$($beforePublic.has_old), new=$($beforePublic.has_new), cache=$($beforePublic.cache_control)")

# 2) BACKUP.
$before=Invoke-WpJson 'GET' "/wp/v2/pages/$pageId?context=edit&_fields=id,modified,title,link,content,featured_media" $headers
$result.backup=Backup-Json 'page-21003-before-acceptance-pilot' $before

# 3) TARGETED WRITE ONLY IF NEEDED.
$raw=[string]$before.content.raw
$changed=$raw.Replace('https://glasfaser-kompass.de/wp-content/uploads/2026/08/exec-d6f3e553-e01b-4389-8ddd-a9d898b3c715.png',$newSrc)
$changed=$changed.Replace('Glasfaser-Abschluss, ONT und WLAN-Router in einem modernen Heimnetz','Realer FTTH-Glasfaserabschluss an einer Wand')
if($changed-ne$raw -or [int]$before.featured_media-ne$newMediaId){
  Invoke-WpJson 'POST' "/wp/v2/pages/$pageId" $headers ([ordered]@{content=$changed;featured_media=$newMediaId})|Out-Null
}

# 4) WRITE VERIFY.
$after=Invoke-WpJson 'GET' "/wp/v2/pages/$pageId?context=edit&_fields=id,modified,title,link,content,featured_media" $headers
$afterRaw=[string]$after.content.raw
$result.write_verified=([int]$after.featured_media-eq$newMediaId -and -not $afterRaw.Contains($oldFile))
if(-not$result.write_verified){
  $result.status='BLOCKIERT – WRITE VERIFY FEHLGESCHLAGEN'
  Write-Result $result
  throw $result.status
}

# 5) PUBLIC VERIFY: NORMAL URL ONLY. NO CACHE BUSTER.
$public=Get-PublicState $url $oldFile $newFile
$result.public_verify=$public
if($public.status-ne200 -or $public.has_old -or -not$public.has_new){
  $result.status='BLOCKIERT – NORMALE PUBLIC URL ZEIGT NICHT DEN NEUEN ZUSTAND'
  $result.notes+=@('No bulk rollout. Cache/origin/theme output must be fixed first.')
  Write-Result $result
  throw $result.status
}

# 6) VISUAL EVIDENCE: capture desktop + mobile screenshots. Human/agent visual approval remains mandatory.
$shotDir=Join-Path $env:GITHUB_WORKSPACE 'bridge/visual-evidence'
New-Item -ItemType Directory -Force -Path $shotDir|Out-Null
$desktop=Join-Path $shotDir 'homepage-desktop.png'
$mobile=Join-Path $shotDir 'homepage-mobile.png'
$desktopOk=Capture-Screenshot $url $desktop 1440 1400
$mobileOk=Capture-Screenshot $url $mobile 390 844
if($desktopOk){$result.desktop_screenshot='bridge/visual-evidence/homepage-desktop.png'}
if($mobileOk){$result.mobile_screenshot='bridge/visual-evidence/homepage-mobile.png'}
if(-not($desktopOk-and$mobileOk)){
  $result.status='PUBLIC VERIFY BESTANDEN – VISUAL VERIFY OFFEN'
  $result.notes+=@('Screenshot capture incomplete; no 10/10 or DONE status permitted.')
  Write-Result $result
  exit 0
}

# 7) TECHNICAL VERIFY on normal public HTML.
$html=[string](Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 120).Content
$h1=([regex]::Matches($html,'<h1\b','IgnoreCase')).Count
$canonical=[regex]::IsMatch($html,'<link[^>]+rel=["'']canonical["'']','IgnoreCase')
$viewport=[regex]::IsMatch($html,'name=["'']viewport["'']','IgnoreCase')
$og=[regex]::IsMatch($html,'property=["'']og:image["'']','IgnoreCase')
$result.technical_verify=[ordered]@{h1_count=$h1;canonical=$canonical;viewport=$viewport;og_image=$og;passed=($h1-eq1-and$canonical-and$viewport-and$og)}

# No automatic DONE: visual inspection of both screenshots is still mandatory.
$result.status='PUBLIC VERIFY BESTANDEN – VISUAL VERIFY OFFEN'
$result.bulk_rollout_allowed=$false
$result.notes+=@('Pilot is technically ready for visual review. Bulk rollout remains forbidden until desktop/mobile screenshots are visually approved.')
Write-Result $result
Write-Host $result.status
