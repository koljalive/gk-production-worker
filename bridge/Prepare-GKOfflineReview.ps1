Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$snapshot=Get-Content (Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-snapshot.json') -Encoding UTF8 -Raw|ConvertFrom-Json
$report=Get-Content (Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-quality-report.json') -Encoding UTF8 -Raw|ConvertFrom-Json
function Plain([string]$Html){if([string]::IsNullOrWhiteSpace($Html)){return ''};$s=[regex]::Replace($Html,'(?is)<script\b.*?</script>|<style\b.*?</style>',' ');$s=[regex]::Replace($s,'<[^>]+>',' ');$s=[Net.WebUtility]::HtmlDecode($s);[regex]::Replace($s,'\s+',' ').Trim()}
$items=@();foreach($x in $snapshot.pages){$items+=$x};foreach($x in $snapshot.posts){$items+=$x}
$editorial=@()
foreach($x in $items){$title=Plain([string]$x.title.rendered);$slug=[string]$x.slug;$plain=Plain([string]$x.content.raw);$words=$(if([string]::IsNullOrWhiteSpace($plain)){0}else{($plain-split'\s+').Count});$topic=($title+' '+$slug)
 $kind='guide';$minimum=650;$benefit=5
 if($topic-match'(?i)erklärt|erklaert|lexikon|was ist'){$kind='glossary';$minimum=300;$benefit=3}
 elseif($topic-match'(?i)kauf|vergleich|beste|router|tarif|kosten|lohnt'){$kind='commercial';$minimum=900;$benefit=8}
 elseif($topic-match'(?i)störung|stoerung|problem|prüfen|pruefen|fehler|ausfall|abbr'){$kind='troubleshooting';$minimum=800;$benefit=7}
 elseif([string]$x.type-eq'page'){$kind='hub';$minimum=550;$benefit=6}
 if($words-lt$minimum){$gap=$minimum-$words;$cost=[math]::Max(1,[math]::Ceiling($gap/300));$editorial+=[ordered]@{id=[int]$x.id;type=[string]$x.type;title=$title;slug=$slug;url=[string]$x.link;kind=$kind;words=$words;context_minimum=$minimum;word_gap=$gap;benefit=$benefit;cost=$cost;roi=[math]::Round($benefit/$cost,2);source_modified=[string]$x.modified}}
}
$editorial=@($editorial|Sort-Object @{Expression='roi';Descending=$true},@{Expression='benefit';Descending=$true},@{Expression='word_gap';Descending=$false})
$photos=@()
foreach($m in $snapshot.media){$meta=Plain([string]$m.title.rendered+' '+[string]$m.alt_text+' '+[string]$m.caption.rendered+' '+[string]$m.description.rendered+' '+[string]$m.source_url);$mime=[string]$m.mime_type
 if($mime-match'^image/(jpeg|webp)$'-and$meta-match'(?i)reales foto|real photo|fotografie|photo'-and$meta-notmatch'(?i)exec-|schematic|diagramm|illustration'){
  $topics=@();foreach($pair in @(@('dsl','dsl|kupfer|tae|apl|endleitung'),@('fiber','glasfaser|ftth|ont|gf-ta|splei|muffe|nvt'),@('wifi','wlan|wifi|access point|router|repeater|mesh'),@('installation','techniker|monteur|installation|hausanschluss|bohrung'))){if($meta-match$pair[1]){$topics+=$pair[0]}}
  $photos+=[ordered]@{id=[int]$m.id;title=Plain([string]$m.title.rendered);alt=[string]$m.alt_text;source_url=[string]$m.source_url;mime=$mime;topics=$topics;metadata=$meta}
 }
}
$out=[ordered]@{generated_utc=(Get-Date).ToUniversalTime().ToString('o');source_snapshot_utc=[string]$snapshot.captured_utc;offline_only=$true;production_writes=0;content_total=$items.Count;contextual_editorial_count=$editorial.Count;real_photo_candidate_count=$photos.Count;editorial_queue=$editorial;real_photo_candidates=$photos;status='OFFLINE_REVIEW_PREPARED'}
[IO.File]::WriteAllText((Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-review.json'),($out|ConvertTo-Json -Depth 25),(New-Object Text.UTF8Encoding($false)))
$manifest=[ordered]@{generated_utc=$out.generated_utc;source_snapshot_utc=$out.source_snapshot_utc;offline_only=$true;production_writes=0;content_total=$out.content_total;contextual_editorial_count=$out.contextual_editorial_count;real_photo_candidate_count=$out.real_photo_candidate_count;status=$out.status}
[IO.File]::WriteAllText((Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-review-manifest.json'),($manifest|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
Write-Host "Offline review prepared: editorial=$($editorial.Count), photos=$($photos.Count), writes=0"