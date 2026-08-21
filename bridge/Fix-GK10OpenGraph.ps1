Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-PlainSecret([string]$Path){$s=Get-Content $Path|ConvertTo-SecureString;$p=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s);try{[Runtime.InteropServices.Marshal]::PtrToStringBSTR($p)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p)}}
function Invoke-Wp([string]$Path,[string]$Method,[hashtable]$Headers,[object]$Body=$null){$u='https://glasfaser-kompass.de/wp-json'+$Path;$args=@{Uri=$u;Method=$Method;Headers=$Headers;UseBasicParsing=$true;TimeoutSec=180};if($null-ne$Body){$args.Body=($Body|ConvertTo-Json -Depth 8 -Compress);$args.ContentType='application/json'};$r=Invoke-WebRequest @args;return ($r.Content|ConvertFrom-Json)}
function Pick-Media([string]$Title,[string]$Url){$s=("$Title $Url").ToLowerInvariant();if($s -match 'wlan|wifi|mesh|repeater|access.?point'){return 29403};if($s -match 'router|fritz|speedport'){return 29397};if($s -match 'splei|techniker|telekom-readiness|muffe'){return 29398};return 29401}

$root=$env:GITHUB_WORKSPACE
$auditPath=Join-Path $root 'bridge/gk10-full-result.json'
if(-not(Test-Path $auditPath)){throw 'gk10-full-result.json fehlt'}
$audit=Get-Content $auditPath -Raw | ConvertFrom-Json
$secretDir=Join-Path $env:APPDATA 'GK-MCP-Tunnel';$user=(Get-Content (Join-Path $secretDir 'wp-user.txt') -Raw).Trim();$pass=Get-PlainSecret (Join-Path $secretDir 'wp-password.dat');try{$basic=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$user`:$pass"))}finally{Remove-Variable pass -ErrorAction SilentlyContinue};$headers=@{Authorization="Basic $basic";Accept='application/json'};Remove-Variable basic -ErrorAction SilentlyContinue

$backup=@();$changes=@();$verify=@();$targets=@($audit.results|Where-Object{($_.issues -contains 'og_image_missing') -or ($_.suspicious_images -gt 0)})
foreach($r in $targets){
  $endpoint=if($r.type -eq 'post'){'posts'}else{'pages'}
  $current=Invoke-Wp "/wp/v2/$endpoint/$($r.id)?context=edit&_fields=id,featured_media,modified,title,link" 'GET' $headers
  $backup += [pscustomobject]@{id=$r.id;type=$endpoint;featured_media=$current.featured_media;modified=$current.modified;url=$current.link}
  $chosen=[int]$current.featured_media
  if($chosen -le 0 -or $r.suspicious_images -gt 0){$chosen=Pick-Media ([string]$r.title) ([string]$r.url)}
  $u=Invoke-Wp "/wp/v2/$endpoint/$($r.id)" 'POST' $headers @{featured_media=$chosen}
  $changes += [pscustomobject]@{id=$r.id;type=$endpoint;before=[int]$current.featured_media;after=[int]$u.featured_media;url=$r.url}
  Start-Sleep -Milliseconds 150
  try{$pub=Invoke-WebRequest -Uri ($r.url+'?gkog='+[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) -UseBasicParsing -TimeoutSec 60;$html=[string]$pub.Content;$og=($html -match 'property=["'']og:image["'']');$h1=([regex]::Matches($html,'<h1\b','IgnoreCase')).Count;$verify += [pscustomobject]@{id=$r.id;http=[int]$pub.StatusCode;og_image=$og;h1_count=$h1}}catch{$verify += [pscustomobject]@{id=$r.id;http=$null;og_image=$false;h1_count=$null;error=$_.Exception.Message}}
}
$out=[ordered]@{started_utc=(Get-Date).ToUniversalTime().ToString('o');target_count=$targets.Count;change_count=$changes.Count;verified_og_count=@($verify|Where-Object og_image).Count;failed_og_count=@($verify|Where-Object{-not $_.og_image}).Count;changes=$changes;verification=$verify;finished_utc=(Get-Date).ToUniversalTime().ToString('o')}
[IO.File]::WriteAllText((Join-Path $root 'bridge/gk10-og-backup.json'),($backup|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $root 'bridge/gk10-og-fix-result.json'),($out|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
Write-Host "GK10 OG repair complete: targets=$($targets.Count), verified=$($out.verified_og_count), failed=$($out.failed_og_count)"
