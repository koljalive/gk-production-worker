param([string]$EnvFile='.\.env')
$ErrorActionPreference='Stop'
$v=@{};Get-Content $EnvFile|Where-Object{$_-match'^[^#].*='}|ForEach-Object{$p=$_-split'=',2;$v[$p[0].Trim()]=$p[1].Trim()}
foreach($n in @('GK_SITE_URL','GK_CONTROL_TOKEN','GK_UNIFIED_API_TOKEN')){if([string]::IsNullOrWhiteSpace($v[$n])){throw "$n fehlt."}}
$site=$v.GK_SITE_URL.TrimEnd('/');$control=@{Authorization='Bearer '+$v.GK_CONTROL_TOKEN};$unified=@{Authorization='Bearer '+$v.GK_UNIFIED_API_TOKEN}
$targets=@(
 [pscustomobject]@{id=1002;media=28070;reason='Glasfaser-Grundlagen'},[pscustomobject]@{id=1003;media=28070;reason='Glasfaser-Komponenten'},
 [pscustomobject]@{id=1004;media=28070;reason='Glasfaser-Komponenten'},[pscustomobject]@{id=1005;media=28076;reason='Glasfaser-Hardware'},
 [pscustomobject]@{id=1006;media=26201;reason='APL'},[pscustomobject]@{id=1008;media=28074;reason='WLAN'},
 [pscustomobject]@{id=1009;media=28070;reason='Technik-Lexikon'},[pscustomobject]@{id=21041;media=28074;reason='WLAN-Repeater'},
 [pscustomobject]@{id=21066;media=28073;reason='Internetanbieter'},[pscustomobject]@{id=21967;media=28073;reason='Netz- und Bereitschaftsstatus'},
 [pscustomobject]@{id=21968;media=28073;reason='Netz- und Portalstatus'}
)
$root=Split-Path -Parent $PSScriptRoot;$backup=Join-Path $root('backups\object-visual-fix-'+(Get-Date -Format 'yyyyMMdd-HHmmss'));New-Item $backup -ItemType Directory -Force|Out-Null
$rows=@()
foreach($t in $targets){
 if($t.media-gt0){$m=Invoke-RestMethod($site+"/wp-json/wp/v2/media/$($t.media)?_fields=id,source_url,alt_text")-TimeoutSec 30;if([long]$m.id-ne$t.media-or[string]::IsNullOrWhiteSpace([string]$m.alt_text)){throw "Ungueltiges Zielmedium: $($t.media)"}}
 $kind='pages';try{$before=Invoke-RestMethod($site+"/wp-json/wp/v2/pages/$($t.id)?_fields=id,title,featured_media")-TimeoutSec 30}catch{$kind='posts';$before=Invoke-RestMethod($site+"/wp-json/wp/v2/posts/$($t.id)?_fields=id,title,featured_media")-TimeoutSec 30}
 $old=[long]$before.featured_media;$rows+=[pscustomobject]@{id=$t.id;type=$kind;title=[string]$before.title.rendered;old_media=$old;new_media=$t.media;reason=$t.reason}
 if($old-ne$t.media){$body=@{post_id=$t.id;attachment_id=$t.media}|ConvertTo-Json -Compress;Invoke-RestMethod ($site+'/wp-json/gk-control/v1/media/set-featured') -Method Post -Headers $control -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))|Out-Null}
 $check=Invoke-RestMethod($site+"/wp-json/wp/v2/$kind/$($t.id)?_fields=id,featured_media&_gk="+(Get-Date -Format HHmmssfff))-TimeoutSec 30;if([long]$check.featured_media-ne$t.media){throw "Zuweisung nicht verifiziert: $($t.id)"};Write-Host("$($t.id): VERIFIED | $old -> $($t.media)")
}
$rows|Export-Csv(Join-Path $backup 'backup.csv')-NoTypeInformation -Encoding UTF8
$cache=Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/clear-cache') -Method Post -Headers $unified -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('{}'));if($cache.cache_cleared-ne$true){throw 'Cache nicht geleert.'}
Write-Host("FERTIG: Korrigiert=$($targets.Count) | Verifiziert=$($targets.Count) | Backup=$backup")
