param([string]$EnvFile='.\.env')
$ErrorActionPreference='Stop'
$v=@{}; Get-Content $EnvFile|Where-Object{$_-match'^[^#].*='}|ForEach-Object{$p=$_-split'=',2;$v[$p[0].Trim()]=$p[1].Trim()}
foreach($n in @('GK_SITE_URL','GK_CONTROL_TOKEN','GK_UNIFIED_API_TOKEN')){if([string]::IsNullOrWhiteSpace($v[$n])){throw "$n fehlt."}}
$site=$v.GK_SITE_URL.TrimEnd('/'); $control=@{Authorization='Bearer '+$v.GK_CONTROL_TOKEN}; $unified=@{Authorization='Bearer '+$v.GK_UNIFIED_API_TOKEN}
function New-Svg([string]$title,[string]$subtitle,[string]$kind){
 $drawing=switch($kind){
  'router' {'<rect x="405" y="255" width="390" height="170" rx="28" fill="#e8f7fb" stroke="#0b3558" stroke-width="8"/><circle cx="490" cy="365" r="12" fill="#36a852"/><circle cx="535" cy="365" r="12" fill="#36a852"/><path d="M510 255V175M690 255V175" stroke="#0b3558" stroke-width="10" stroke-linecap="round"/><path d="M435 225a105 105 0 01150 0M615 225a105 105 0 01150 0" fill="none" stroke="#00a6c8" stroke-width="14" stroke-linecap="round"/><rect x="610" y="340" width="120" height="34" rx="8" fill="#0b3558"/>'}
  'fiber' {'<path d="M160 325H430" stroke="#f4c542" stroke-width="24"/><rect x="430" y="235" width="340" height="180" rx="25" fill="#e8f7fb" stroke="#0b3558" stroke-width="8"/><circle cx="525" cy="325" r="34" fill="#00a6c8"/><circle cx="675" cy="325" r="34" fill="#00a6c8"/><path d="M559 325H641" stroke="#0b3558" stroke-width="12"/><path d="M770 325H1040" stroke="#f4c542" stroke-width="24"/>'}
  'practice' {'<rect x="180" y="205" width="390" height="270" rx="24" fill="#e8f7fb" stroke="#0b3558" stroke-width="8"/><path d="M245 285l28 28 62-76M245 385l28 28 62-76" fill="none" stroke="#00a6c8" stroke-width="12"/><path d="M365 275H505M365 375H505" stroke="#0b3558" stroke-width="8"/><circle cx="800" cy="275" r="75" fill="#fff" stroke="#0b3558" stroke-width="9"/><path d="M853 328l120 120" stroke="#0b3558" stroke-width="22"/><path d="M755 275h90" stroke="#c87818" stroke-width="14"/>'}
 }
 return '<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630" role="img"><rect width="1200" height="630" fill="#f4f8fb"/><rect x="45" y="45" width="1110" height="540" rx="28" fill="#fff" stroke="#0b3558" stroke-width="4"/><text x="85" y="115" font-family="Arial,sans-serif" font-size="42" font-weight="700" fill="#0b3558">'+$title+'</text><text x="85" y="158" font-family="Arial,sans-serif" font-size="24" fill="#34556f">'+$subtitle+'</text>'+$drawing+'</svg>'
}
$groups=@(
 @{key='router-kaufberatung';title='Router-Kaufberatung';sub='Anschlussart, Ausstattung und Heimnetz passend wählen';kind='router';alt='Schematischer Router mit WLAN-Signal und Anschlussanzeigen.';ids=@(21020,21021,21043,21053)},
 @{key='glasfaser-hardware';title='Glasfaser-Hardware';sub='Netzabschluss, Faser und Router sauber unterscheiden';kind='fiber';alt='Schematische Glasfaser-Komponenten und optische Verbindung.';ids=@(21022)},
 @{key='techniker-praxis';title='Praxiswissen vom Techniker';sub='Prüfen, messen und den nächsten Schritt ableiten';kind='practice';alt='Schematische Checkliste und Messlupe für die technische Praxis.';ids=@(20001)}
)
$root=Split-Path -Parent $PSScriptRoot; $backup=Join-Path $root('backups\final-media-'+(Get-Date -Format 'yyyyMMdd-HHmmss')); New-Item $backup -ItemType Directory -Force|Out-Null; $rows=@()
foreach($g in $groups){
 $filename='gk-'+$g.key+'.svg'; $found=@(Invoke-RestMethod($site+'/wp-json/wp/v2/media?search='+$g.key+'&per_page=20&_fields=id,source_url,date')-TimeoutSec 30|Where-Object{$_.source_url-match[regex]::Escape($filename)}|Sort-Object date -Descending)
 if($found.Count){$attachment=[long]$found[0].id}else{$payload=@{filename=$filename;title=$g.title;alt=$g.alt;svg=(New-Svg $g.title $g.sub $g.kind)}|ConvertTo-Json -Compress;$up=Invoke-RestMethod ($site+'/wp-json/gk-control/v1/media/upload-svg') -Method Post -Headers $control -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($payload));$attachment=[long]$(if($up.attachment_id){$up.attachment_id}elseif($up.media_id){$up.media_id}else{$up.id})}
 if($attachment-le 0){throw "Upload ohne Medien-ID: $($g.key)"}
 foreach($id in $g.ids){$before=Invoke-RestMethod ($site+"/wp-json/wp/v2/pages/$id`?_fields=id,featured_media") -TimeoutSec 30;$old=[long]$before.featured_media;if($old-ne$attachment){$rows+=[pscustomobject]@{id=$id;old=$old;new=$attachment};$set=@{post_id=$id;attachment_id=$attachment}|ConvertTo-Json -Compress;Invoke-RestMethod ($site+'/wp-json/gk-control/v1/media/set-featured') -Method Post -Headers $control -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($set))|Out-Null};$check=Invoke-RestMethod ($site+"/wp-json/wp/v2/pages/$id`?_fields=id,featured_media&_gk="+(Get-Date -Format HHmmssfff)) -TimeoutSec 30;if([long]$check.featured_media-ne$attachment){throw "Zuweisung nicht verifiziert: $id"};Write-Host("${id}: VERIFIED | Attachment=$attachment")}
}
$rows|Export-Csv (Join-Path $backup 'backup.csv') -NoTypeInformation -Encoding UTF8
$cache=Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/clear-cache') -Method Post -Headers $unified -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('{}'));if($cache.cache_cleared-ne$true){throw 'Cache nicht geleert.'}
Write-Host('FERTIG: Seiten=6 | Verifiziert=6 | Backup='+$backup)
