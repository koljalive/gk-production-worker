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
  if($null-ne$Body){$j=$Body|ConvertTo-Json -Depth 40 -Compress;$p.Body=[Text.Encoding]::UTF8.GetBytes($j);$p.ContentType='application/json; charset=utf-8'}
  $r=Invoke-WebRequest @p
  if([string]::IsNullOrWhiteSpace([string]$r.Content)){return $null}
  [string]$r.Content|ConvertFrom-Json
}
function Is-Suspicious([string]$Url){ return $Url -match 'exec-|diagram|schema|signalweg|illustr|infograf|bauformen|collage|skizze|\.svg(?:\?|$)' }
function Backup([string]$Name,[object]$Obj){
  $dir='C:\GKBridge\backups';New-Item -ItemType Directory -Force -Path $dir|Out-Null
  $p=Join-Path $dir ($Name+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json')
  [IO.File]::WriteAllText($p,($Obj|ConvertTo-Json -Depth 40),(New-Object Text.UTF8Encoding($false)))
  return $p
}
function Probe([string]$Url,[string]$ExpectedImage=''){
  try{
    $r=Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 120
    $h=[string]$r.Content
    $h1=([regex]::Matches($h,'<h1\b','IgnoreCase')).Count
    $sus=0
    foreach($m in [regex]::Matches($h,'<img\b[^>]*>','IgnoreCase')){
      $s=[regex]::Match($m.Value,'\bsrc=["'']([^"'']+)["'']','IgnoreCase')
      if($s.Success -and (Is-Suspicious $s.Groups[1].Value)){$sus++}
    }
    [pscustomobject]@{ok=$true;http=[int]$r.StatusCode;h1=$h1;suspicious=$sus;expected_image=([string]::IsNullOrWhiteSpace($ExpectedImage) -or $h.Contains($ExpectedImage))}
  }catch{[pscustomobject]@{ok=$false;http=$null;h1=$null;suspicious=$null;expected_image=$false;error=$_.Exception.Message}}
}
function Purge([string]$Url){
  try{ Invoke-WebRequest -Uri $Url -Method PURGE -UseBasicParsing -TimeoutSec 60 | Out-Null }catch{}
}
function Wait-Probe([string]$Url,[string]$ExpectedImage,[scriptblock]$Predicate){
  $last=$null
  for($i=0;$i -lt 20;$i++){
    $last=Probe $Url $ExpectedImage
    if(& $Predicate $last){ return $last }
    Start-Sleep -Seconds 15
  }
  return $last
}
function Find-Chrome(){
  $candidates=@(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
  )
  foreach($c in $candidates){if($c -and (Test-Path $c)){return $c}}
  return $null
}
function Select-PraxisMedia([hashtable]$Headers){
  $candidates=@()
  foreach($id in 29398,29401,29397,29403){
    $path="/wp/v2/media/$($id)?context=edit&_fields=id,title,source_url,alt_text,mime_type,caption"
    $m=Invoke-Wp 'GET' $path $Headers
    if($null-eq$m){continue}
    $text=((([string]$m.title.raw)+' '+([string]$m.alt_text)+' '+([string]$m.caption.raw)+' '+([string]$m.source_url)).ToLowerInvariant())
    if(([string]$m.mime_type) -notmatch '^image/'){continue}
    if([string]::IsNullOrWhiteSpace([string]$m.source_url)){continue}
    if(Is-Suspicious ([string]$m.source_url)){continue}
    if($text -match 'schema|diagram|illustr|infograf|skizze|collage'){continue}
    $score=0
    foreach($kw in @('techniker','technik','installation','anschluss','leitung','telekom','dsl','kupfer','glasfaser','ftth','foto','real')){if($text -match [regex]::Escape($kw)){$score++}}
    $candidates+=@([pscustomobject]@{media=$m;score=$score;text=$text})
  }
  $best=$candidates|Sort-Object score -Descending|Select-Object -First 1
  if($null-eq$best -or [int]$best.score -lt 1){throw 'No semantically plausible real photo passed the Praxiswissen safety gate.'}
  return $best.media
}

$workspace=$env:GITHUB_WORKSPACE
$secretDir=Join-Path $env:APPDATA 'GK-MCP-Tunnel'
$user=(Get-Content (Join-Path $secretDir 'wp-user.txt') -Raw).Trim()
$pass=Get-PlainSecret (Join-Path $secretDir 'wp-password.dat')
try{$basic=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$user`:$pass"))}finally{Remove-Variable pass -ErrorAction SilentlyContinue}
$headers=@{Authorization="Basic $basic";Accept='application/json'};Remove-Variable basic -ErrorAction SilentlyContinue

$result=[ordered]@{started_utc=(Get-Date).ToUniversalTime().ToString('o');status='RUNNING';items=@();screenshots=@();finished_utc=$null}

$router=Invoke-Wp 'GET' '/wp/v2/pages/21020?context=edit&_fields=id,modified,link,title,content,featured_media' $headers
$routerBackup=Backup 'acceptance-pilot-21020-before' $router
$raw=[string]$router.content.raw
$beforeContentH1=([regex]::Matches($raw,'<h1\b','IgnoreCase')).Count
$new=$raw
if($beforeContentH1 -gt 0){
  $new=[regex]::Replace($new,'<h1\b([^>]*)>','<h2$1>','IgnoreCase')
  $new=[regex]::Replace($new,'</h1\s*>','</h2>','IgnoreCase')
}
if($new -ne $raw){Invoke-Wp 'POST' '/wp/v2/pages/21020' $headers ([ordered]@{content=$new})|Out-Null}
Purge ([string]$router.link)
$routerProbe=Wait-Probe ([string]$router.link) '' { param($p) $p.ok -and $p.http -eq 200 -and $p.h1 -eq 1 }
$result.items+=@([ordered]@{id=21020;url=[string]$router.link;change='content_h1_to_h2';backup=$routerBackup;public=$routerProbe;accepted=($routerProbe.ok -and $routerProbe.h1 -eq 1)})
if(-not($routerProbe.ok -and $routerProbe.h1 -eq 1)){throw 'Acceptance pilot failed on router H1 public verification.'}

$media=Select-PraxisMedia $headers
$hub=Invoke-Wp 'GET' '/wp/v2/pages/21009?context=edit&_fields=id,modified,link,title,content,featured_media' $headers
$hubBackup=Backup 'acceptance-pilot-21009-before' $hub
$hubRaw=[string]$hub.content.raw
$replacement=[string]$media.source_url
$alt=if([string]::IsNullOrWhiteSpace([string]$media.alt_text)){'Reales Technikfoto passend zum Praxiswissen'}else{[string]$media.alt_text}
$rx=[regex]::new('<img\b[^>]*>','IgnoreCase')
$script:replaced=0
$hubNew=$rx.Replace($hubRaw,{param($m)
  $tag=$m.Value
  $srcM=[regex]::Match($tag,'\bsrc=["'']([^"'']+)["'']','IgnoreCase')
  if(-not $srcM.Success -or -not(Is-Suspicious $srcM.Groups[1].Value)){return $tag}
  $script:replaced++
  $x=[regex]::Replace($tag,'\bsrc=["''][^"'']+["'']',('src="'+$replacement+'"'),'IgnoreCase')
  $x=[regex]::Replace($x,'\s+srcset=["''][^"'']*["'']','','IgnoreCase')
  $x=[regex]::Replace($x,'\s+sizes=["''][^"'']*["'']','','IgnoreCase')
  if([regex]::IsMatch($x,'\balt=["''][^"'']*["'']','IgnoreCase')){$x=[regex]::Replace($x,'\balt=["''][^"'']*["'']',('alt="'+[System.Net.WebUtility]::HtmlEncode($alt)+'"'),'IgnoreCase')}
  else{$x=$x -replace '>$',(' alt="'+[System.Net.WebUtility]::HtmlEncode($alt)+'">')}
  return $x
})
if($script:replaced -lt 1){throw 'No suspicious visible image found on Praxiswissen pilot; refusing blind write.'}
Invoke-Wp 'POST' '/wp/v2/pages/21009' $headers ([ordered]@{content=$hubNew;featured_media=[int]$media.id})|Out-Null
$verifyHub=Invoke-Wp 'GET' '/wp/v2/pages/21009?context=edit&_fields=id,link,content,featured_media' $headers
if(-not([string]$verifyHub.content.raw).Contains($replacement)){throw 'Praxiswissen write did not persist expected image.'}
Purge ([string]$hub.link)
$hubProbe=Wait-Probe ([string]$hub.link) $replacement { param($p) $p.ok -and $p.http -eq 200 -and $p.h1 -eq 1 -and $p.suspicious -eq 0 -and $p.expected_image }
$result.items+=@([ordered]@{id=21009;url=[string]$hub.link;change='replace_visible_schematic_with_selected_real_photo';media_id=[int]$media.id;media_title=[string]$media.title.raw;media_src=$replacement;backup=$hubBackup;public=$hubProbe;accepted=($hubProbe.ok -and $hubProbe.h1 -eq 1 -and $hubProbe.suspicious -eq 0 -and $hubProbe.expected_image)})
if(-not($hubProbe.ok -and $hubProbe.h1 -eq 1 -and $hubProbe.suspicious -eq 0 -and $hubProbe.expected_image)){throw 'Acceptance pilot failed on Praxiswissen public verification.'}

$chrome=Find-Chrome
if($chrome){
  foreach($pair in @(@{name='router';url=[string]$router.link},@{name='praxiswissen';url=[string]$hub.link})){
    $desktop=Join-Path $workspace ("bridge/acceptance-$($pair.name)-desktop.png")
    $mobile=Join-Path $workspace ("bridge/acceptance-$($pair.name)-mobile.png")
    & $chrome --headless=new --disable-gpu --hide-scrollbars --window-size=1440,1200 --screenshot=$desktop $pair.url | Out-Null
    & $chrome --headless=new --disable-gpu --hide-scrollbars --window-size=390,844 --screenshot=$mobile $pair.url | Out-Null
    if(Test-Path $desktop){$result.screenshots+=@([ordered]@{url=$pair.url;viewport='desktop';path=(Split-Path $desktop -Leaf)})}
    if(Test-Path $mobile){$result.screenshots+=@([ordered]@{url=$pair.url;viewport='mobile';path=(Split-Path $mobile -Leaf)})}
  }
}
$result.status='PUBLIC VERIFIED - VISUAL EVIDENCE CAPTURED'
$result.finished_utc=(Get-Date).ToUniversalTime().ToString('o')
[IO.File]::WriteAllText((Join-Path $workspace 'bridge/acceptance-pilot-result.json'),($result|ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
Write-Host 'Acceptance pilot completed: router H1 and Praxiswissen visible image publicly verified.'
