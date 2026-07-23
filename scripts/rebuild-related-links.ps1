param([string]$EnvFile='.\.env',[ValidateSet('Preview','Apply')][string]$Mode='Preview',[string]$Confirm='')
$ErrorActionPreference='Stop'
if($Mode -eq 'Apply' -and $Confirm -cne 'WEITERFUEHRENDE LINKS NEU BAUEN'){throw 'Bestaetigung fehlt.'}

$catalog=@{
 wlan=@(
  @{url='https://glasfaser-kompass.de/wlan-langsam-trotz-glasfaser/';title='WLAN langsam trotz Glasfaser';label='Fehlersuche';desc='So trennen Sie Anschlussprobleme von WLAN-Problemen.'},
  @{url='https://glasfaser-kompass.de/repeater-richtig-platzieren/';title='Repeater richtig platzieren';label='WLAN-Praxis';desc='Standort, Signalqualit&#228;t und typische Platzierungsfehler.'},
  @{url='https://glasfaser-kompass.de/repeater-oder-access-point/';title='Repeater oder Access Point?';label='Netzplanung';desc='Welche L&#246;sung sich f&#252;r Wohnung und Haus eignet.'})
 router=@(
  @{url='https://glasfaser-kompass.de/routerstandort-optimieren/';title='Routerstandort optimieren';label='Router-Praxis';desc='Der richtige Standort f&#252;r stabiles WLAN.'},
  @{url='https://glasfaser-kompass.de/wlan-langsam-trotz-glasfaser/';title='WLAN langsam trotz Glasfaser';label='Fehlersuche';desc='Leitung und Heimnetz sauber voneinander unterscheiden.'},
  @{url='https://glasfaser-kompass.de/repeater-oder-access-point/';title='Repeater oder Access Point?';label='Erweiterung';desc='Die passende Erg&#228;nzung f&#252;r gr&#246;&#223;ere Wohnfl&#228;chen.'})
 fiber=@(
  @{url='https://glasfaser-kompass.de/ont-erklaert-einfach-erklaert/';title='ONT einfach erkl&#228;rt';label='Glasfaser-Bauteil';desc='Aufgabe und Position des Glasfasermodems.'},
  @{url='https://glasfaser-kompass.de/gf-ap-erklaert/';title='Gf-AP erkl&#228;rt';label='Hausanschluss';desc='Der Glasfaser-Abschlusspunkt im Geb&#228;ude.'},
  @{url='https://glasfaser-kompass.de/wie-laeuft-ein-technikertermin-ab/';title='So l&#228;uft ein Technikertermin ab';label='Vorbereitung';desc='Ablauf, Zugang und sinnvolle Vorbereitung.'})
 dsl=@(
  @{url='https://glasfaser-kompass.de/warum-misst-der-techniker-am-apl/';title='Warum misst der Techniker am APL?';label='DSL-Messung';desc='Was die Messung am Hausanschluss zeigt.'},
  @{url='https://glasfaser-kompass.de/wem-gehoert-der-apl/';title='Wem geh&#246;rt der APL?';label='Zust&#228;ndigkeit';desc='Eigentum, Zugang und Arbeiten am Abschlusspunkt.'},
  @{url='https://glasfaser-kompass.de/was-prueft-ein-techniker-bei-einer-entstoerung/';title='Was pr&#252;ft ein Techniker bei einer Entst&#246;rung?';label='Fehlersuche';desc='Messpunkte und typische Pr&#252;fschritte.'})
 termin=@(
  @{url='https://glasfaser-kompass.de/wie-laeuft-ein-technikertermin-ab/';title='So l&#228;uft ein Technikertermin ab';label='Ablauf';desc='Die wichtigsten Schritte vom Eintreffen bis zum Abschluss.'},
  @{url='https://glasfaser-kompass.de/typische-missverstaendnisse-beim-technikertermin/';title='Missverst&#228;ndnisse beim Technikertermin';label='Vorbereitung';desc='Was Kunden und Techniker vorab kl&#228;ren sollten.'},
  @{url='https://glasfaser-kompass.de/was-prueft-ein-techniker-bei-einer-entstoerung/';title='Pr&#252;fung bei einer Entst&#246;rung';label='Praxis';desc='Welche Messungen und Eingrenzungen &#252;blich sind.'})
}
function Normalize-Title([string]$value){
 $d=$value.Normalize([Text.NormalizationForm]::FormD);$b=New-Object Text.StringBuilder
 foreach($c in $d.ToCharArray()){if([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c)-ne[Globalization.UnicodeCategory]::NonSpacingMark){[void]$b.Append($c)}}
 return $b.ToString()
}
function Cards([long]$id,[string]$title){
 $t=Normalize-Title $title
 $key=if($t-match'WLAN|Wi.?Fi|Mesh|Repeater|Access Point|Frequenz|Heimnetz'){'wlan'}elseif($t-match'Router|FRITZ|Speedport'){'router'}elseif($t-match'Glasfaser|FTTH|ONT|Gf-|GPON|PON|Splei|Hausbegehung|Hausanschluss|LC-Stecker|OTDR'){'fiber'}elseif($t-match'DSL|APL|TAE|TAL|KVz|HVt|Vectoring|CRC|FEC|Dampfung|Storabstand|SNR|Leitung|Entstorung|Fehlerbild'){'dsl'}elseif($t-match'Techniker|Termin|Keller|Auendienst|Schaltung'){'termin'}else{return $null}
 $chosen=@($catalog[$key]|Where-Object{$title -notlike ('*'+$_.title+'*')}|Select-Object -First 3)
 $html="<section class=`"gk-related-box`" aria-labelledby=`"gk-related-$id`">`n<h2 id=`"gk-related-$id`">Weiterf&#252;hrende Artikel</h2>`n<ul class=`"gk-related-grid`">`n"
 foreach($x in $chosen){$html+="<li class=`"gk-related-card`"><p class=`"gk-related-label`"><strong>$($x.label)</strong></p><p><a href=`"$($x.url)`"><strong>$($x.title)</strong></a></p><p>$($x.desc)</p></li>`n"}
 return $html+"</ul>`n</section>"
}
function Bad-Encoding-Score([string]$value){
 $chars=@([char]0x00C3,[char]0x00C2,[char]0x00E2,[char]0x00F0,[char]0xFFFD);$score=0
 foreach($c in $chars){$score+=[regex]::Matches($value,[regex]::Escape([string]$c)).Count};return $score
}
function Repair-Encoding([string]$html){
 $current=$html
 for($attempt=0;$attempt-lt 2;$attempt++){
  $oldScore=Bad-Encoding-Score $current;if($oldScore-eq 0){break}
  try{$candidate=[Text.Encoding]::UTF8.GetString([Text.Encoding]::GetEncoding(1252).GetBytes($current))}catch{break}
  $newScore=Bad-Encoding-Score $candidate
  if($candidate.Contains([char]0xFFFD)-or$newScore-ge$oldScore){break};$current=$candidate
 }
 return $current
}
function Rebuild([long]$id,[string]$title,[string]$html){
 if($html-notmatch'(?i)Weiterf.{1,8}hrende Artikel|GK_RELATED_START|gk-related-box'){return $html}
 $cards=Cards $id $title;if([string]::IsNullOrWhiteSpace($cards)){return $html}
 $token='@@GK_RELATED_CANONICAL@@';$script:placed=$false
 $html=[regex]::Replace($html,'(?is)<section\b[^>]*class\s*=\s*["''][^"'']*\bgk-related-box\b[^"'']*["''][^>]*>.*?</section>',{param($m)if(-not $script:placed){$script:placed=$true;return $token}else{return ''}})
 $html=[regex]::Replace($html,'(?is)<!--\s*GK_RELATED_START\s*-->.*?<!--\s*GK_RELATED_END\s*-->',{param($m)if(-not $script:placed){$script:placed=$true;return $token}else{return ''}})
 $html=[regex]::Replace($html,'(?is)<h2\b[^>]*>\s*Weiterf.{1,8}hrende Artikel\s*</h2>.*?(?=<h2\b|\z)',{param($m)if(-not $script:placed){$script:placed=$true;return $token}else{return ''}})
 if(-not $script:placed){return $html};return $html.Replace($token,$cards)
}
$v=@{};Get-Content $EnvFile|Where-Object{$_-match'^[^#].*='}|ForEach-Object{$p=$_-split'=',2;$v[$p[0].Trim()]=$p[1].Trim()}
foreach($n in @('GK_SITE_URL','GK_SITE_AUDIT_TOKEN','GK_UNIFIED_API_TOKEN')){if([string]::IsNullOrWhiteSpace($v[$n])){throw "$n fehlt."}}
$site=$v.GK_SITE_URL.TrimEnd('/');$ah=@{Authorization='Bearer '+$v.GK_SITE_AUDIT_TOKEN};$uh=@{Authorization='Bearer '+$v.GK_UNIFIED_API_TOKEN};$items=@();$page=1
do{$b=@(Invoke-RestMethod ($site+'/wp-json/gk-site-audit/v1/items?page='+$page+'&per_page=100') -Headers $ah);if($b.Count-eq 1-and $null-ne$b[0].items){$b=@($b[0].items)};$items+=$b;$page++}while($b.Count-eq 100)
$root=if(Test-Path(Join-Path $PSScriptRoot '..\GkProductionWorker.sln')){Split-Path -Parent $PSScriptRoot}else{$PSScriptRoot};$stamp=Get-Date -Format 'yyyyMMdd-HHmmss';$reportDir=Join-Path $root 'reports';$backup=Join-Path $root ('backups\related-'+$stamp);New-Item $reportDir -ItemType Directory -Force|Out-Null;if($Mode-eq'Apply'){New-Item $backup -ItemType Directory -Force|Out-Null};$rows=@()
foreach($i in($items|Sort-Object{[long]$_.id}-Unique)){$id=[long]$i.id;$body=[Text.Encoding]::UTF8.GetBytes((@{id=$id}|ConvertTo-Json -Compress));$p=Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/read-post') -Method Post -Headers $uh -ContentType 'application/json; charset=utf-8' -Body $body;$old=[string]$p.content;$clean=Repair-Encoding $old;$script:placed=$false;$new=Rebuild $id ([string]$p.title) $clean;if($new-ceq$old){continue};if($new-match'gk-related-box'-and[regex]::Matches($new,'class="gk-related-box"').Count-ne 1){throw "Kanonischer Linkbereich fehlt oder ist doppelt: $id"};$status='READY';if($Mode-eq'Apply'){[IO.File]::WriteAllText((Join-Path $backup("post-$id.html")),$old,[Text.UTF8Encoding]::new($false));$payload=[Text.Encoding]::UTF8.GetBytes((@{id=$id;content=$new}|ConvertTo-Json -Compress));$u=Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/update-post') -Method Post -Headers $uh -ContentType 'application/json; charset=utf-8' -Body $payload;if($u.updated-ne$true){throw "Update nicht bestaetigt: $id"};$q=Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/read-post') -Method Post -Headers $uh -ContentType 'application/json; charset=utf-8' -Body $body;if([string]$q.content-cne$new){throw "Speicherpruefung fehlgeschlagen: $id"};$status='UPDATED_AND_VERIFIED'};$rows+=[pscustomobject]@{id=$id;title=[string]$p.title;status=$status};Write-Host("${id}: $status")}
if($Mode-eq'Apply'-and$rows.Count){$c=Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/clear-cache') -Method Post -Headers $uh -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('{}'));if($c.cache_cleared-ne$true){throw 'Cache nicht geleert'}}
$rows|Export-Csv (Join-Path $reportDir('related-rebuild-'+$Mode.ToLower()+'-'+$stamp+'.csv')) -NoTypeInformation -Encoding UTF8
Write-Host('FERTIG: Modus='+$Mode+' | Beitraege='+$rows.Count)
