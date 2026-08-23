Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Get-PlainSecret([string]$Path){$s=Get-Content $Path|ConvertTo-SecureString;$p=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s);try{[Runtime.InteropServices.Marshal]::PtrToStringBSTR($p)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p)}}
function Wp([string]$Method,[string]$Path,[hashtable]$Headers,[object]$Body=$null){$p=@{Uri=('https://glasfaser-kompass.de/wp-json'+$Path);Method=$Method;Headers=$Headers;UseBasicParsing=$true;TimeoutSec=180};if($null-ne$Body){$j=$Body|ConvertTo-Json -Depth 40 -Compress;$p.Body=[Text.Encoding]::UTF8.GetBytes($j);$p.ContentType='application/json; charset=utf-8'};$r=Invoke-WebRequest @p;if([string]::IsNullOrWhiteSpace([string]$r.Content)){return $null};[string]$r.Content|ConvertFrom-Json}
function Shot([string]$Url,[string]$Path,[int]$W,[int]$H){$cs=@("$env:ProgramFiles\Google\Chrome\Application\chrome.exe","$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe","$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe");$chrome=$cs|Where-Object{Test-Path $_}|Select-Object -First 1;if(-not$chrome){throw 'Chrome fehlt'};& $chrome --headless=new --disable-gpu --hide-scrollbars --window-size="$W,$H" --screenshot="$Path" $Url|Out-Null;if(-not(Test-Path $Path)){throw "Screenshot fehlt: $Path"}}
function Save([object]$x){[IO.File]::WriteAllText((Join-Path $env:GITHUB_WORKSPACE 'bridge/direct-live-improvements-result.json'),($x|ConvertTo-Json -Depth 40),(New-Object Text.UTF8Encoding($false)))}
$secretDir=Join-Path $env:APPDATA 'GK-MCP-Tunnel';$user=(Get-Content(Join-Path $secretDir 'wp-user.txt')-Raw).Trim();$pass=Get-PlainSecret(Join-Path $secretDir 'wp-password.dat')
try{$basic=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($user+':'+$pass))}finally{Remove-Variable pass -ErrorAction SilentlyContinue}
$headers=@{Authorization="Basic $basic";Accept='application/json'};Remove-Variable basic -ErrorAction SilentlyContinue
$pages=@(
[ordered]@{id=21005;slug='dsl-kupfer';url='https://glasfaser-kompass.de/dsl-kupfer/'},
[ordered]@{id=21009;slug='praxiswissen';url='https://glasfaser-kompass.de/praxiswissen/'},
[ordered]@{id=21008;slug='stoerungen';url='https://glasfaser-kompass.de/stoerungen/'},
[ordered]@{id=1009;slug='technik-lexikon';url='https://glasfaser-kompass.de/technik-lexikon-2/'}
)
$shotDir=Join-Path $env:GITHUB_WORKSPACE 'bridge/direct-live-evidence';New-Item -ItemType Directory -Force -Path $shotDir|Out-Null
$result=[ordered]@{started_utc=(Get-Date).ToUniversalTime().ToString('o');status='RUNNING';dsl_image_action=$null;dsl_image=$null;verified=@();rollback=$false;error=$null}
$dslBefore=$null;$dslWritten=$false
try{
$dslBefore=Wp 'GET' '/wp/v2/pages/21005?context=edit&_fields=id,content,featured_media' $headers
$media=Wp 'GET' '/wp/v2/media/25957?context=edit&_fields=id,source_url,alt_text,caption,description,title,media_type,mime_type' $headers
$meta=([string]$media.title.rendered+' '+[string]$media.alt_text+' '+[string]$media.caption.rendered+' '+[string]$media.description.rendered+' '+[string]$media.source_url).ToLowerInvariant()
$allowed=($meta-match'dsl|kupfer|tae|apl|endleitung|telefonleitung')
$forbidden=($meta-match'glasfaser|ftth|splei|muffe|wlan|access.point|router')
$isPhoto=([string]$media.media_type-eq'image'-and[string]$media.mime_type-match'^image/(jpeg|webp)$')
$raw=[string]$dslBefore.content.raw
$pattern='(?is)<!-- gk-direct-live-v1:dsl-kupfer -->.*?<!-- /wp:image -->'
if($allowed-and-not$forbidden-and$isPhoto){
  $alt=[string]$media.alt_text;if([string]::IsNullOrWhiteSpace($alt)){$alt=[string]$media.title.rendered}
  $replacement=[regex]::Match($raw,$pattern).Value
  if([string]::IsNullOrWhiteSpace($replacement)){throw 'DSL-Leitblock fehlt'}
  $replacement=[regex]::Replace($replacement,'(?is)<!-- wp:image.*?<!-- /wp:image -->','<!-- wp:image {"id":25957,"sizeSlug":"large","linkDestination":"none","align":"wide"} --><figure class="wp-block-image alignwide size-large"><img src="'+[string]$media.source_url+'" alt="'+[Net.WebUtility]::HtmlEncode($alt)+'" class="wp-image-25957"/></figure><!-- /wp:image -->')
  $raw=([regex]$pattern).Replace($raw,$replacement,1)
  Wp 'POST' '/wp/v2/pages/21005' $headers ([ordered]@{content=$raw;featured_media=25957})|Out-Null
  $result.dsl_image_action='replaced_with_semantically_gated_dsl_media';$result.dsl_image=[string]$media.source_url
}else{
  $raw=[regex]::Replace($raw,'(?is)<!-- wp:image[^>]*>\s*<figure[^>]*>.*?glasfaser-spleissmuffe.*?</figure>\s*<!-- /wp:image -->','')
  Wp 'POST' '/wp/v2/pages/21005' $headers ([ordered]@{content=$raw;featured_media=0})|Out-Null
  $result.dsl_image_action='removed_wrong_image_no_safe_dsl_media';$result.dsl_image=$null
}
$dslWritten=$true
foreach($p in $pages){
  $r=Invoke-WebRequest -Uri $p.url -UseBasicParsing -TimeoutSec 180 -Headers @{'Cache-Control'='no-cache';Pragma='no-cache'};$html=[string]$r.Content
  $h1=([regex]::Matches($html,'<h1\b','IgnoreCase')).Count;$marker=$html.Contains("gk-direct-live-v1:$($p.slug)")
  if([int]$r.StatusCode-ne200-or$h1-ne1-or-not$marker){throw "Public acceptance $($p.id) failed: http=$($r.StatusCode) h1=$h1 marker=$marker"}
  if($p.id-eq21005-and$html-match'glasfaser-spleissmuffe'){throw 'Falsches Spleissmuffenbild ist öffentlich noch vorhanden'}
  if($p.id-eq21005-and$result.dsl_image){$stem=[IO.Path]::GetFileNameWithoutExtension(([uri][string]$result.dsl_image).AbsolutePath);if($html-notmatch[regex]::Escape($stem)){throw 'Freigegebenes DSL-Bild ist öffentlich nicht sichtbar'}}
  $desk=Join-Path $shotDir "$($p.slug)-desktop.png";$mob=Join-Path $shotDir "$($p.slug)-mobile.png";Shot $p.url $desk 1440 1400;Shot $p.url $mob 390 844
  $result.verified+=[ordered]@{id=$p.id;url=$p.url;http=200;h1_count=$h1;marker=$marker;desktop="bridge/direct-live-evidence/$($p.slug)-desktop.png";mobile="bridge/direct-live-evidence/$($p.slug)-mobile.png"}
}
$result.status='SUCCEEDED';$result.finished_utc=(Get-Date).ToUniversalTime().ToString('o');Save $result
}catch{
  $result.status='FAILED';$result.error=$_.Exception.Message
  if($dslWritten-and$null-ne$dslBefore){try{Wp 'POST' '/wp/v2/pages/21005' $headers ([ordered]@{content=[string]$dslBefore.content.raw;featured_media=[int]$dslBefore.featured_media})|Out-Null;$result.rollback=$true}catch{$result.error+='; rollback failed: '+$_.Exception.Message}}
  $result.finished_utc=(Get-Date).ToUniversalTime().ToString('o');Save $result;throw
}