Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$review=Get-Content(Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-review.json')-Raw|ConvertFrom-Json
$dir=Join-Path $env:GITHUB_WORKSPACE 'bridge/offline-media-review';New-Item -ItemType Directory -Force -Path $dir|Out-Null
$items=@()
foreach($m in $review.real_photo_candidates){$ext=$(if ([string]$m.mime -eq 'image/webp') { '.webp' } else { '.jpg' });$path=Join-Path $dir([string]$m.id+$ext);Invoke-WebRequest -Uri ([string]$m.source_url) -OutFile $path -UseBasicParsing -TimeoutSec 180;if (-not (Test-Path $path)){throw "Media download missing $($m.id)"};$file=Get-Item $path;if ($file.Length -lt 1024){throw "Media file too small $($m.id) bytes=$($file.Length)"};$hash=(Get-FileHash $path -Algorithm SHA256).Hash;$items+=[ordered]@{id=[int]$m.id;title=[string]$m.title;alt=[string]$m.alt;source_url=[string]$m.source_url;local_path="bridge/offline-media-review/$($m.id)$ext";bytes=$file.Length;sha256=$hash;topics=$m.topics}}
if ($items.Count -ne [int]$review.real_photo_candidate_count){throw "Media review count mismatch expected=$($review.real_photo_candidate_count) actual=$($items.Count)"}
$out=[ordered]@{generated_utc=(Get-Date).ToUniversalTime().ToString('o');offline_only=$true;production_writes=0;candidate_count=$items.Count;items=$items;status='OFFLINE_MEDIA_READY_FOR_VISUAL_REVIEW'}
[IO.File]::WriteAllText((Join-Path $dir 'manifest.json'),($out|ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
Write-Host "Offline media ready: $($items.Count) files, writes=0"