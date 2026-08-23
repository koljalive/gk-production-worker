Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Get-PlainSecret([string]$Path){$s=Get-Content $Path|ConvertTo-SecureString;$p=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s);try{[Runtime.InteropServices.Marshal]::PtrToStringBSTR($p)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p)}}
function Wp([string]$Method,[string]$Path,[hashtable]$Headers,[object]$Body=$null){$p=@{Uri=('https://glasfaser-kompass.de/wp-json'+$Path);Method=$Method;Headers=$Headers;UseBasicParsing=$true;TimeoutSec=180};if($null-ne$Body){$j=$Body|ConvertTo-Json -Depth 40 -Compress;$p.Body=[Text.Encoding]::UTF8.GetBytes($j);$p.ContentType='application/json; charset=utf-8'};$r=Invoke-WebRequest @p;if([string]::IsNullOrWhiteSpace([string]$r.Content)){return $null};[string]$r.Content|ConvertFrom-Json}
function Shot([string]$Url,[string]$Path,[int]$W,[int]$H){$cs=@("$env:ProgramFiles\Google\Chrome\Application\chrome.exe","$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe","$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe");$chrome=$cs|Where-Object{Test-Path $_}|Select-Object -First 1;if(-not$chrome){throw 'Chrome fehlt'};& $chrome --headless=new --disable-gpu --hide-scrollbars --window-size="$W,$H" --screenshot="$Path" 'https://glasfaser-kompass.de/dsl-kupfer/'|Out-Null;if(-not(Test-Path $Path)){throw "Screenshot fehlt: $Path"}}
function Save([object]$x){[IO.File]::WriteAllText((Join-Path $env:GITHUB_WORKSPACE 'bridge/direct-live-improvements-result.json'),($x|ConvertTo-Json -Depth 30),(New-Object Text.UTF8Encoding($false)))}
$secretDir=Join-Path $env:APPDATA 'GK-MCP-Tunnel';$user=(Get-Content(Join-Path $secretDir 'wp-user.txt')-Raw).Trim();$pass=Get-PlainSecret(Join-Path $secretDir 'wp-password.dat')
try{$basic=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($user+':'+$pass))}finally{Remove-Variable pass -ErrorAction SilentlyContinue}
$headers=@{Authorization="Basic $basic";Accept='application/json'};Remove-Variable basic -ErrorAction SilentlyContinue
$result=[ordered]@{started_utc=(Get-Date).ToUniversalTime().ToString('o');status='RUNNING';action='remove wrong DSL spleissmuffe image';rollback=$false;verified=$null;error=$null}
$before=$null;$written=$false
try{
$before=Wp 'GET' '/wp/v2/pages/21005?context=edit&_fields=id,content,featured_media' $headers
$raw=[string]$before.content.raw
$raw=[regex]::Replace($raw,'(?is)<!-- wp:image[^>]*>\s*<figure[^>]*>.*?glasfaser-spleissmuffe.*?</figure>\s*<!-- /wp:image -->','')
$raw=[regex]::Replace($raw,'(?is)<figure[^>]*>.*?glasfaser-spleissmuffe.*?</figure>','')
Wp 'POST' '/wp/v2/pages/21005' $headers ([ordered]@{content=$raw;featured_media=0})|Out-Null
$written=$true
$r=Invoke-WebRequest -Uri 'https://glasfaser-kompass.de/dsl-kupfer/' -UseBasicParsing -TimeoutSec 180 -Headers @{'Cache-Control'='no-cache';Pragma='no-cache'};$html=[string]$r.Content
$h1=([regex]::Matches($html,'<h1\b','IgnoreCase')).Count;$wrong=($html-match'glasfaser-spleissmuffe');$marker=$html.Contains('gk-direct-live-v1:dsl-kupfer')
if([int]$r.StatusCode-ne200-or$h1-ne1-or$wrong-or-not$marker){throw "DSL acceptance failed: http=$($r.StatusCode) h1=$h1 wrong=$wrong marker=$marker"}
$dir=Join-Path $env:GITHUB_WORKSPACE 'bridge/direct-live-evidence';New-Item -ItemType Directory -Force -Path $dir|Out-Null
Shot 'https://glasfaser-kompass.de/dsl-kupfer/' (Join-Path $dir 'dsl-kupfer-desktop.png') 1440 1400
Shot 'https://glasfaser-kompass.de/dsl-kupfer/' (Join-Path $dir 'dsl-kupfer-mobile.png') 390 844
$result.verified=[ordered]@{url='https://glasfaser-kompass.de/dsl-kupfer/';http=200;h1_count=1;wrong_image_present=$false;marker=$true;desktop='bridge/direct-live-evidence/dsl-kupfer-desktop.png';mobile='bridge/direct-live-evidence/dsl-kupfer-mobile.png'}
$result.status='SUCCEEDED';$result.finished_utc=(Get-Date).ToUniversalTime().ToString('o');Save $result
}catch{$result.status='FAILED';$result.error=$_.Exception.Message;if($written-and$null-ne$before){try{Wp 'POST' '/wp/v2/pages/21005' $headers ([ordered]@{content=[string]$before.content.raw;featured_media=[int]$before.featured_media})|Out-Null;$result.rollback=$true}catch{$result.error+='; rollback failed: '+$_.Exception.Message}};$result.finished_utc=(Get-Date).ToUniversalTime().ToString('o');Save $result;throw}