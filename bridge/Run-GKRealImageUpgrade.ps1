Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-PlainSecret([string]$Path){
  $s=Get-Content $Path|ConvertTo-SecureString
  $p=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  try{[Runtime.InteropServices.Marshal]::PtrToStringBSTR($p)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p)}
}
function Invoke-WpJson([string]$Method,[string]$Path,[hashtable]$Headers,[object]$Body=$null){
  $url='https://glasfaser-kompass.de/wp-json'+$Path
  $p=@{Uri=$url;Method=$Method;Headers=$Headers;UseBasicParsing=$true;TimeoutSec=120}
  if($null-ne$Body){$j=$Body|ConvertTo-Json -Depth 30 -Compress;$p.Body=[Text.Encoding]::UTF8.GetBytes($j);$p.ContentType='application/json; charset=utf-8'}
  $r=Invoke-WebRequest @p
  if([string]::IsNullOrWhiteSpace([string]$r.Content)){return $null}
  return ([string]$r.Content|ConvertFrom-Json)
}
function Find-Media([string]$Search,[hashtable]$Headers){
  for($i=0;$i-lt 30;$i++){
    $q=[Uri]::EscapeDataString($Search)
    $arr=@(Invoke-WpJson 'GET' ("/wp/v2/media?context=edit&per_page=20&search=$q&_fields=id,title,source_url,alt_text,mime_type") $Headers)
    $hit=$arr|Where-Object{[string]$_.title.raw -eq $Search}|Select-Object -First 1
    if($hit){return $hit}
    Start-Sleep -Seconds 10
  }
  throw "Media not found after waiting: $Search"
}
function Set-Featured([int]$PageId,[int]$MediaId,[string]$Label,[hashtable]$Headers,[ref]$Report){
  $before=Invoke-WpJson 'GET' ("/wp/v2/pages/$PageId?context=edit&_fields=id,modified,status,link,title,featured_media") $Headers
  $backupDir='C:\GKBridge\backups';New-Item -ItemType Directory -Force -Path $backupDir|Out-Null
  $stamp=Get-Date -Format 'yyyyMMdd-HHmmss';$backup=Join-Path $backupDir ("page-$PageId-$stamp-before-image.json")
  [IO.File]::WriteAllText($backup,($before|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
  $after=Invoke-WpJson 'POST' ("/wp/v2/pages/$PageId") $Headers ([ordered]@{featured_media=$MediaId})
  $verify=Invoke-WpJson 'GET' ("/wp/v2/pages/$PageId?context=edit&_fields=id,modified,status,link,title,featured_media") $Headers
  if([int]$verify.featured_media-ne$MediaId){throw "Featured-media verification failed on page $PageId"}
  $Report.Value+=@([ordered]@{page_id=$PageId;title=[string]$verify.title.raw;url=[string]$verify.link;old_featured_media=[int]$before.featured_media;new_featured_media=$MediaId;media_label=$Label;backup=$backup;verified=$true})
}

$secretDir=Join-Path $env:APPDATA 'GK-MCP-Tunnel'
$user=(Get-Content (Join-Path $secretDir 'wp-user.txt') -Raw).Trim();$pass=Get-PlainSecret (Join-Path $secretDir 'wp-password.dat')
try{$basic=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$user`:$pass"))}finally{Remove-Variable pass -ErrorAction SilentlyContinue}
$headers=@{Authorization="Basic $basic";Accept='application/json'};Remove-Variable basic -ErrorAction SilentlyContinue

$router=Find-Media 'FRITZ!Box 7590 – reales Routerfoto' $headers
$ftth=Find-Media 'FTTH-Abschluss – reales Foto' $headers
$fiber=Find-Media 'Glasfaser-Bündelrohre vor dem Einbau – reales Foto' $headers
$changes=@()
Set-Featured 21020 ([int]$router.id) 'real-router-photo' $headers ([ref]$changes)
Set-Featured 21003 ([int]$ftth.id) 'real-ftth-photo' $headers ([ref]$changes)
Set-Featured 21004 ([int]$ftth.id) 'real-ftth-photo' $headers ([ref]$changes)
Set-Featured 21022 ([int]$ftth.id) 'real-ftth-photo' $headers ([ref]$changes)
Set-Featured 21066 ([int]$fiber.id) 'real-fiber-installation-photo' $headers ([ref]$changes)

$out=[ordered]@{generated_at_utc=(Get-Date).ToUniversalTime().ToString('o');success=$true;media=[ordered]@{router=$router;ftth=$ftth;fiber=$fiber};changes=$changes}
$path=Join-Path $env:GITHUB_WORKSPACE 'bridge/real-image-upgrade-result.json'
[IO.File]::WriteAllText($path,($out|ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
Write-Host "Real-image upgrade complete: $($changes.Count) verified page changes"
