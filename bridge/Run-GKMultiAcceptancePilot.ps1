Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-PlainSecret([string]$Path){
  $s=Get-Content $Path|ConvertTo-SecureString
  $p=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  try{return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($p)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p)}
}
function Invoke-Wp([string]$Method,[string]$Path,[hashtable]$Headers,[object]$Body=$null){
  $u='https://glasfaser-kompass.de/wp-json'+$Path
  $p=@{Uri=$u;Method=$Method;Headers=$Headers;UseBasicParsing=$true;TimeoutSec=180}
  if($null -ne $Body){$j=$Body|ConvertTo-Json -Depth 40 -Compress;$p.Body=[Text.Encoding]::UTF8.GetBytes($j);$p.ContentType='application/json; charset=utf-8'}
  $r=Invoke-WebRequest @p
  if([string]::IsNullOrWhiteSpace([string]$r.Content)){return $null}
  return ([string]$r.Content|ConvertFrom-Json)
}
function Is-Schematic([string]$Url){return $Url -match 'exec-|diagram|schema|signalweg|illustr|infograf|bauformen|collage|skizze|\.svg(?:\?|$)'}
function Get-Category([string]$Text){
  $t=$Text.ToLowerInvariant()
  if($t -match 'wlan|wi-fi|wifi|mesh|repeater|access point|homeoffice'){return 'wifi'}
  if($t -match 'router|fritz|speedport'){return 'router'}
  if($t -match 'glasfaser|gf-ap|gf-ta|gfta|ont|ftth|fiber|spleiss|spleiß'){return 'fiber'}
  if($t -match 'techniker|telekom|apl|tae|dsl|kupfer|leitung|störung|montage|installation'){return 'field'}
  return $null
}
function Get-MediaId([string]$Category){
  switch($Category){'wifi'{return 29403};'router'{return 29397};'fiber'{return 29401};'field'{return 29398};default{return 0}}
}
function Replace-SchematicImages([string]$Raw,[string]$ReplacementUrl,[string]$Alt,[ref]$Count){
  $Count.Value=0
  $rx=[regex]::new('<img\b[^>]*>','IgnoreCase')
  return $rx.Replace($Raw,{
    param($m)
    $tag=$m.Value
    $srcM=[regex]::Match($tag,'\bsrc=["'']([^"'']+)["'']','IgnoreCase')
    if((-not $srcM.Success) -or (-not (Is-Schematic $srcM.Groups[1].Value))){return $tag}
    $Count.Value++
    $x=[regex]::Replace($tag,'\bsrc=["''][^"'']+["'']',('src="'+$ReplacementUrl+'"'),'IgnoreCase')
    $x=[regex]::Replace($x,'\s+srcset=["''][^"'']*["'']','','IgnoreCase')
    $x=[regex]::Replace($x,'\s+sizes=["''][^"'']*["'']','','IgnoreCase')
    if([regex]::IsMatch($x,'\balt=["''][^"'']*["'']','IgnoreCase')){$x=[regex]::Replace($x,'\balt=["''][^"'']*["'']',('alt="'+[System.Net.WebUtility]::HtmlEncode($Alt)+'"'),'IgnoreCase')}
    else{$x=$x -replace '>$',(' alt="'+[System.Net.WebUtility]::HtmlEncode($Alt)+'">')}
    return $x
  })
}
function Probe([string]$Url,[string]$ExpectedImage=''){
  try{
    $r=Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 120
    $h=[string]$r.Content
    $h1=([regex]::Matches($h,'<h1\b','IgnoreCase')).Count
    $schematic=0
    foreach($m in [regex]::Matches($h,'<img\b[^>]*>','IgnoreCase')){
      $s=[regex]::Match($m.Value,'\bsrc=["'']([^"'']+)["'']','IgnoreCase')
      if($s.Success -and (Is-Schematic $s.Groups[1].Value)){$schematic++}
    }
    return [pscustomobject]@{ok=$true;http=[int]$r.StatusCode;h1=$h1;schematic=$schematic;expected_image=([string]::IsNullOrWhiteSpace($ExpectedImage) -or $h.Contains($ExpectedImage))}
  }catch{return [pscustomobject]@{ok=$false;http=$null;h1=$null;schematic=$null;expected_image=$false;error=$_.Exception.Message}}
}
function Purge([string]$Url){try{Invoke-WebRequest -Uri $Url -Method PURGE -UseBasicParsing -TimeoutSec 60|Out-Null}catch{}}
function Wait-Probe([string]$Url,[string]$ExpectedImage){
  $last=$null
  for($i=0;$i -lt 16;$i++){
    $last=Probe $Url $ExpectedImage
    if($last.ok -and $last.http -eq 200 -and $last.h1 -eq 1 -and $last.schematic -eq 0 -and $last.expected_image){return $last}
    Start-Sleep -Seconds 10
  }
  return $last
}
function Find-Chrome(){
  $c=@("$env:ProgramFiles\Google\Chrome\Application\chrome.exe","${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe","$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")
  foreach($x in $c){if($x -and (Test-Path $x)){return $x}}
  return $null
}

