Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$snapshotPath=Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-snapshot.json'
if(-not(Test-Path $snapshotPath)){throw 'Offline snapshot missing'}
$snapshot=Get-Content $snapshotPath -Encoding UTF8 -Raw|ConvertFrom-Json
$items=@();foreach($x in $snapshot.pages){$items+=$x};foreach($x in $snapshot.posts){$items+=$x}
if($items.Count-ne([int]$snapshot.page_count+[int]$snapshot.post_count)){throw "Snapshot count mismatch expected=$([int]$snapshot.page_count+[int]$snapshot.post_count) actual=$($items.Count)"}
function Plain([string]$Html){if([string]::IsNullOrWhiteSpace($Html)){return ''};$s=[regex]::Replace($Html,'(?is)<script\b.*?</script>|<style\b.*?</style>',' ');$s=[regex]::Replace($s,'<[^>]+>',' ');$s=[Net.WebUtility]::HtmlDecode($s);[regex]::Replace($s,'\s+',' ').Trim()}
$results=@()
foreach($x in $items){
 $raw=[string]$x.content.raw;$plain=Plain $raw;$words=$(if([string]::IsNullOrWhiteSpace($plain)){0}else{($plain-split'\s+').Count})
 $h1=([regex]::Matches($raw,'<h1\b','IgnoreCase')).Count;$h2=([regex]::Matches($raw,'<h2\b','IgnoreCase')).Count
 $imgs=@([regex]::Matches($raw,'(?i)<img\b[^>]*src=["'']([^"'']+)')|ForEach-Object{$_.Groups[1].Value})
 $bad=@($imgs|Where-Object{$_-match'(?i)\.svg(?:\?|$)|exec-|schematic|diagramm|illustration'})
 $links=@([regex]::Matches($raw,'(?i)<a\b[^>]*href=["'']([^"'']+)')|ForEach-Object{$_.Groups[1].Value})
 $internal=@($links|Where-Object{$_.StartsWith('/')-or$_-match'glasfaser-kompass\.de'}).Count
 $title=Plain([string]$x.title.rendered);$topic=($title+' '+[string]$x.slug)
 $issues=@()
 if($words-lt450){$issues+='thin_content'}
 if($h1-gt0){$issues+="content_h1_$h1"}
 if($words-gt700-and$h2-lt2){$issues+='weak_structure'}
 if($bad.Count-gt0){$issues+="schematic_images_$($bad.Count)"}
 if(($imgs-join' ')-match'(?i)glasfaser-spleissmuffe'-and$topic-match'(?i)dsl|kupfer'){$issues+='wrong_dsl_image'}
 if($internal-lt2){$issues+='weak_internal_links'}
 if($topic-match'(?i)kauf|vergleich|router|tarif'-and$plain-notmatch'(?i)jetzt|prüfen|vergleichen|kaufen|angebot|tarif|mehr erfahren|zur kaufberatung'){$issues+='missing_cta'}
 $benefit=0;$cost=1
 foreach($issue in $issues){if($issue-eq'wrong_dsl_image'){$benefit+=10}elseif($issue-match'^content_h1'){$benefit+=7}elseif($issue-match'^schematic_images'){$benefit+=6}elseif($issue-eq'missing_cta'){$benefit+=5}elseif($issue-eq'thin_content'){$benefit+=4}else{$benefit+=2}}
 if($words-gt1800){$cost++};if($bad.Count-gt2){$cost+=2}
 $results+=[ordered]@{id=[int]$x.id;type=[string]$x.type;title=$title;slug=[string]$x.slug;url=[string]$x.link;modified=[string]$x.modified;featured_media=[int]$x.featured_media;words=$words;content_h1=$h1;h2=$h2;image_count=$imgs.Count;suspicious_images=$bad.Count;internal_links=$internal;issue_count=$issues.Count;issues=$issues;benefit=$benefit;cost=$cost;roi=$(if($cost){[math]::Round($benefit/$cost,2)}else{0})}
}
$issueTotals=[ordered]@{};foreach($r in $results){foreach($i in $r.issues){$key=[regex]::Replace([string]$i,'_\d+$','');if(-not$issueTotals.Contains($key)){$issueTotals[$key]=0};$issueTotals[$key]++}}
$priority=@($results|Where-Object{$_.issue_count-gt0}|Sort-Object @{Expression='roi';Descending=$true},@{Expression='benefit';Descending=$true},@{Expression='id';Descending=$false})
$report=[ordered]@{generated_utc=(Get-Date).ToUniversalTime().ToString('o');source_snapshot_utc=[string]$snapshot.captured_utc;offline_only=$true;production_writes=0;content_count=$results.Count;media_count=[int]$snapshot.media_count;needs_work=@($results|Where-Object{$_.issue_count-gt0}).Count;issue_totals=$issueTotals;priority=$priority;all_results=$results}
$out=Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-quality-report.json';[IO.File]::WriteAllText($out,($report|ConvertTo-Json -Depth 30),(New-Object Text.UTF8Encoding($false)))
$manifest=[ordered]@{generated_utc=$report.generated_utc;source_snapshot_utc=$report.source_snapshot_utc;offline_only=$true;production_writes=0;content_count=$report.content_count;media_count=$report.media_count;needs_work=$report.needs_work;report='bridge/gk-offline-quality-report.json';status='OFFLINE_AUDIT_COMPLETE'}
[IO.File]::WriteAllText((Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-quality-manifest.json'),($manifest|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
Write-Host "Offline audit complete: content=$($report.content_count), needs_work=$($report.needs_work), writes=0"