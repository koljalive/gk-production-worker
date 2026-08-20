Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-PlainSecret([string]$Path){$s=Get-Content $Path|ConvertTo-SecureString;$p=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s);try{[Runtime.InteropServices.Marshal]::PtrToStringBSTR($p)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p)}}
function Invoke-WpJson([string]$Method,[string]$Path,[hashtable]$Headers,[object]$Body=$null){
  $url='https://glasfaser-kompass.de/wp-json'+$Path
  $p=@{Uri=$url;Method=$Method;Headers=$Headers;UseBasicParsing=$true;TimeoutSec=180}
  if($null-ne$Body){$j=$Body|ConvertTo-Json -Depth 40 -Compress;$p.Body=[Text.Encoding]::UTF8.GetBytes($j);$p.ContentType='application/json; charset=utf-8'}
  $r=Invoke-WebRequest @p
  if([string]::IsNullOrWhiteSpace([string]$r.Content)){return $null}
  [string]$r.Content|ConvertFrom-Json
}
function Find-Media([string]$Title,[hashtable]$Headers){
  $q=[Uri]::EscapeDataString($Title)
  $arr=@(Invoke-WpJson 'GET' ("/wp/v2/media?context=edit&per_page=100&search=$q&_fields=id,title,source_url,alt_text,mime_type") $Headers)
  $arr|Where-Object{[string]$_.title.raw -eq $Title}|Select-Object -First 1
}
function Ensure-Media([hashtable]$Spec,[hashtable]$Headers){
  $hit=Find-Media $Spec.title $Headers
  if($hit){return $hit}
  $tmp=Join-Path $env:TEMP $Spec.filename
  Invoke-WebRequest -Uri $Spec.url -OutFile $tmp -UseBasicParsing -TimeoutSec 180
  $bytes=[IO.File]::ReadAllBytes($tmp)
  $uh=@{};foreach($k in $Headers.Keys){$uh[$k]=$Headers[$k]}
  $uh['Content-Disposition']='attachment; filename="'+$Spec.filename+'"'
  $r=Invoke-WebRequest -Uri 'https://glasfaser-kompass.de/wp-json/wp/v2/media' -Method POST -Headers $uh -ContentType $Spec.mime -Body $bytes -UseBasicParsing -TimeoutSec 180
  $m=[string]$r.Content|ConvertFrom-Json
  Invoke-WpJson 'POST' ("/wp/v2/media/$($m.id)") $Headers ([ordered]@{title=$Spec.title;alt_text=$Spec.alt;caption=$Spec.caption;description=$Spec.description})|Out-Null
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  Invoke-WpJson 'GET' ("/wp/v2/media/$($m.id)?context=edit&_fields=id,title,source_url,alt_text,mime_type") $Headers
}
function Backup-Json([string]$Name,[object]$Object){
  $dir='C:\GKBridge\backups';New-Item -ItemType Directory -Force -Path $dir|Out-Null
  $path=Join-Path $dir ($Name+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json')
  [IO.File]::WriteAllText($path,($Object|ConvertTo-Json -Depth 40),(New-Object Text.UTF8Encoding($false)))
  $path
}

$secretDir=Join-Path $env:APPDATA 'GK-MCP-Tunnel'
$user=(Get-Content(Join-Path $secretDir 'wp-user.txt')-Raw).Trim();$pass=Get-PlainSecret(Join-Path $secretDir 'wp-password.dat')
try{$basic=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$user`:$pass"))}finally{Remove-Variable pass -ErrorAction SilentlyContinue}
$headers=@{Authorization="Basic $basic";Accept='application/json'};Remove-Variable basic -ErrorAction SilentlyContinue

$routerSpec=@{title='FRITZ!Box 7590 – reales Routerfoto';url='https://commons.wikimedia.org/wiki/Special:Redirect/file/FRITZ!Box_7590-Image29.jpg';filename='fritzbox-7590-reales-routerfoto.jpg';mime='image/jpeg';alt='Rückseite einer echten FRITZ!Box 7590 mit DSL-, WAN-, LAN- und USB-Anschlüssen';caption='Foto: Janus / Wikimedia Commons / CC BY-SA 3.0';description='Reales Produktfoto. Quelle: Wikimedia Commons, CC BY-SA 3.0.'}
$ftthSpec=@{title='FTTH-Abschluss – reales Foto';url='https://commons.wikimedia.org/wiki/Special:Redirect/file/Fiber_to_the_Home-aansluiting_van_E-fiber.jpg';filename='ftth-abschluss-reales-foto.jpg';mime='image/jpeg';alt='Realer FTTH-Glasfaserabschluss an einer Wand';caption='Foto: Maxmust / Wikimedia Commons / CC BY-SA 4.0';description='Reales FTTH-Foto. Quelle: Wikimedia Commons, CC BY-SA 4.0.'}
$router=Ensure-Media $routerSpec $headers
$ftth=Ensure-Media $ftthSpec $headers

$changes=@()
# Router page: visible image is the page featured image used by Astra.
$beforeRouter=Invoke-WpJson 'GET' '/wp/v2/pages/21020?context=edit&_fields=id,modified,title,link,featured_media' $headers
$routerBackup=Backup-Json 'page-21020-before-visible-image' $beforeRouter
if([int]$beforeRouter.featured_media -ne [int]$router.id){Invoke-WpJson 'POST' '/wp/v2/pages/21020' $headers ([ordered]@{featured_media=[int]$router.id})|Out-Null}
$afterRouter=Invoke-WpJson 'GET' '/wp/v2/pages/21020?context=edit&_fields=id,modified,title,link,featured_media' $headers
if([int]$afterRouter.featured_media -ne [int]$router.id){throw 'Router featured image did not persist.'}
$changes+=@([ordered]@{page_id=21020;kind='featured';old=[int]$beforeRouter.featured_media;new=[int]$afterRouter.featured_media;new_src=[string]$router.source_url;backup=$routerBackup;verified=$true})

# Homepage: visible image is embedded directly in content, so replace the actual rendered source.
$beforeHome=Invoke-WpJson 'GET' '/wp/v2/pages/21003?context=edit&_fields=id,modified,title,link,content,featured_media' $headers
$homeBackup=Backup-Json 'page-21003-before-visible-image' $beforeHome
$raw=[string]$beforeHome.content.raw
$old='https://glasfaser-kompass.de/wp-content/uploads/2026/08/exec-d6f3e553-e01b-4389-8ddd-a9d898b3c715.png'
$new=[string]$ftth.source_url
$changed=$raw.Replace($old,$new)
$changed=$changed.Replace('Glasfaser-Abschluss, ONT und WLAN-Router in einem modernen Heimnetz',$ftthSpec.alt)
if($changed -ne $raw){Invoke-WpJson 'POST' '/wp/v2/pages/21003' $headers ([ordered]@{content=$changed;featured_media=[int]$ftth.id})|Out-Null}
$afterHome=Invoke-WpJson 'GET' '/wp/v2/pages/21003?context=edit&_fields=id,modified,title,link,content,featured_media' $headers
$vr=[string]$afterHome.content.raw
if($vr.Contains($old)){throw 'Old homepage schematic image is still in content.'}
if(-not $vr.Contains($new)){throw 'Real FTTH image is not present in homepage content.'}
$changes+=@([ordered]@{page_id=21003;kind='inline+featured';old_src=$old;new_src=$new;new_media_id=[int]$ftth.id;backup=$homeBackup;verified=$true})

# Public verification with cache-busting query strings.
$stamp=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$public=@()
foreach($u in @('https://glasfaser-kompass.de/router-kaufberatung/','https://glasfaser-kompass.de/')){
  $sep=if($u.Contains('?')){'&'}else{'?'}
  $r=Invoke-WebRequest -Uri ($u+$sep+'gkimg='+$stamp) -UseBasicParsing -TimeoutSec 120
  $html=[string]$r.Content
  $public+=@([ordered]@{url=$u;status=[int]$r.StatusCode;has_router_real=$html.Contains([string]$router.source_url);has_ftth_real=$html.Contains([string]$ftth.source_url);has_old_router_svg=$html.Contains('gk-router-kaufberatung.svg');has_old_home_png=$html.Contains('exec-d6f3e553-e01b-4389-8ddd-a9d898b3c715.png')})
}

$out=[ordered]@{generated_at_utc=(Get-Date).ToUniversalTime().ToString('o');success=$true;router_media=$router;ftth_media=$ftth;changes=$changes;public=$public}
$path=Join-Path $env:GITHUB_WORKSPACE 'bridge/visible-image-fix-result.json'
[IO.File]::WriteAllText($path,($out|ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
Write-Host 'Visible image fix completed and public HTML checked.'
