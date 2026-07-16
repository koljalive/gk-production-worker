param([string]$EnvFile='.\.env',[ValidateSet('Preview','Apply')][string]$Mode='Preview',[string]$Confirm='')
$ErrorActionPreference='Stop'
if($Mode -eq 'Apply' -and $Confirm -cne 'WEITERFUEHRENDE LINKS NEU BAUEN'){throw 'Bestätigung fehlt.'}
$catalog=@{
 wlan=@(
  @{url='https://glasfaser-kompass.de/wlan-langsam-trotz-glasfaser/';title='WLAN langsam trotz Glasfaser';label='Fehlersuche';desc='So trennen Sie Anschlussprobleme von WLAN-Problemen.'},
  @{url='https://glasfaser-kompass.de/repeater-richtig-platzieren/';title='Repeater richtig platzieren';label='WLAN-Praxis';desc='Standort, Signalqualität und typische Platzierungsfehler.'},
  @{url='https://glasfaser-kompass.de/repeater-oder-access-point/';title='Repeater oder Access Point?';label='Netzplanung';desc='Welche Lösung sich für Wohnung und Haus eignet.'},
  @{url='https://glasfaser-kompass.de/wlan-24-5-6-ghz/';title='2,4 GHz, 5 GHz oder 6 GHz?';label='Funktechnik';desc='Reichweite, Tempo und passende Einsatzbereiche.'},
  @{url='https://glasfaser-kompass.de/mesh-wlan-erklaert/';title='Mesh WLAN erklärt';label='Heimnetz';desc='Wann Mesh hilft und wo seine Grenzen liegen.'})
 router=@(
  @{url='https://glasfaser-kompass.de/routerstandort-optimieren/';title='Routerstandort optimieren';label='Router-Praxis';desc='Der richtige Standort für stabiles WLAN.'},
  @{url='https://glasfaser-kompass.de/wlan-langsam-trotz-glasfaser/';title='WLAN langsam trotz Glasfaser';label='Fehlersuche';desc='Leitung und Heimnetz sauber voneinander unterscheiden.'},
  @{url='https://glasfaser-kompass.de/repeater-oder-access-point/';title='Repeater oder Access Point?';label='Erweiterung';desc='Die passende Ergänzung für größere Wohnflächen.'},
  @{url='https://glasfaser-kompass.de/wlan-24-5-6-ghz/';title='WLAN-Frequenzbänder richtig wählen';label='Funktechnik';desc='Welches Frequenzband für welche Geräte passt.'})
 fiber=@(
  @{url='https://glasfaser-kompass.de/ont-erklaert-einfach-erklaert/';title='ONT einfach erklärt';label='Glasfaser-Bauteil';desc='Aufgabe und Position des Glasfasermodems.'},
  @{url='https://glasfaser-kompass.de/gf-ap-erklaert/';title='Gf-AP erklärt';label='Hausanschluss';desc='Der Glasfaser-Abschlusspunkt im Gebäude.'},
  @{url='https://glasfaser-kompass.de/warum-kommt-der-techniker-in-den-keller/';title='Warum kommt der Techniker in den Keller?';label='Technikertermin';desc='Welche Anschlusspunkte dort geprüft werden.'},
  @{url='https://glasfaser-kompass.de/wie-laeuft-ein-technikertermin-ab/';title='So läuft ein Technikertermin ab';label='Vorbereitung';desc='Ablauf, Zugang und sinnvolle Vorbereitung.'})
 dsl=@(
  @{url='https://glasfaser-kompass.de/warum-misst-der-techniker-am-apl/';title='Warum misst der Techniker am APL?';label='DSL-Messung';desc='Was die Messung am Hausanschluss zeigt.'},
  @{url='https://glasfaser-kompass.de/wem-gehoert-der-apl/';title='Wem gehört der APL?';label='Zuständigkeit';desc='Eigentum, Zugang und Arbeiten am Abschlusspunkt.'},
  @{url='https://glasfaser-kompass.de/was-prueft-ein-techniker-bei-einer-entstoerung/';title='Was prüft ein Techniker bei einer Entstörung?';label='Fehlersuche';desc='Messpunkte und typische Prüfschritte.'},
  @{url='https://glasfaser-kompass.de/warum-kommt-der-techniker-in-den-keller/';title='Warum kommt der Techniker in den Keller?';label='Hausanschluss';desc='Warum der Zugang zu APL und Hausverkabelung wichtig ist.'})
 termin=@(
  @{url='https://glasfaser-kompass.de/wie-laeuft-ein-technikertermin-ab/';title='So läuft ein Technikertermin ab';label='Ablauf';desc='Die wichtigsten Schritte vom Eintreffen bis zum Abschluss.'},
  @{url='https://glasfaser-kompass.de/typische-missverstaendnisse-beim-technikertermin/';title='Missverständnisse beim Technikertermin';label='Vorbereitung';desc='Was Kunden und Techniker vorab klären sollten.'},
  @{url='https://glasfaser-kompass.de/warum-kommt-der-techniker-in-den-keller/';title='Warum muss der Techniker in den Keller?';label='Zugang';desc='Welche Technik dort erreichbar sein muss.'},
  @{url='https://glasfaser-kompass.de/was-prueft-ein-techniker-bei-einer-entstoerung/';title='Prüfung bei einer Entstörung';label='Praxis';desc='Welche Messungen und Eingrenzungen üblich sind.'})
}
function Cards([long]$id,[string]$title){
 $key=if($title-match'WLAN|Wi.?Fi|Mesh|Repeater|Access Point|Frequenz|Routerstandort'){'wlan'}elseif($title-match'Router|FRITZ|Speedport'){'router'}elseif($title-match'Glasfaser|FTTH|ONT|Gf-|Spleiß'){'fiber'}elseif($title-match'DSL|APL|TAE|Vectoring|CRC|Leitung|Entstörung'){'dsl'}else{'termin'}
 $chosen=@($catalog[$key]|Where-Object{$title -notlike ('*'+$_.title+'*')}|Select-Object -First 3)
 $html="<section class=`"gk-related-box`" aria-labelledby=`"gk-related-$id`">`n<h2 id=`"gk-related-$id`">Weiterführende Artikel</h2>`n<div class=`"gk-related-grid`">`n"
 foreach($x in $chosen){$html+="<a class=`"gk-related-card`" href=`"$($x.url)`"><span class=`"gk-related-label`">$($x.label)</span><strong>$($x.title)</strong><span>$($x.desc)</span></a>`n"}
 $html += "</div>`n</section>"; return $html
}
function Rebuild([long]$id,[string]$title,[string]$html){
 if($html -notmatch'Weiterf.hrende Artikel|GK_RELATED_START'){return $html}
 $token='@@GK_RELATED_CANONICAL@@';$script:placed=$false
 $html=[regex]::Replace($html,'(?is)<!--\s*GK_RELATED_START\s*-->.*?<!--\s*GK_RELATED_END\s*-->',{param($m)if(-not $script:placed){$script:placed=$true;return $token}else{return''}})
 $html=[regex]::Replace($html,'(?is)<h2\b[^>]*>\s*Weiterf.hrende Artikel\s*</h2>.*?(?=<h2\b|\z)',{param($m)if(-not $script:placed){$script:placed=$true;return $token}else{return''}})
 if(-not $script:placed){return $html};return $html.Replace($token,(Cards $id $title))
}
$v=@{};Get-Content $EnvFile|Where-Object{$_-match'^[^#].*='}|ForEach-Object{$p=$_-split'=',2;$v[$p[0].Trim()]=$p[1].Trim()};foreach($n in @('GK_SITE_URL','GK_SITE_AUDIT_TOKEN','GK_UNIFIED_API_TOKEN')){if([string]::IsNullOrWhiteSpace($v[$n])){throw "$n fehlt."}};$site=$v.GK_SITE_URL.TrimEnd('/');$ah=@{Authorization='Bearer '+$v.GK_SITE_AUDIT_TOKEN};$uh=@{Authorization='Bearer '+$v.GK_UNIFIED_API_TOKEN};$items=@();$page=1
do{$b=@(Invoke-RestMethod($site+'/wp-json/gk-site-audit/v1/items?page='+$page+'&per_page=100')-Headers $ah);if($b.Count-eq 1-and $null-ne$b[0].items){$b=@($b[0].items)};$items+=$b;$page++}while($b.Count-eq 100)
$root=if(Test-Path(Join-Path $PSScriptRoot '..\GkProductionWorker.sln')){Split-Path -Parent $PSScriptRoot}else{$PSScriptRoot};$stamp=Get-Date -Format 'yyyyMMdd-HHmmss';$reportDir=Join-Path $root 'reports';$backup=Join-Path $root ('backups\related-'+$stamp);New-Item $reportDir -ItemType Directory -Force|Out-Null;if($Mode-eq'Apply'){New-Item $backup -ItemType Directory -Force|Out-Null};$rows=@()
foreach($i in($items|Sort-Object{[long]$_.id}-Unique)){$id=[long]$i.id;$body=[Text.Encoding]::UTF8.GetBytes((@{id=$id}|ConvertTo-Json -Compress));$p=Invoke-RestMethod($site+'/wp-json/gk-unified-api/v1/read-post')-Method Post -Headers $uh -ContentType 'application/json; charset=utf-8' -Body $body;$old=[string]$p.content;$script:placed=$false;$new=Rebuild $id ([string]$p.title) $old;if($new-ceq$old){continue};if([regex]::Matches($new,'class="gk-related-box"').Count-ne 1){throw "Kanonischer Linkbereich fehlt oder ist doppelt: $id"};$status='READY';if($Mode-eq'Apply'){[IO.File]::WriteAllText((Join-Path $backup("post-$id.html")),$old,[Text.UTF8Encoding]::new($false));$payload=[Text.Encoding]::UTF8.GetBytes((@{id=$id;content=$new}|ConvertTo-Json -Compress));$u=Invoke-RestMethod($site+'/wp-json/gk-unified-api/v1/update-post')-Method Post -Headers $uh -ContentType 'application/json; charset=utf-8' -Body $payload;if($u.updated -ne $true){throw "Update nicht bestätigt: $id"};$q=Invoke-RestMethod($site+'/wp-json/gk-unified-api/v1/read-post')-Method Post -Headers $uh -ContentType 'application/json; charset=utf-8' -Body $body;if([string]$q.content-cne$new){throw "Speicherprüfung fehlgeschlagen: $id"};$status='UPDATED_AND_VERIFIED'};$rows+=[pscustomobject]@{id=$id;title=[string]$p.title;status=$status};Write-Host("${id}: $status")}
if($Mode-eq'Apply'-and $rows.Count){$c=Invoke-RestMethod($site+'/wp-json/gk-unified-api/v1/clear-cache')-Method Post -Headers $uh -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('{}'));if($c.cache_cleared -ne $true){throw 'Cache nicht geleert'}};$rows|Export-Csv (Join-Path $reportDir('related-rebuild-'+$Mode.ToLower()+'-'+$stamp+'.csv')) -NoTypeInformation -Encoding UTF8;Write-Host('FERTIG: Modus='+$Mode+' | Beiträge='+$rows.Count)
