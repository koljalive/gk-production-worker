Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$s=Get-Content (Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-snapshot.json') -Encoding UTF8 -Raw|ConvertFrom-Json
function Plain([string]$Html){if([string]::IsNullOrWhiteSpace($Html)){return ''};$x=[regex]::Replace($Html,'<[^>]+>',' ');[regex]::Replace([Net.WebUtility]::HtmlDecode($x),'\s+',' ').Trim()}
function Key([string]$Slug){$k=$Slug.ToLowerInvariant();$k=[regex]::Replace($k,'-(voll|2|neu|aktuell)$','');$k=[regex]::Replace($k,'-(erklaert|erklärt)$','');$k=[regex]::Replace($k,'[^a-z0-9äöüß]+','-');$k.Trim('-')}
$items=@();foreach($x in $s.pages){$items+=$x};foreach($x in $s.posts){$items+=$x}
$rows=@();foreach($x in $items){$plain=Plain([string]$x.content.raw);$words=$(if($plain){($plain-split'\s+').Count}else{0});$rows+=[pscustomobject][ordered]@{id=[int]$x.id;type=[string]$x.type;title=Plain([string]$x.title.rendered);slug=[string]$x.slug;key=Key([string]$x.slug);url=[string]$x.link;words=$words;modified=[string]$x.modified}}
$groups=@($rows|Group-Object key|Where-Object{$_.Count-gt1})
$pairs=@()
foreach($g in $groups){$sorted=@($g.Group|Sort-Object @{Expression='words';Descending=$true},@{Expression='modified';Descending=$true});$canonical=$sorted[0];foreach($dup in @($sorted|Select-Object -Skip 1)){$ratio=$(if($canonical.words){[math]::Round($dup.words/$canonical.words,2)}else{1});$confidence=$(if($ratio-lt0.75){'high'}else{'review'});$pairs+=[ordered]@{key=$g.Name;canonical=$canonical;duplicate=$dup;word_ratio=$ratio;confidence=$confidence;recommended_action=$(if($confidence-eq'high'){'merge_unique_value_then_301_redirect'}else{'manual_overlap_review'})}}}
$pairs=@($pairs|Sort-Object @{Expression={if($_.confidence-eq'high'){1}else{0}};Descending=$true},@{Expression={$_.canonical.words-$_.duplicate.words};Descending=$true})
$out=[ordered]@{generated_utc=(Get-Date).ToUniversalTime().ToString('o');offline_only=$true;production_writes=0;content_total=$rows.Count;duplicate_group_count=$groups.Count;pair_count=$pairs.Count;high_confidence_count=@($pairs|Where-Object{$_.confidence-eq'high'}).Count;pairs=$pairs;status='OFFLINE_DEDUPLICATION_COMPLETE'}
[IO.File]::WriteAllText((Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-deduplication.json'),($out|ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
$manifest=[ordered]@{generated_utc=$out.generated_utc;offline_only=$true;production_writes=0;content_total=$out.content_total;duplicate_group_count=$out.duplicate_group_count;pair_count=$out.pair_count;high_confidence_count=$out.high_confidence_count;status=$out.status}
[IO.File]::WriteAllText((Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-deduplication-manifest.json'),($manifest|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
Write-Host "Offline dedup complete: groups=$($groups.Count), pairs=$($pairs.Count), high=$($out.high_confidence_count), writes=0"