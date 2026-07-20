param([ValidateSet('Preview','Apply')][string]$Mode='Preview')
$ErrorActionPreference='Stop'
$site=$env:GK_SITE_URL.TrimEnd('/')
$token=$env:GK_UNIFIED_API_TOKEN
foreach($value in @($site,$token)){if([string]::IsNullOrWhiteSpace($value)){throw 'Erforderliche Zugangsdaten fehlen.'}}
$uh=@{Authorization='Bearer '+$token}
$wh=@{}
$root=Split-Path -Parent $PSScriptRoot
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$backup=Join-Path $root ('backups\final-live-repair-'+$stamp)
$report=Join-Path $root 'reports'
New-Item $backup,$report -ItemType Directory -Force|Out-Null

function Utf8([string]$value){[Text.Encoding]::UTF8.GetBytes($value)}
function Read-Post([long]$id){Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/read-post') -Method Post -Headers $uh -ContentType 'application/json; charset=utf-8' -Body (Utf8 ((@{id=$id}|ConvertTo-Json -Compress))) -TimeoutSec 60}
function Save-Post([long]$id,[string]$content){
  $result=Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/update-post') -Method Post -Headers $uh -ContentType 'application/json; charset=utf-8' -Body (Utf8 ((@{id=$id;content=$content}|ConvertTo-Json -Compress))) -TimeoutSec 60
  if($result.updated-ne$true){throw "Speicherung nicht bestätigt: $id"}
  $check=Read-Post $id
  if(([string]$check.content)-cne$content){throw "Speicherprüfung fehlgeschlagen: $id"}
}
function Clean([string]$html,[string]$slug){
  $x=$html
  $x=$x.Replace('Verantwortlich gemä §','Verantwortlich gemäß §')
  $x=[regex]::Replace($x,'(?is)<style\b[^>]*>.*?</style>','')
  $x=[regex]::Replace($x,'(?is)<script\b[^>]*>.*?</script>','')
  $x=[regex]::Replace($x,'(?is)<p\b[^>]*>[^<]*(?:querySelectorAll|display\s*:\s*none\s*!important)[^<]*</p>','')
  $x=[regex]::Replace($x,'(?is)<!--\s*GK[^>]*-->','')
  $x=[regex]::Replace($x,'(?is)<h2\b[^>]*>\s*Offizielle Quellen\s*</h2>\s*(?<list><ul\b[^>]*>.*?</ul>)\s*<h2\b[^>]*>\s*Offizielle Quellen\s*</h2>\s*\k<list>','<h2>Offizielle Quellen</h2>${list}')
  $x=[regex]::Replace($x,'(?is)(<section\b[^>]*class=["''][^"'']*(?:gk9-authorbox|gkpr-author)[^"'']*["''][^>]*>.*?</section>)(?:\s*\1)+','$1')
  $x=[regex]::Replace($x,'(?is)(<section\b[^>]*class=["''][^"'']*(?:gk9-tarifcheck|gkpr-affiliate)[^"'']*["''][^>]*>.*?</section>)(?:\s*\1)+','$1')
  if($slug-match'^(impressum|datenschutz|kontakt)'){$x=[regex]::Replace($x,'(?is)<section\b[^>]*class=["''][^"'']*(?:gk9-tarifcheck|gkpr-affiliate)[^"'']*["''][^>]*>.*?</section>','')}
  return $x.Trim()
}

$asset=$site+'/wp-content/plugins/gk-render-guard/assets/'
$replacements=@{}
$replacements['dsl-bauteile-im-haus']=@"
<article class="gk-clean-article"><figure class="gk-article-visual"><img src="$($asset)dsl-kupfer-signalweg.png" alt="DSL-Signalweg vom DSLAM oder MSAN über das Kupfernetz, den APL, die Endleitung und die erste TAE bis zum Router."><figcaption>Der DSL-Signalweg im Gebäude und im Zugangsnetz.</figcaption></figure>
<p>Bei einem DSL-Anschluss müssen Netz und Hausverkabelung getrennt betrachtet werden. Netzseitig erzeugt ein DSLAM oder MSAN das DSL-Signal. Bei FTTC/VDSL sitzt diese aktive Technik häufig im Multifunktionsgehäuse; das MFG ist also das Gehäuse und nicht eine zusätzliche Signalstufe hinter dem DSLAM.</p>
<h2>Der korrekte Signalweg</h2><p><strong>DSLAM/MSAN – Kupfer-Zugangsnetz – APL – Endleitung – erste TAE – DSL-Router.</strong></p>
<h2>APL</h2><p>Der Abschlusspunkt Linientechnik beendet das öffentliche Kupfer-Zugangsnetz am Gebäude. Er ist passiv und enthält weder DSL-Modem noch Routertechnik. Arbeiten und Messungen am APL gehören grundsätzlich in die Hände des Netzbetreibers beziehungsweise seines Auftragnehmers.</p>
<h2>Endleitung</h2><p>Die Endleitung verbindet den APL mit der ersten TAE. Schlechte Klemmstellen, Abzweigungen, ungeeignete Leitungen oder parallel geschaltete Dosen können Dämpfung, Störabstand und Fehlerzahl verschlechtern.</p>
<h2>Erste TAE</h2><p>Die erste TAE ist der reguläre Übergabe- und Messpunkt in den Kundenräumen. Der Vergleich einer Messung am APL mit einer Messung an der ersten TAE zeigt, ob die Hausverkabelung die Leitung verschlechtert.</p>
<h2>Router</h2><p>Der DSL-Router synchronisiert sich mit dem DSLAM/MSAN. Seine Leitungswerte helfen bei der Eingrenzung, ersetzen aber keine qualifizierte Messung an APL und TAE.</p>
<h2>Praxisprüfung</h2><ul><li>APL und erste TAE müssen erreichbar sein.</li><li>Zwischen APL und erster TAE sollten keine unnötigen Abzweigungen liegen.</li><li>Router, Netzteil und DSL-Anschlusskabel werden gemeinsam geprüft.</li><li>LAN- und WLAN-Probleme werden erst nach bestätigter DSL-Synchronisation bewertet.</li></ul>
<h2>Offizielle Quellen</h2><ul><li><a href="https://www.telekom.de/hilfe">Deutsche Telekom Hilfe</a></li><li><a href="https://www.bundesnetzagentur.de/DE/Vportal/TK/InternetTelefon/Internetgeschwindigkeit/start.html">Bundesnetzagentur – Internetzugang und Geschwindigkeit</a></li></ul></article>
"@
$replacements['apl-tae-signalweg']=@"
<article class="gk-clean-article"><figure class="gk-article-visual"><img src="$($asset)dsl-kupfer-signalweg.png" alt="Korrekter DSL-Signalweg von DSLAM oder MSAN über Kupfernetz, APL, Endleitung und erste TAE bis zum Router."><figcaption>DSLAM/MSAN → Kupfer-Zugangsnetz → APL → Endleitung → erste TAE → Router.</figcaption></figure>
<h2>Der DSL-Signalweg</h2><p>Das DSL-Signal beginnt am Port eines DSLAM oder MSAN. Bei FTTC/VDSL befindet sich diese aktive Technik meist in einem Multifunktionsgehäuse am Straßenrand. Das MFG ist das Gehäuse der aktiven Technik und keine zusätzliche Station nach dem DSLAM.</p>
<ol><li><strong>DSLAM/MSAN:</strong> stellt das DSL-Signal bereit.</li><li><strong>Kupfer-Zugangsnetz:</strong> führt das Signal über Kabel, Verzweiger, Muffen und Anschlussadern zum Gebäude.</li><li><strong>APL:</strong> passiver Gebäudeabschluss des Betreiber-Netzes.</li><li><strong>Endleitung:</strong> gebäudeseitige Verbindung zur ersten TAE.</li><li><strong>Erste TAE:</strong> regulärer Anschluss- und Messpunkt in den Kundenräumen.</li><li><strong>Router:</strong> synchronisiert das DSL-Modem mit dem DSLAM/MSAN.</li></ol>
<h2>Warum an zwei Punkten gemessen wird</h2><p>Eine gute Messung am APL und deutlich schlechtere Werte an der ersten TAE sprechen für einen Fehler in Endleitung, Klemmstelle oder Dose. Sind die Werte bereits am APL auffällig, wird netzseitig weiter eingegrenzt.</p>
<h2>Typische Fehler</h2><ul><li>DSLAM und MFG fälschlich als zwei hintereinanderliegende Signalstufen darstellen.</li><li>Endleitung zwischen APL und TAE auslassen.</li><li>ONT oder Gf-TA in einen Kupfer-DSL-Signalweg einordnen.</li><li>WLAN-Probleme mit der DSL-Leitung gleichsetzen.</li></ul>
<h2>Offizielle Quellen</h2><ul><li><a href="https://www.telekom.de/hilfe">Deutsche Telekom Hilfe</a></li><li><a href="https://www.bundesnetzagentur.de/DE/Vportal/TK/InternetTelefon/Internetgeschwindigkeit/start.html">Bundesnetzagentur</a></li></ul></article>
"@
$replacements['endleitung-dsl-probleme']=@"
<article class="gk-clean-article"><figure class="gk-article-visual"><img src="$($asset)dsl-kupfer-signalweg.png" alt="Endleitung zwischen APL und erster TAE im DSL-Signalweg."><figcaption>Die Endleitung liegt zwischen APL und erster TAE.</figcaption></figure>
<h2>Was ist die Endleitung?</h2><p>Als Endleitung wird die gebäudeseitige Kupferverbindung vom APL zur ersten TAE bezeichnet. Sie gehört nicht zum WLAN und ist auch keine Glasfaserstrecke. Ihre Qualität kann die erreichbare DSL-Datenrate und Stabilität unmittelbar beeinflussen.</p>
<h2>Typische Fehlerquellen</h2><ul><li>korrodierte oder lose Klemmstellen</li><li>unnötige Verlängerungen und zusätzliche Übergänge</li><li>parallel angeschlossene TAE-Dosen oder Abzweigungen</li><li>ungeeignete, ungeschirmte oder beschädigte Leitungen</li><li>Feuchtigkeit, Quetschungen oder beschädigte Adern</li><li>alte Telefoninstallationen mit weiteren Bauteilen im Leitungsweg</li></ul>
<h2>Woran erkennt der Techniker ein Problem?</h2><p>Entscheidend ist der Vergleich: Sind Synchronisation, Störabstand oder Fehlerwerte am APL deutlich besser als an der ersten TAE, liegt die Ursache häufig in der Endleitung oder Dose. Ein einzelner Speedtest reicht für diese Aussage nicht aus.</p>
<h2>Wann sollte die Leitung erneuert werden?</h2><p>Eine Erneuerung ist sinnvoll, wenn ein reproduzierbarer Messunterschied zwischen APL und erster TAE besteht, sichtbare Schäden vorhanden sind oder sich problematische Abzweigungen nicht fachgerecht beseitigen lassen. Die konkrete Ausführung sollte mit Netzbetreiber, Eigentümer und Fachbetrieb abgestimmt werden.</p>
<h2>Was Nutzer vorbereiten können</h2><ul><li>APL und erste TAE freiräumen.</li><li>Verlauf und vorhandene weitere Dosen dokumentieren.</li><li>Zeitpunkte von Abbrüchen notieren.</li><li>Routerwerte sichern, ohne den APL selbst zu öffnen.</li></ul>
<h2>Offizielle Quellen</h2><ul><li><a href="https://www.telekom.de/hilfe">Deutsche Telekom Hilfe</a></li><li><a href="https://www.bundesnetzagentur.de/DE/Vportal/TK/InternetTelefon/Internetgeschwindigkeit/start.html">Bundesnetzagentur</a></li></ul></article>
"@
$replacements['nvt-erklaert']=@"
<article class="gk-clean-article"><figure class="gk-article-visual"><img src="$($asset)nvt.png" alt="Geöffneter Glasfaser-Netzverteiler mit Spleißkassetten und passiven Verteilfeldern."><figcaption>Beispiel eines passiven Glasfaser-Netzverteilers.</figcaption></figure>
<h2>Was bedeutet NVT?</h2><p>NVT steht üblicherweise für Netzverteiler. Im FTTH-Ausbau bezeichnet der Begriff einen passiven Verteilpunkt zwischen übergeordnetem Glasfasernetz und den Leitungen zu Gebäuden oder kleineren Verteilbereichen. Aufbau, Bezeichnung und Position unterscheiden sich je nach Netzbetreiber.</p>
<h2>Welche Aufgabe hat der NVT?</h2><p>Im NVT werden Fasern geordnet, gespleißt und – bei passiven optischen Netzen – gegebenenfalls über optische Splitter verteilt. Ein NVT erzeugt kein optisches Signal und benötigt für seine reine passive Verteilfunktion keine Stromversorgung.</p>
<h2>Wo steht er?</h2><p>Je nach Ausbaukonzept befindet sich der Verteiler in einem Außengehäuse, Schacht, Technikraum oder Gebäude. Nicht jedes Netz verwendet dieselbe Hierarchie oder denselben Begriff.</p>
<h2>Abgrenzung</h2><ul><li><strong>PoP:</strong> Standort aktiver Netztechnik.</li><li><strong>NVT:</strong> passiver regionaler Verteilpunkt.</li><li><strong>Gf-AP:</strong> Gebäudeabschluss des Glasfasernetzes.</li><li><strong>Gf-TA:</strong> Teilnehmeranschlussdose in Wohnung oder Haus.</li><li><strong>ONT:</strong> aktives Gerät zur Umsetzung des optischen Signals auf Ethernet.</li></ul>
<h2>Praxis</h2><p>NVTs gehören zum Betreiber-Netz und dürfen nicht von Anschlussnutzern geöffnet werden. Für eine Störung wird anhand von Dokumentation und Messwerten bestimmt, an welchem Abschnitt weiter geprüft werden muss.</p>
<h2>Offizielle Quellen</h2><ul><li><a href="https://www.gigabitgrundbuch.bund.de/">Gigabit-Grundbuch des Bundes</a></li><li><a href="https://www.telekom.de/netz/glasfaser">Deutsche Telekom – Glasfasernetz</a></li></ul></article>
"@
$replacements['splitter-erklaert']=@"
<article class="gk-clean-article"><figure class="gk-article-visual"><img src="$($asset)splitter.png" alt="Passiver optischer Splitter mit einem Eingang und mehreren Ausgängen."><figcaption>Ein passiver optischer Splitter verteilt die Lichtleistung eines Eingangs auf mehrere Ausgänge.</figcaption></figure>
<h2>Was ist ein optischer Splitter?</h2><p>Ein optischer Splitter ist ein passives Bauteil in PON-Netzen. Er verteilt das Lichtsignal einer Faser auf mehrere Teilnehmerfasern. Er routet keine Daten, benötigt keinen Strom und ist nicht mit einem Ethernet-Switch oder DSL-Splitter gleichzusetzen.</p>
<h2>Teilungsverhältnis und Dämpfung</h2><p>Übliche Teilungsverhältnisse sind beispielsweise 1:4, 1:8, 1:16 oder 1:32. Mit steigender Zahl der Ausgänge verteilt sich die optische Leistung auf mehr Wege; zusätzlich entstehen Einfüge- und Verteilverluste. Deshalb muss der gesamte optische Leistungspegel innerhalb des vorgesehenen Budgets liegen.</p>
<h2>Wo befindet sich der Splitter?</h2><p>Je nach Netzarchitektur kann er im PoP, Netzverteiler, einer Muffe oder einem anderen passiven Verteilpunkt sitzen. Kaskadierte Splitter sind möglich, wenn das Netz entsprechend geplant wurde.</p>
<h2>Was prüft der Techniker?</h2><ul><li>Dokumentierten Faserweg und Splitterport</li><li>optischen Pegel und zulässiges Leistungsbudget</li><li>Steckverbindungen, Spleiße und Verschmutzung</li><li>Zuordnung zwischen Netzseite und Teilnehmerfaser</li></ul>
<h2>Abgrenzung</h2><p>Der OLT stellt netzseitig das PON-Signal bereit. Der Splitter verteilt es passiv. Beim Teilnehmer beendet ein ONT oder geeigneter Glasfaserrouter die optische Verbindung.</p>
<h2>Offizielle Quellen</h2><ul><li><a href="https://www.itu.int/rec/T-REC-G.984">ITU-T G.984 – GPON</a></li><li><a href="https://www.itu.int/rec/T-REC-G.9807.1">ITU-T G.9807.1 – XGS-PON</a></li></ul></article>
"@

$items=@()
foreach($kind in @('posts','pages')){$page=1;do{try{$batch=@(Invoke-RestMethod ($site+"/wp-json/wp/v2/$kind`?status=publish&per_page=100&page=$page&_fields=id,slug,title,author") -Headers $wh -TimeoutSec 60);if($batch.Count-eq1-and$batch[0]-is[Array]){$batch=@($batch[0])}}catch{if($_.Exception.Response-and[int]$_.Exception.Response.StatusCode-eq400){$batch=@()}else{throw}};$items+=@($batch|ForEach-Object{[pscustomobject]@{kind=$kind;id=[long]$_.id;slug=[string]$_.slug;title=[string]$_.title.rendered;author=[long]$_.author}});$page++}while($batch.Count-eq100)}
$rows=@()
foreach($item in $items){
  Write-Host ("PRUEFE: $($item.id) $($item.slug)")
  try{$post=Read-Post $item.id}catch{$rows+=[pscustomobject]@{id=$item.id;slug=$item.slug;title=$item.title;status='SKIPPED_READ_ERROR';reason=$_.Exception.Message};continue}
  $old=[string]$post.content
  $new=if($replacements.ContainsKey($item.slug)){[string]$replacements[$item.slug]}else{Clean $old $item.slug}
  $reasons=@();if($new-cne$old){$reasons+='CONTENT'}
  if(-not$reasons.Count){continue}
  $status='READY'
  if($Mode-eq'Apply'){
    [IO.File]::WriteAllText((Join-Path $backup ("post-$($item.id).html")),$old,[Text.UTF8Encoding]::new($false))
    if($new-cne$old){Save-Post $item.id $new}
    $status='UPDATED_AND_VERIFIED'
  }
  $rows+=[pscustomobject]@{id=$item.id;slug=$item.slug;title=$item.title;status=$status;reason=($reasons-join',')}
}
if($Mode-eq'Apply'){
  $cache=Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/clear-cache') -Method Post -Headers $uh -ContentType 'application/json' -Body '{}' -TimeoutSec 60
  if($cache.cache_cleared-ne$true){throw 'Cache-Leerung nicht bestätigt.'}
}
$path=Join-Path $report ("final-live-repair-$Mode-$stamp.csv")
$rows|Export-Csv $path -NoTypeInformation -Encoding UTF8
Write-Host ("FERTIG: Modus=$Mode | Geändert=$($rows.Count) | Bericht=$path")
