param([switch]$Simulation)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Get-PlainSecret([string]$Path){$s=Get-Content $Path|ConvertTo-SecureString;$p=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s);try{[Runtime.InteropServices.Marshal]::PtrToStringBSTR($p)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p)}}
function Parse-Utf8($Response){$text=[Text.Encoding]::UTF8.GetString($Response.RawContentStream.ToArray());ConvertFrom-Json $text}
function Invoke-Wp([string]$Method,[string]$Path,[hashtable]$Headers,[object]$Body=$null){$p=@{Uri=('https://glasfaser-kompass.de/wp-json'+$Path);Method=$Method;Headers=$Headers;UseBasicParsing=$true;TimeoutSec=180};if($null-ne$Body){$j=$Body|ConvertTo-Json -Depth 20 -Compress;$p.Body=[Text.Encoding]::UTF8.GetBytes($j);$p.ContentType='application/json; charset=utf-8'};Parse-Utf8(Invoke-WebRequest @p)}
function Find-Chrome(){foreach($x in @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe","$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")){if($x-and(Test-Path $x)){return $x}};$null}
$workspace=$env:GITHUB_WORKSPACE;$pilot=Get-Content(Join-Path $workspace 'bridge/gk-offline-pilot.json') -Encoding UTF8 -Raw|ConvertFrom-Json
if($pilot.status-ne'OFFLINE_PILOT_FULL_SIMULATION_PASSED'){throw 'Pilot gate failed'}
$css=@'
<style class="gk-nav-fix">.gk-clean-article .gk-design-toc{display:flex;flex-wrap:wrap;gap:10px;margin:22px 0}.gk-clean-article .gk-design-toc a{display:inline-flex;padding:9px 13px;border:1px solid #b9d8e8;border-radius:999px;text-decoration:none;font-weight:700;background:#f7fbfd}.gk-clean-article table{display:block;max-width:100%;overflow-x:auto}@media(max-width:600px){.gk-clean-article .gk-design-toc{gap:8px}.gk-clean-article .gk-design-toc a{padding:8px 11px;font-size:.92rem}}</style>
'@
$plans=@();foreach($id in 298,163){$t=$pilot.targets|Where-Object{[int]$_.id-eq$id};if($null-eq$t){throw "Pilot target missing $id"};$plans+=@([ordered]@{id=$id;route="/wp/v2/posts/$id";expected=[string]$t.content;new=([string]$t.content+$css)})}
if($Simulation){foreach($p in $plans){if(-not$p.new.Contains('gk-nav-fix')-or$p.new-match'<h1\b|<img\b'){throw 'Simulation quality gate failed'}};Write-Host 'VISUAL POLISH SIMULATION PASSED';exit 0}
$secretDir=Join-Path $env:APPDATA 'GK-MCP-Tunnel';$user=(Get-Content(Join-Path $secretDir 'wp-user.txt')-Raw).Trim();$pass=Get-PlainSecret(Join-Path $secretDir 'wp-password.dat');try{$basic=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($user+':'+$pass))}finally{Remove-Variable pass -ErrorAction SilentlyContinue};$headers=@{Authorization="Basic $basic";Accept='application/json'};Remove-Variable basic -ErrorAction SilentlyContinue
$backups=@();foreach($p in $plans){$x=Invoke-Wp GET ($p.route+'?context=edit&_fields=id,link,content,featured_media') $headers;$raw=[string]$x.content.raw;if($raw-ne$p.expected-and$raw-ne$p.new){throw "Source content changed $($p.id)"};$backups+=@([ordered]@{id=$p.id;route=$p.route;link=[string]$x.link;content=$raw;featured_media=[int]$x.featured_media});$p.link=[string]$x.link}
[IO.File]::WriteAllText((Join-Path $workspace 'bridge/gk-live-polish-backup.json'),($backups|ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
$written=@();$result=[ordered]@{started_utc=(Get-Date).ToUniversalTime().ToString('o');status='RUNNING';targets=@();screenshots=@();rollback=@()}
try{
 foreach($p in $plans){if($backups|Where-Object{$_.id-eq$p.id}|ForEach-Object{$_.content-ne$p.new}){Invoke-Wp POST $p.route $headers ([ordered]@{content=$p.new;featured_media=0})|Out-Null;$written+=@($p.id)};$v=Invoke-Wp GET ($p.route+'?context=edit&_fields=id,content') $headers;if([string]$v.content.raw-ne$p.new){throw "Post-write mismatch $($p.id)"};$result.targets+=@([ordered]@{id=$p.id;url=$p.link;accepted=$true})}
 $chrome=Find-Chrome;if($null-eq$chrome){throw 'Chrome missing'}
 $urls=@([ordered]@{id=21005;url='https://glasfaser-kompass.de/dsl-kupfer/'})+@($result.targets)
 Add-Type -AssemblyName System.Drawing
 foreach($x in $urls){foreach($v in @(@{n='desktop';s='1440,1200';w=1440;h=1200},@{n='mobile';s='390,844';w=390;h=844})){$path=Join-Path $workspace ("bridge/final-$($x.id)-$($v.n).png");$args=@('--headless=new','--disable-gpu','--hide-scrollbars',("--window-size="+$v.s),("--screenshot="+$path),$x.url);&$chrome @args|Out-Null;if(-not(Test-Path $path)){throw "Screenshot missing $($x.id)"};$img=[Drawing.Image]::FromFile($path);try{if($img.Width-ne$v.w-or$img.Height-ne$v.h){throw "Screenshot dimensions wrong $($x.id) $($v.n): $($img.Width)x$($img.Height)"}}finally{$img.Dispose()};$result.screenshots+=@([ordered]@{id=$x.id;viewport=$v.n;width=$v.w;height=$v.h;path=(Split-Path $path -Leaf)})}}
 $result.status='VISUAL_POLISH_AND_EXACT_VIEWPORT_EVIDENCE_READY'
}catch{$failure=$_.Exception.Message;foreach($id in $written){$b=$backups|Where-Object{$_.id-eq$id};try{Invoke-Wp POST ([string]$b.route) $headers ([ordered]@{content=[string]$b.content;featured_media=[int]$b.featured_media})|Out-Null;$result.rollback+=@([ordered]@{id=$id;ok=$true})}catch{$result.rollback+=@([ordered]@{id=$id;ok=$false})}};$result.status='FAILED_AND_ROLLBACK_ATTEMPTED';$result.failure=$failure;[IO.File]::WriteAllText((Join-Path $workspace 'bridge/gk-live-polish-result.json'),($result|ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)));throw}
[IO.File]::WriteAllText((Join-Path $workspace 'bridge/gk-live-polish-result.json'),($result|ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)));Write-Host 'Visual polish complete with exact viewport evidence.'

