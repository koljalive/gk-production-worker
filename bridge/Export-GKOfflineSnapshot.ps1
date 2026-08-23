Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Get-PlainSecret([string]$Path){$s=Get-Content $Path|ConvertTo-SecureString;$p=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s);try{[Runtime.InteropServices.Marshal]::PtrToStringBSTR($p)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p)}}
function ConvertFrom-Utf8Response($Response){
  $bytes=$Response.RawContentStream.ToArray()
  $text=[Text.Encoding]::UTF8.GetString($bytes)
  ConvertFrom-Json -InputObject $text
}
function Get-Collection([string]$Base,[hashtable]$Headers){
  $sep=$(if($Base.Contains('?')){'&'}else{'?'})
  $first=Invoke-WebRequest -Uri ('https://glasfaser-kompass.de/wp-json'+$Base+$sep+'per_page=100&page=1') -Method GET -Headers $Headers -UseBasicParsing -TimeoutSec 180
  $total=[int]$first.Headers['X-WP-Total'];$totalPages=[int]$first.Headers['X-WP-TotalPages']
  $items=@();$parsed=ConvertFrom-Utf8Response $first;foreach($item in $parsed){$items+=$item}
  if($totalPages -gt 1){for($page=2;$page -le $totalPages;$page++){$r=Invoke-WebRequest -Uri ('https://glasfaser-kompass.de/wp-json'+$Base+$sep+"per_page=100&page=$page") -Method GET -Headers $Headers -UseBasicParsing -TimeoutSec 180;$parsed=ConvertFrom-Utf8Response $r;foreach($item in $parsed){$items+=$item}}}
  if($items.Count -ne $total){throw "Incomplete collection $Base expected=$total actual=$($items.Count)"}
  [ordered]@{items=@($items);reported_total=$total;reported_pages=$totalPages}
}
$secretDir=Join-Path $env:APPDATA 'GK-MCP-Tunnel';$user=(Get-Content(Join-Path $secretDir 'wp-user.txt')-Raw).Trim();$pass=Get-PlainSecret(Join-Path $secretDir 'wp-password.dat')
try{$basic=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($user+':'+$pass))}finally{Remove-Variable pass -ErrorAction SilentlyContinue}
$headers=@{Authorization="Basic $basic";Accept='application/json'};Remove-Variable basic -ErrorAction SilentlyContinue
$fields='id,date,modified,slug,status,type,link,title,content,excerpt,featured_media,template,meta'
$pageSet=Get-Collection "/wp/v2/pages?context=edit&status=publish&_fields=$fields" $headers
$postSet=Get-Collection "/wp/v2/posts?context=edit&status=publish&_fields=$fields" $headers
$mediaFields='id,date,modified,slug,status,link,title,caption,description,alt_text,media_type,mime_type,source_url,media_details'
$mediaSet=Get-Collection "/wp/v2/media?context=edit&status=inherit&_fields=$mediaFields" $headers
$snapshot=[ordered]@{captured_utc=(Get-Date).ToUniversalTime().ToString('o');site='https://glasfaser-kompass.de';read_only=$true;page_count=$pageSet.reported_total;post_count=$postSet.reported_total;media_count=$mediaSet.reported_total;page_api_pages=$pageSet.reported_pages;post_api_pages=$postSet.reported_pages;media_api_pages=$mediaSet.reported_pages;pages=$pageSet.items;posts=$postSet.items;media=$mediaSet.items}
if($snapshot.pages.Count-ne$snapshot.page_count-or$snapshot.posts.Count-ne$snapshot.post_count-or$snapshot.media.Count-ne$snapshot.media_count){throw 'Final snapshot completeness assertion failed'}
$path=Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-snapshot.json';[IO.File]::WriteAllText($path,($snapshot|ConvertTo-Json -Depth 60),(New-Object Text.UTF8Encoding($false)))
$manifest=[ordered]@{captured_utc=$snapshot.captured_utc;page_count=$snapshot.page_count;post_count=$snapshot.post_count;media_count=$snapshot.media_count;page_api_pages=$snapshot.page_api_pages;post_api_pages=$snapshot.post_api_pages;media_api_pages=$snapshot.media_api_pages;snapshot='bridge/gk-offline-snapshot.json';status='SNAPSHOT_COMPLETE_NO_WRITES_TOTALS_VERIFIED'}
[IO.File]::WriteAllText((Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-snapshot-manifest.json'),($manifest|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
Write-Host "Verified read-only snapshot: pages=$($snapshot.page_count), posts=$($snapshot.post_count), media=$($snapshot.media_count)"