$workspace=$env:GITHUB_WORKSPACE
$auditPath=Join-Path $workspace 'bridge/gk10-full-result.json'
if(-not (Test-Path $auditPath)){throw 'Missing gk10-full-result.json'}
$audit=(Get-Content $auditPath -Raw)|ConvertFrom-Json
$candidates=@($audit.results|Where-Object{$_.score -lt 10 -and (($_.issues -contains 'h1_count_2') -or ([int]$_.suspicious_images -gt 0))})
if($candidates.Count -lt 1){throw 'No pilot candidates found in full audit.'}

$secretDir=Join-Path $env:APPDATA 'GK-MCP-Tunnel'
$user=(Get-Content (Join-Path $secretDir 'wp-user.txt') -Raw).Trim()
$pass=Get-PlainSecret (Join-Path $secretDir 'wp-password.dat')
try{$basic=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$user`:$pass"))}finally{Remove-Variable pass -ErrorAction SilentlyContinue}
$headers=@{Authorization="Basic $basic";Accept='application/json'}
Remove-Variable basic -ErrorAction SilentlyContinue

$media=@{}
foreach($mid in 29397,29398,29401,29403){$media[$mid]=Invoke-Wp 'GET' "/wp/v2/media/$($mid)?context=edit&_fields=id,title,source_url,alt_text,mime_type" $headers}
$chrome=Find-Chrome
if(-not $chrome){throw 'Chrome not found; visual acceptance evidence is mandatory.'}

$result=[ordered]@{started_utc=(Get-Date).ToUniversalTime().ToString('o');pilot_size=8;gate_version='multi-editorial-v2-live-state';selected=0;changed=0;verified=0;blocked=0;stale_skipped=0;items=@();screenshots=@();finished_utc=$null}
$backupDir='C:\GKBridge\backups';New-Item -ItemType Directory -Force -Path $backupDir|Out-Null

foreach($t in $candidates){
  if($result.selected -ge 8){break}
  $type=if([string]$t.type -eq 'page'){'pages'}else{'posts'}
  $id=[int]$t.id
  $o=Invoke-Wp 'GET' "/wp/v2/$type/$($id)?context=edit&_fields=id,modified,slug,link,title,featured_media,content" $headers
  if($null -eq $o){$result.blocked++;continue}

  # Critical: stale audit findings are never treated as live truth. Re-probe the public URL first.
  $pre=Probe ([string]$o.link)
  if(-not $pre.ok -or $pre.http -ne 200){$result.blocked++;continue}
  if($pre.h1 -eq 1 -and $pre.schematic -eq 0){$result.stale_skipped++;continue}
  if($pre.h1 -lt 1 -or $pre.h1 -gt 2){$result.blocked++;continue}

  $raw=[string]$o.content.raw
  $title=[string]$o.title.raw
  $text="$title $([string]$o.slug) $raw"
  $needsH1=($pre.h1 -eq 2)
  $needsImage=([int]$pre.schematic -gt 0)
  $cat=Get-Category $text
  if($needsImage -and [string]::IsNullOrWhiteSpace([string]$cat)){$result.blocked++;continue}
  $mid=if($needsImage){Get-MediaId $cat}else{0}
  if($needsImage -and $mid -eq 0){$result.blocked++;continue}
  $photo=if($needsImage){$media[$mid]}else{$null}
  if($needsImage -and ($null -eq $photo -or ([string]$photo.mime_type) -notmatch '^image/' -or [string]::IsNullOrWhiteSpace([string]$photo.source_url) -or (Is-Schematic ([string]$photo.source_url)))){$result.blocked++;continue}

  $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
  $backupPath=Join-Path $backupDir "$type-$id-$stamp-multipilot-before.json"
  [IO.File]::WriteAllText($backupPath,($o|ConvertTo-Json -Depth 30),(New-Object Text.UTF8Encoding($false)))

  $new=$raw;$h1Changed=$false;$imgChanged=0;$expected=''
  if($needsH1){
    $before=$new
    $new=[regex]::Replace($new,'<h1\b([^>]*)>','<h2$1>','IgnoreCase')
    $new=[regex]::Replace($new,'</h1\s*>','</h2>','IgnoreCase')
    $h1Changed=($new -ne $before)
    if(-not $h1Changed){$result.blocked++;continue}
  }
  if($needsImage){
    $expected=[string]$photo.source_url
    $alt=if([string]::IsNullOrWhiteSpace([string]$photo.alt_text)){"Reales Foto passend zu $title"}else{[string]$photo.alt_text}
    $cnt=0
    $new=Replace-SchematicImages $new $expected $alt ([ref]$cnt)
    $imgChanged=$cnt
    if($imgChanged -lt 1){$result.blocked++;continue}
  }

  # Only now count the target as selected: every selected target is actually actionable and backed up.
  $result.selected++
  $body=[ordered]@{}
  if($new -ne $raw){$body.content=$new}
  if($needsImage -and [int]$o.featured_media -ne $mid){$body.featured_media=$mid}
  if($body.Count -lt 1){$result.blocked++;$result.selected--;continue}
  Invoke-Wp 'POST' "/wp/v2/$type/$($id)" $headers $body|Out-Null
  $result.changed++

  Purge ([string]$o.link)
  $probe=Wait-Probe ([string]$o.link) $expected
  $ok=($probe.ok -and $probe.http -eq 200 -and $probe.h1 -eq 1 -and $probe.schematic -eq 0 -and $probe.expected_image)
  if(-not $ok){throw "Public acceptance failed for target $id."}
  $result.verified++

  $safeName="pilot-$id"
  $desktop=Join-Path $workspace ("bridge/$safeName-desktop.png")
  $mobile=Join-Path $workspace ("bridge/$safeName-mobile.png")
  & $chrome --headless=new --disable-gpu --hide-scrollbars --window-size=1440,1200 --screenshot=$desktop ([string]$o.link)|Out-Null
  & $chrome --headless=new --disable-gpu --hide-scrollbars --window-size=390,844 --screenshot=$mobile ([string]$o.link)|Out-Null
  if((-not (Test-Path $desktop)) -or (-not (Test-Path $mobile))){throw "Screenshot evidence missing for target $id."}
  $result.screenshots+=@([ordered]@{id=$id;viewport='desktop';path=(Split-Path $desktop -Leaf)},[ordered]@{id=$id;viewport='mobile';path=(Split-Path $mobile -Leaf)})
  $result.items+=@([ordered]@{id=$id;type=$type;title=$title;url=[string]$o.link;category=$cat;backup=$backupPath;pre_probe=$pre;h1_changed=$h1Changed;images_replaced=$imgChanged;media_id=$mid;expected_image=$expected;probe=$probe;accepted=$true})
}
if($result.selected -lt 8){throw "Only $($result.selected) live-actionable safe pilot targets found; required 8. stale_skipped=$($result.stale_skipped) blocked=$($result.blocked)"}
if($result.verified -ne 8){throw "Only $($result.verified) of 8 pilot targets verified."}
if($result.screenshots.Count -ne 16){throw "Screenshot evidence incomplete: $($result.screenshots.Count) of 16."}
$result.finished_utc=(Get-Date).ToUniversalTime().ToString('o')
[IO.File]::WriteAllText((Join-Path $workspace 'bridge/multi-acceptance-pilot-result.json'),($result|ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
Write-Host "Multi acceptance pilot complete: selected=$($result.selected) changed=$($result.changed) verified=$($result.verified) stale_skipped=$($result.stale_skipped) blocked=$($result.blocked) screenshots=$($result.screenshots.Count)"