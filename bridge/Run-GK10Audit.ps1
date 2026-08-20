Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-PlainSecret([string]$Path){
  $s=Get-Content $Path | ConvertTo-SecureString
  $p=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($p) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p) }
}
function Get-Wp([string]$Path,[hashtable]$Headers){
  $u='https://glasfaser-kompass.de/wp-json'+$Path
  try {
    $r=Invoke-WebRequest -Uri $u -Method GET -Headers $Headers -UseBasicParsing -TimeoutSec 180
    [pscustomobject]@{ok=$true;status=[int]$r.StatusCode;body=[string]$r.Content}
  } catch {
    $b='';$s=$null
    if($_.Exception.Response){try{$s=[int]$_.Exception.Response.StatusCode}catch{};try{$rd=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream());$b=$rd.ReadToEnd();$rd.Close()}catch{}}
    [pscustomobject]@{ok=$false;status=$s;body=$b;error=$_.Exception.Message}
  }
}
function Public-Probe([string]$Url){
  try {
    $r=Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 60
    $h=[string]$r.Content
    $canonical=([regex]::Match($h,'<link[^>]+rel=["'']canonical["''][^>]+href=["'']([^"'']+)')).Groups[1].Value
    [pscustomobject]@{
      url=$Url;status=[int]$r.StatusCode;bytes=$h.Length;
      h1_count=([regex]::Matches($h,'<h1\b','IgnoreCase')).Count;
      table_count=([regex]::Matches($h,'<table\b','IgnoreCase')).Count;
      amazon_links=([regex]::Matches($h,'https?://(?:www\.)?amazon\.[^"''\s<]+','IgnoreCase')).Count;
      sponsored_links=([regex]::Matches($h,'rel=["''][^"'']*sponsored[^"'']*["'']','IgnoreCase')).Count;
      canonical=$canonical;
      noindex=($h -match 'noindex');
      has_viewport=($h -match 'name=["'']viewport["'']');
      has_og_image=($h -match 'property=["'']og:image["'']');
      html=$null
    }
  } catch { [pscustomobject]@{url=$Url;status=$null;error=$_.Exception.Message} }
}

$secretDir=Join-Path $env:APPDATA 'GK-MCP-Tunnel'
$user=(Get-Content (Join-Path $secretDir 'wp-user.txt') -Raw).Trim()
$pass=Get-PlainSecret (Join-Path $secretDir 'wp-password.dat')
try{$basic=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$user`:$pass"))}finally{Remove-Variable pass -ErrorAction SilentlyContinue}
$headers=@{Authorization="Basic $basic";Accept='application/json'}
Remove-Variable basic -ErrorAction SilentlyContinue

$out=[ordered]@{generated_at_utc=(Get-Date).ToUniversalTime().ToString('o');site=$null;rankmath=$null;pages=@();posts=@();key_pages=@();public=@();errors=@()}

$root=Get-Wp '/' $headers
if($root.ok){$o=$root.body|ConvertFrom-Json;$out.site=[ordered]@{name=$o.name;url=$o.url;page_on_front=$o.page_on_front;page_for_posts=$o.page_for_posts;namespaces=$o.namespaces}}else{$out.errors+=@($root)}

$rm=Get-Wp '/wp-abilities/v1/abilities/rank-math/audit-site-seo/run' $headers
if($rm.ok){try{$out.rankmath=$rm.body|ConvertFrom-Json}catch{$out.rankmath=[ordered]@{raw=$rm.body}}}else{$out.errors+=@([ordered]@{area='rankmath';status=$rm.status;body=$rm.body})}

$p=Get-Wp '/wp/v2/pages?context=edit&per_page=100&_fields=id,slug,status,link,modified,title,featured_media,content' $headers
if($p.ok){$out.pages=@($p.body|ConvertFrom-Json)}else{$out.errors+=@([ordered]@{area='pages';status=$p.status;body=$p.body})}

for($n=1;$n -le 4;$n++){
  $x=Get-Wp ("/wp/v2/posts?context=edit&per_page=100&page=$n&_fields=id,slug,status,link,modified,title,featured_media,content") $headers
  if($x.ok){$out.posts+=@($x.body|ConvertFrom-Json)} elseif($x.status -ne 400){$out.errors+=@([ordered]@{area="posts-$n";status=$x.status;body=$x.body})}
}

$keyIds=@(21003,21020,21021,21022,21053,21043,21041,21066,21009,21008,21007,21006,21005,21004,20824,21967,21968,1009)
foreach($id in $keyIds){
  $found=@($out.pages|Where-Object id -eq $id)+@($out.posts|Where-Object id -eq $id)
  foreach($z in $found){
    $raw=[string]$z.content.raw
    $out.key_pages+=@([ordered]@{id=$z.id;title=$z.title.raw;slug=$z.slug;status=$z.status;link=$z.link;modified=$z.modified;featured_media=$z.featured_media;content_length=$raw.Length;table_count=([regex]::Matches($raw,'<table\b','IgnoreCase')).Count;amazon_links=([regex]::Matches($raw,'amazon\.','IgnoreCase')).Count;affiliate_tag=([regex]::Matches($raw,'tag=glasfaserkomp-21','IgnoreCase')).Count;content=$raw})
  }
}

$urls=@('https://glasfaser-kompass.de/','https://glasfaser-kompass.de/router-kaufberatung/','https://glasfaser-kompass.de/wlan-kaufberatung-2026/','https://glasfaser-kompass.de/glasfaser-hardware-2026/','https://glasfaser-kompass.de/internet-buchen/','https://glasfaser-kompass.de/ueber-den-autor/','https://glasfaser-kompass.de/telekom-readiness/','https://glasfaser-kompass.de/portal-status/')
foreach($u in $urls){$out.public+=@(Public-Probe $u)}

$path=Join-Path $env:GITHUB_WORKSPACE 'bridge/gk10-audit.json'
$json=$out|ConvertTo-Json -Depth 30
[IO.File]::WriteAllText($path,$json,(New-Object Text.UTF8Encoding($false)))
Write-Host "GK10 audit written: $path"
