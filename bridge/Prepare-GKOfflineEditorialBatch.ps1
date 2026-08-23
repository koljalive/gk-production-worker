Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$s=Get-Content (Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-snapshot.json') -Encoding UTF8 -Raw|ConvertFrom-Json
$r=Get-Content (Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-review.json') -Encoding UTF8 -Raw|ConvertFrom-Json
$d=Get-Content (Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-deduplication.json') -Encoding UTF8 -Raw|ConvertFrom-Json
$excluded=@{};foreach($p in $d.pairs){if([string]$p.confidence-eq'high'){$excluded[[string]$p.duplicate.id]=$true}}
$map=@{};foreach($x in $s.pages){$map[[string]$x.id]=$x};foreach($x in $s.posts){$map[[string]$x.id]=$x}
$selected=@($r.editorial_queue|Where-Object{-not$excluded.ContainsKey([string]$_.id)}|Sort-Object @{Expression='roi';Descending=$true},@{Expression='benefit';Descending=$true},@{Expression='word_gap';Descending=$false}|Select-Object -First 20)
$items=@();foreach($q in $selected){$x=$map[[string]$q.id];if($null-eq$x){throw "Snapshot item missing $($q.id)"};$items+=[ordered]@{id=[int]$q.id;type=[string]$q.type;title=[string]$q.title;slug=[string]$q.slug;url=[string]$q.url;kind=[string]$q.kind;words=[int]$q.words;context_minimum=[int]$q.context_minimum;word_gap=[int]$q.word_gap;benefit=[int]$q.benefit;cost=[int]$q.cost;roi=[double]$q.roi;source_modified=[string]$q.source_modified;featured_media=[int]$x.featured_media;content_raw=[string]$x.content.raw;excerpt_raw=[string]$x.excerpt.raw}}
$out=[ordered]@{generated_utc=(Get-Date).ToUniversalTime().ToString('o');source_snapshot_utc=[string]$s.captured_utc;offline_only=$true;production_writes=0;excluded_high_confidence_duplicates=$excluded.Count;batch_count=$items.Count;items=$items;status='OFFLINE_EDITORIAL_BATCH_READY'}
[IO.File]::WriteAllText((Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-editorial-batch.json'),($out|ConvertTo-Json -Depth 30),(New-Object Text.UTF8Encoding($false)))
Write-Host "Offline editorial batch ready: $($items.Count), excluded duplicates=$($excluded.Count), writes=0"