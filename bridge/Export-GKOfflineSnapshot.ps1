Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Get-PlainSecret([string]$Path){$s=Get-Content $Path|ConvertTo-SecureString;$p=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s);try{[Runtime.InteropServices.Marshal]::PtrToStringBSTR($p)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p)}}
function Wp([string]$Path,[hashtable]$Headers){$p=@{Uri=('https://glasfaser-kompass.de/wp-json'+$Path);Method='GET';Headers=$Headers;UseBasicParsing=$true;TimeoutSec=180};$r=Invoke-WebRequest @p;if([string]::IsNullOrWhiteSpace([string]$r.Content)){return $null};[string]$r.Content|ConvertFrom-Json}
function All([string]$Base,[hashtable]$Headers){$out=@();$page=1;do{$items=@(Wp ($Base+($(if($Base.Contains('?')){'&'}else{'?'})+"per_page=100&page=$page")) $Headers);$out+=$items;$page++}while($items.Count-eq100);return @($out)}
$secretDir=Join-Path $env:APPDATA 'GK-MCP-Tunnel';$user=(Get-Content(Join-Path $secretDir 'wp-user.txt')-Raw).Trim();$pass=Get-PlainSecret(Join-Path $secretDir 'wp-password.dat')
try{$basic=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($user+':'+$pass))}finally{Remove-Variable pass -ErrorAction SilentlyContinue}
$headers=@{Authorization="Basic $basic";Accept='application/json'};Remove-Variable basic -ErrorAction SilentlyContinue
$fields='id,date,modified,slug,status,type,link,title,content,excerpt,featured_media,template,meta'
$pages=All("/wp/v2/pages?context=edit&status=publish&_fields=$fields")$headers
$posts=All("/wp/v2/posts?context=edit&status=publish&_fields=$fields")$headers
$mediaFields='id,date,modified,slug,status,link,title,caption,description,alt_text,media_type,mime_type,source_url,media_details'
$media=All("/wp/v2/media?context=edit&status=inherit&_fields=$mediaFields")$headers
$snapshot=[ordered]@{captured_utc=(Get-Date).ToUniversalTime().ToString('o');site='https://glasfaser-kompass.de';read_only=$true;page_count=$pages.Count;post_count=$posts.Count;media_count=$media.Count;pages=$pages;posts=$posts;media=$media}
$path=Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-snapshot.json';[IO.File]::WriteAllText($path,($snapshot|ConvertTo-Json -Depth 60),(New-Object Text.UTF8Encoding($false)))
$manifest=[ordered]@{captured_utc=$snapshot.captured_utc;page_count=$pages.Count;post_count=$posts.Count;media_count=$media.Count;snapshot='bridge/gk-offline-snapshot.json';status='SNAPSHOT_COMPLETE_NO_WRITES'}
[IO.File]::WriteAllText((Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-snapshot-manifest.json'),($manifest|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
Write-Host "Read-only snapshot complete: pages=$($pages.Count), posts=$($posts.Count), media=$($media.Count)"