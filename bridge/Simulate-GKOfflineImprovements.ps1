Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$snapshot=Get-Content(Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-snapshot.json')-Raw|ConvertFrom-Json
$report=Get-Content(Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-quality-report.json')-Raw|ConvertFrom-Json
$items=@();foreach($x in $snapshot.pages){$items+=$x};foreach($x in $snapshot.posts){$items+=$x}
$proposals=@();$changed=0
foreach($x in $items){
 $raw=[string]$x.content.raw;$sim=$raw;$actions=@()
 $topic=([string]$x.title.rendered+' '+[string]$x.slug).ToLowerInvariant()
 if($topic-match'dsl|kupfer'){
  $next=[regex]::Replace($sim,'(?is)<!--\s*wp:image\b.*?glasfaser-spleissmuffe.*?<!--\s*\/wp:image\s*-->','')
  $next=[regex]::Replace($next,'(?is)<figure\b[^>]*>.*?glasfaser-spleissmuffe.*?</figure>','')
  if($next-ne$sim){$sim=$next;$actions+='remove_semantically_wrong_dsl_image'}
 }
 $next=[regex]::Replace($sim,'(?is)<!--\s*wp:image\b.*?(?:\.svg|exec-|schematic|diagramm|illustration).*?<!--\s*\/wp:image\s*-->','')
 $next=[regex]::Replace($next,'(?is)<figure\b[^>]*>.*?(?:\.svg|exec-|schematic|diagramm|illustration).*?</figure>','')
 if($next-ne$sim){$removed=([regex]::Matches($sim,'(?i)\.svg|exec-|schematic|diagramm|illustration')).Count-([regex]::Matches($next,'(?i)\.svg|exec-|schematic|diagramm|illustration')).Count;$sim=$next;$actions+="remove_schematic_image_markup_$removed"}
 if(([regex]::Matches($sim,'<h1\b','IgnoreCase')).Count-gt0){$sim=[regex]::Replace($sim,'(?i)<h1\b([^>]*)>','<h2$1>');$sim=[regex]::Replace($sim,'(?i)</h1>','</h2>');$actions+='demote_content_h1_to_h2'}
 if($actions.Count-gt0){$changed++;$proposals+=[ordered]@{id=[int]$x.id;type=[string]$x.type;title=[string]$x.title.rendered;slug=[string]$x.slug;url=[string]$x.link;source_modified=[string]$x.modified;source_featured_media=[int]$x.featured_media;actions=$actions;before_length=$raw.Length;after_length=$sim.Length;simulated_content=$sim}}
}
$manual=@($report.all_results|Where-Object{$_.issues-contains'thin_content'-or$_.issues-contains'weak_structure'-or$_.issues-contains'weak_internal_links'-or$_.issues-contains'missing_cta'}|Sort-Object @{Expression='roi';Descending=$true},@{Expression='benefit';Descending=$true})
$mediaCatalog=@()
foreach($m in $snapshot.media){$meta=([string]$m.title.rendered+' '+[string]$m.alt_text+' '+[string]$m.caption.rendered+' '+[string]$m.description.rendered+' '+[string]$m.source_url);$mediaCatalog+=[ordered]@{id=[int]$m.id;title=[string]$m.title.rendered;alt=[string]$m.alt_text;mime=[string]$m.mime_type;source_url=[string]$m.source_url;real_photo_hint=($meta-match'(?i)reales foto|real photo|fotografie|photo');forbidden_automation_hint=($meta-match'(?i)exec-|\.svg|schematic|diagramm|illustration')}}
$simulation=[ordered]@{generated_utc=(Get-Date).ToUniversalTime().ToString('o');source_snapshot_utc=[string]$snapshot.captured_utc;offline_only=$true;production_writes=0;content_total=$items.Count;automatic_proposal_count=$proposals.Count;manual_editorial_count=$manual.Count;automatic_proposals=$proposals;manual_editorial_queue=$manual;media_catalog=$mediaCatalog}
[IO.File]::WriteAllText((Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-simulation.json'),($simulation|ConvertTo-Json -Depth 40),(New-Object Text.UTF8Encoding($false)))
$manifest=[ordered]@{generated_utc=$simulation.generated_utc;source_snapshot_utc=$simulation.source_snapshot_utc;offline_only=$true;production_writes=0;content_total=$simulation.content_total;automatic_proposal_count=$simulation.automatic_proposal_count;manual_editorial_count=$simulation.manual_editorial_count;status='OFFLINE_SIMULATION_COMPLETE'}
[IO.File]::WriteAllText((Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-simulation-manifest.json'),($manifest|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
Write-Host "Offline simulation complete: automatic=$($proposals.Count), editorial=$($manual.Count), writes=0"