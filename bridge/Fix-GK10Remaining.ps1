Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-PlainSecret([string]$Path){
  $s=Get-Content $Path|ConvertTo-SecureString
  $p=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  try{[Runtime.InteropServices.Marshal]::PtrToStringBSTR($p)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p)}
}
function Invoke-Wp([string]$Method,[string]$Path,[hashtable]$Headers,[object]$Body=$null){
  $u='https://glasfaser-kompass.de/wp-json'+$Path
  $p=@{Uri=$u;Method=$Method;Headers=$Headers;UseBasicParsing=$true;TimeoutSec=180}
  if($null-ne $Body){$json=$Body|ConvertTo-Json -Depth 30 -Compress;$p.Body=[Text.Encoding]::UTF8.GetBytes($json);$p.ContentType='application/json; charset=utf-8'}
  try{$r=Invoke-WebRequest @p;[pscustomobject]@{ok=$true;status=[int]$r.StatusCode;body=[string]$r.Content}}
  catch{$b='';$s=$null;if($_.Exception.Response){try{$s=[int]$_.Exception.Response.StatusCode}catch{};try{$rd=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream());$b=$rd.ReadToEnd();$rd.Close()}catch{}};[pscustomobject]@{ok=$false;status=$s;body=$b;error=$_.Exception.Message}}
}
function Get-PhotoMediaId([string]$Text){
  $t=$Text.ToLowerInvariant()
  if($t -match 'wlan|wi-fi|wifi|mesh|repeater|access point|homeoffice'){return 29403}
  if($t -match 'router|fritz|speedport'){return 29397}
  if($t -match 'techniker|telekom|apl|tae|dsl|kupfer|leitung|störung'){return 29398}
  if($t -match 'glasfaser|gf-ap|gf-ta|ont|ftth|fiber'){return 29401}
  return 29401
}
function Is-SuspiciousUrl([string]$Url){return $Url -match 'exec-|diagram|schema|signalweg|illustr|infograf|bauformen|collage|skizze|\.svg(?:\?|$)'}
function Replace-SuspiciousImages([string]$Raw,[string]$ReplacementUrl,[string]$Alt,[ref]$Count){
  $Count.Value=0
  $rx=[regex]::new('<img\b[^>]*>','IgnoreCase')
  return $rx.Replace($Raw,{param($m)
    $tag=$m.Value
    $srcM=[regex]::Match($tag,'\bsrc=["'']([^"'']+)["'']','IgnoreCase')
    if(-not $srcM.Success -or -not (Is-SuspiciousUrl $srcM.Groups[1].Value)){return $tag}
    $Count.Value++
    $new=$tag
    if([regex]::IsMatch($new,'\bsrc=["''][^"'']+["'']','IgnoreCase')){$new=[regex]::Replace($new,'\bsrc=["''][^"'']+["'']',('src="'+$ReplacementUrl+'"'),'IgnoreCase')}
    $new=[regex]::Replace($new,'\s+srcset=["''][^"'']*["'']','','IgnoreCase')
    $new=[regex]::Replace($new,'\s+sizes=["''][^"'']*["'']','','IgnoreCase')
    if([regex]::IsMatch($new,'\balt=["''][^"'']*["'']','IgnoreCase')){$new=[regex]::Replace($new,'\balt=["''][^"'']*["'']',('alt="'+[System.Net.WebUtility]::HtmlEncode($Alt)+'"'),'IgnoreCase')}
    else{$new=$new -replace '>$',(' alt="'+[System.Net.WebUtility]::HtmlEncode($Alt)+'">')}
    return $new
  })
}
function Probe-Public([string]$Url){
  try{$r=Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 90;$h=[string]$r.Content;$h1=([regex]::Matches($h,'<h1\b','IgnoreCase')).Count;$sus=0;foreach($m in [regex]::Matches($h,'<img\b[^>]*>','IgnoreCase')){$s=[regex]::Match($m.Value,'\bsrc=["'']([^"'']+)["'']','IgnoreCase');if($s.Success -and (Is-SuspiciousUrl $s.Groups[1].Value)){$sus++}};[pscustomobject]@{ok=$true;http=[int]$r.StatusCode;h1=$h1;suspicious=$sus}}
  catch{[pscustomobject]@{ok=$false;http=$null;h1=$null;suspicious=$null;error=$_.Exception.Message}}
}

$workspace=$env:GITHUB_WORKSPACE
$auditPath=Join-Path $workspace 'bridge/gk10-full-result.json'
if(-not(Test-Path $auditPath)){throw 'Missing gk10-full-result.json'}
$audit=(Get-Content $auditPath -Raw)|ConvertFrom-Json
$targets=@($audit.results|Where-Object{$_.score -lt 10 -and (($_.issues -contains 'h1_count_2') -or ($_.suspicious_images -gt 0))})
if($targets.Count -lt 1){throw 'No remaining H1/schematic targets found.'}

$secretDir=Join-Path $env:APPDATA 'GK-MCP-Tunnel'
$user=(Get-Content (Join-Path $secretDir 'wp-user.txt') -Raw).Trim();$pass=Get-PlainSecret (Join-Path $secretDir 'wp-password.dat')
try{$basic=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$user`:$pass"))}finally{Remove-Variable pass -ErrorAction SilentlyContinue}
$headers=@{Authorization="Basic $basic";Accept='application/json'};Remove-Variable basic -ErrorAction SilentlyContinue

$media=@{}
foreach($mid in 29397,29398,29401,29403){$r=Invoke-Wp 'GET' "/wp/v2/media/$mid?_fields=id,source_url,alt_text" $headers;if(-not$r.ok){throw "Cannot read media $mid"};$media[$mid]=$r.body|ConvertFrom-Json}

$backup=[ordered]@{started_utc=(Get-Date).ToUniversalTime().ToString('o');targets=$targets.Count;items=@()}
$result=[ordered]@{started_utc=$backup.started_utc;targets=$targets.Count;changed=0;verified=0;failed=0;items=@();finished_utc=$null}
$backupDir='C:\GKBridge\backups';New-Item -ItemType Directory -Force -Path $backupDir|Out-Null

foreach($t in $targets){
  $type=if([string]$t.type -eq 'page'){'pages'}else{'posts'};$id=[int]$t.id
  $read=Invoke-Wp 'GET' "/wp/v2/$type/$id?context=edit&_fields=id,modified,slug,link,title,featured_media,content" $headers
  if(-not$read.ok){$result.failed++;$result.items+=@([ordered]@{id=$id;ok=$false;stage='read';error=$read.body});continue}
  $o=$read.body|ConvertFrom-Json;$raw=[string]$o.content.raw;$title=[string]$o.title.raw;$slug=[string]$o.slug;$text="$title $slug $raw"
  $mid=Get-PhotoMediaId $text;$photo=$media[$mid];$replacement=[string]$photo.source_url;$alt=if(-not[string]::IsNullOrWhiteSpace([string]$photo.alt_text)){[string]$photo.alt_text}else{"Passendes reales Foto zu $title"}
  $backup.items+=@([ordered]@{id=$id;type=$type;modified=[string]$o.modified;featured_media=[int]$o.featured_media;content_raw=$raw})
  $stamp=Get-Date -Format 'yyyyMMdd-HHmmss';[IO.File]::WriteAllText((Join-Path $backupDir "$type-$id-$stamp-gk10remaining-before.html"),$raw,(New-Object Text.UTF8Encoding($false)))

  $new=$raw;$h1Changed=$false;$imgChanged=0
  if($t.issues -contains 'h1_count_2'){
    $before=$new
    $new=[regex]::Replace($new,'<h1\b([^>]*)>','<h2$1>','IgnoreCase')
    $new=[regex]::Replace($new,'</h1\s*>','</h2>','IgnoreCase')
    $h1Changed=($new -ne $before)
  }
  if([int]$t.suspicious_images -gt 0){$cnt=0;$new=Replace-SuspiciousImages $new $replacement $alt ([ref]$cnt);$imgChanged=$cnt}
  $body=[ordered]@{}
  if($new -ne $raw){$body.content=$new}
  if([int]$t.suspicious_images -gt 0 -and [int]$o.featured_media -ne $mid){$body.featured_media=$mid}
  if($body.Count -eq 0){$probe=Probe-Public [string]$o.link;$ok=($probe.ok -and $probe.h1 -eq 1 -and $probe.suspicious -eq 0);if($ok){$result.verified++}else{$result.failed++};$result.items+=@([ordered]@{id=$id;ok=$ok;changed=$false;probe=$probe});continue}

  $write=Invoke-Wp 'POST' "/wp/v2/$type/$id" $headers $body
  if(-not$write.ok){$result.failed++;$result.items+=@([ordered]@{id=$id;ok=$false;stage='write';error=$write.body});continue}
  $result.changed++
  Start-Sleep -Milliseconds 150
  $probe=Probe-Public [string]$o.link;$ok=($probe.ok -and $probe.h1 -eq 1 -and $probe.suspicious -eq 0)
  if($ok){$result.verified++}else{$result.failed++}
  $result.items+=@([ordered]@{id=$id;title=$title;ok=$ok;changed=$true;h1_changed=$h1Changed;inline_images_replaced=$imgChanged;featured_media=$mid;url=[string]$o.link;probe=$probe})
}
$result.finished_utc=(Get-Date).ToUniversalTime().ToString('o')
[IO.File]::WriteAllText((Join-Path $workspace 'bridge/gk10-remaining-backup.json'),($backup|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $workspace 'bridge/gk10-remaining-fix-result.json'),($result|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
Write-Host "GK10 remaining repair complete: targets=$($result.targets) changed=$($result.changed) verified=$($result.verified) failed=$($result.failed)"
if($result.failed -gt 0){exit 2}
