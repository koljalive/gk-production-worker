param([ValidateSet('Preview','Apply')][string]$Mode='Preview')
$ErrorActionPreference='Stop'
$site=$env:GK_SITE_URL.TrimEnd('/')
$token=$env:GK_UNIFIED_API_TOKEN
$wpUser=$env:WP_USERNAME
$wpPass=$env:WP_APPLICATION_PASSWORD
if([string]::IsNullOrWhiteSpace($site)-or[string]::IsNullOrWhiteSpace($token)-or[string]::IsNullOrWhiteSpace($wpUser)-or[string]::IsNullOrWhiteSpace($wpPass)){throw 'GK_SITE_URL, GK_UNIFIED_API_TOKEN, WP_USERNAME und WP_APPLICATION_PASSWORD sind erforderlich.'}
$headers=@{Authorization='Bearer '+$token}
$basic=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($wpUser+':'+$wpPass))
$wpHeaders=@{Authorization='Basic '+$basic}
$root=Split-Path -Parent $PSScriptRoot
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$backup=Join-Path $root ('backups\dsl-cluster-batch-01-'+$stamp)
$report=Join-Path $root 'reports'
New-Item $backup,$report -ItemType Directory -Force|Out-Null
$asset=$site+'/wp-content/plugins/gk-render-guard/assets/'

function Read-Post([long]$id){
  $body=[Text.Encoding]::UTF8.GetBytes((@{id=$id}|ConvertTo-Json -Compress))
  Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/read-post') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 90
}
function Strip([string]$html){
  $text=[Net.WebUtility]::HtmlDecode([regex]::Replace($html,'(?is)<[^>]+>',' '))
  [regex]::Replace($text,'\s+',' ').Trim()
}
function Save-Post([long]$id,[string]$content){
  # Der Unified-Endpunkt wurde hier bewusst nicht verwendet: Bei mehrwurzeligem
  # Artikel-HTML bestätigte er Readback, während WordPress öffentlich nur den
  # ersten Block auslieferte. Die native WP-REST-API ist die maßgebliche Quelle.
  $body=[Text.Encoding]::UTF8.GetBytes((@{content=$content}|ConvertTo-Json -Compress))
  $result=Invoke-RestMethod ($site+"/wp-json/wp/v2/posts/$id") -Method Post -Headers $wpHeaders -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 90
  if([long]$result.id-ne$id){throw "WordPress-Speicherung nicht bestätigt: $id"}
  $check=Invoke-RestMethod ($site+"/wp-json/wp/v2/posts/$id`?context=edit&_fields=id,content") -Headers $wpHeaders -TimeoutSec 90
  $stored=[string]$check.content.raw
  if((Strip $stored)-cne(Strip $content)){throw "Readback stimmt nicht überein: $id"}
}
function Figure([string]$file,[string]$alt,[string]$caption){
  '<figure class="gk-topic-photo"><img src="'+$asset+$file+'" alt="'+[Net.WebUtility]::HtmlEncode($alt)+'" loading="lazy"><figcaption>'+[Net.WebUtility]::HtmlEncode($caption)+'</figcaption></figure>'
}
function Sources(){
  '<h2>Offizielle Quellen</h2><ul><li><a href="https://www.bundesnetzagentur.de/DE/Vportal/TK/InternetTelefon/Internetgeschwindigkeit/start.html">Bundesnetzagentur: Internetzugang und Geschwindigkeit</a></li><li><a href="https://www.telekom.de/hilfe/internet-telefonie/internet">Deutsche Telekom: Hilfe zu Internet und Anschluss</a></li></ul>'
}

$articles=@{}
$articles[26206]=@"
<article class="gk-clean-article">
<h2>DSL-Bauteile im Haus eindeutig erkennen</h2>
$(Figure 'apl.png' 'Geöffneter Kupfer-APL mit Mehraderkabel und Anschlussklemmen.' 'APL: passiver Abschluss des Betreiber-Kupfernetzes am Gebäude.')
$(Figure 'tae-dose.jpg' 'Weiße TAE-NFF-Anschlussdose mit drei Buchsen.' 'Erste TAE: Anschluss- und Messpunkt in den Kundenräumen.')
<h2>Der korrekte Signalweg</h2><p><strong>MFG mit DSLAM/MSAN → KVz → Kupfer-Zugangsnetz → APL → Endleitung → erste TAE → DSL-Router</strong></p>
<h3>APL</h3><p>Der Abschlusspunkt Linientechnik beendet das öffentliche Kupfer-Zugangsnetz am Gebäude. Er ist passiv. Mehraderkabel, Doppeladern und Anschlussklemmen unterscheiden ihn von einem Glasfaser-Gf-AP und einem Koax-HÜP.</p>
<h3>Endleitung</h3><p>Die Endleitung ist das verwendete Kupfer-Adernpaar zwischen APL und erster TAE. Abzweigungen, lose Klemmstellen, ungeeignete Leitungen und parallel geschaltete Dosen können DSL-Werte verschlechtern.</p>
<h3>Erste TAE</h3><p>Die erste TAE ist der reguläre Anschluss- und Messpunkt in den Kundenräumen. Der Vergleich zwischen APL und erster TAE grenzt Fehler der Endleitung ein.</p>
<h3>DSL-Router</h3><p>Das integrierte DSL-Modem synchronisiert sich mit dem DSLAM/MSAN. Erst wenn diese Verbindung stabil ist, werden LAN und WLAN getrennt beurteilt.</p>
<h2>Vor einem Technikertermin</h2><ul><li>APL und erste TAE zugänglich machen.</li><li>Router, Netzteil und DSL-Kabel bereithalten.</li><li>Weitere Dosen und bekannte Abzweigungen nennen.</li><li>APL nicht selbst öffnen oder umklemmen.</li></ul>
$(Sources)
</article>
"@
$articles[3015]=@"
<article class="gk-clean-article">
$(Figure 'mfg.png' 'Graues Multifunktionsgehäuse am Straßenrand.' 'Bei FTTC/VDSL befindet sich die aktive DSLAM-/MSAN-Technik typischerweise im grauen MFG.')
<h2>Was macht ein DSLAM oder MSAN?</h2><p>Der DSLAM stellt die DSL-Verbindung für viele Teilnehmer bereit. Ein MSAN übernimmt zusätzlich weitere Zugangsfunktionen. Bei FTTC/VDSL sitzt diese aktive Technik typischerweise <strong>im Multifunktionsgehäuse</strong>. Das MFG ist das Gehäuse und keine eigene Signalstufe vor oder hinter dem DSLAM.</p>
<h2>Der korrekte FTTC-/VDSL-Signalweg</h2><p><strong>Glasfaserzuführung → MFG mit DSLAM/MSAN → KVz → Kupfer-Zugangsnetz → APL → Endleitung → erste TAE → DSL-Router</strong></p>
<p>Der KVz ist ein eigener passiver Kabelverzweiger. MFG und KVz sind üblicherweise graue Straßengehäuse. Je nach Ausbau können sie nebeneinander stehen oder technisch gekoppelt sein.</p>
<h2>Abgrenzung zu FTTH</h2><p>Bei einem reinen FTTH-Anschluss gibt es auf der Teilnehmerstrecke keinen DSLAM. Dort sind OLT, passives Glasfasernetz, Gf-AP, Gf-TA und gegebenenfalls ONT relevant.</p>
<h2>Praxis</h2><p>Der Router synchronisiert sein DSL-Modem mit dem Port im DSLAM/MSAN. Auffällige Werte werden anschließend abschnittsweise zwischen Netz, APL, Endleitung und erster TAE eingegrenzt.</p>
$(Sources)
</article>
"@
$articles[5006]=$articles[3015]
$articles[20803]=@"
<article class="gk-clean-article">
$(Figure 'apl.png' 'Geöffneter Kupfer-APL mit Mehraderkabel und Anschlussklemmen.' 'Bei DSL beginnt die Gebäudediagnose am Kupfer-APL und führt über Endleitung und erste TAE zum Router.')
<h2>DSL-Störungen systematisch eingrenzen</h2><ol><li><strong>Synchronisation prüfen:</strong> Besteht keine DSL-Synchronisation, liegt der Fehler vor der Internet-Einwahl.</li><li><strong>Routerwerte sichern:</strong> Datenrate, Störabstandsmarge, Dämpfung und Fehlerzähler mit Zeitstempel notieren.</li><li><strong>APL und erste TAE vergleichen:</strong> Deutlich schlechtere Werte an der TAE sprechen häufig für Endleitung, Klemmstelle oder Dose.</li><li><strong>LAN vor WLAN testen:</strong> Erst nach stabiler DSL-Verbindung das Heimnetz beurteilen.</li></ol>
<h2>Typische Hinweise</h2><table><thead><tr><th>Beobachtung</th><th>Zu prüfender Bereich</th></tr></thead><tbody><tr><td>Keine Synchronisation</td><td>Port, Kupfernetz, APL, Endleitung, TAE oder DSL-Kabel</td></tr><tr><td>Abbrüche bei Regen</td><td>Feuchtigkeit an Muffe, Kabel, APL oder Klemmstelle</td></tr><tr><td>Am APL gut, an der TAE schlecht</td><td>Endleitung, Abzweigung oder TAE</td></tr><tr><td>LAN stabil, WLAN langsam</td><td>Routerstandort, Funkkanal und Heimnetz</td></tr></tbody></table>
<h2>Was ein Speedtest nicht zeigt</h2><p>Ein Speedtest allein trennt Anschlussfehler nicht von WLAN-, LAN- oder Endgeräteproblemen. Für die Leitungsdiagnose sind Synchronisation und Messvergleich an definierten Punkten entscheidend.</p>
$(Sources)
</article>
"@
$articles[3011]=@"
<article class="gk-clean-article">
$(Figure 'tae-dose.jpg' 'Weiße TAE-NFF-Anschlussdose mit drei Buchsen.' 'TAE-Dose: Anschluss- und Messpunkt eines kupferbasierten Telefon- oder DSL-Anschlusses.')
<h2>Was ist eine TAE?</h2><p>Die Telekommunikations-Anschluss-Einheit ist eine Anschlussdose für kupferbasierte Telefon- und DSL-Anschlüsse. Die erste TAE liegt hinter dem APL und der Endleitung. Gf-AP, Gf-TA und ONT gehören dagegen zu Glasfaseranschlüssen.</p>
<h2>Warum ist die erste TAE wichtig?</h2><p>Sie ist der reguläre Anschluss- und Messpunkt in den Kundenräumen. Der Vergleich einer Messung am APL mit der Messung an der ersten TAE zeigt, ob die Endleitung oder Dose die DSL-Verbindung verschlechtert.</p>
<h2>Typische Fehler</h2><ul><li>lose oder korrodierte Kontakte</li><li>parallel angeschlossene weitere Dosen</li><li>unnötige Verlängerungen und Abzweigungen</li><li>beschädigte Anschlussleitung zum Router</li><li>verdeckte oder nicht erreichbare erste TAE</li></ul>
<h2>Was Nutzer selbst tun können</h2><p>Dose freiräumen, DSL-Kabel kontrollieren und Routerwerte dokumentieren. Die erste TAE, den APL und feste Leitungen nicht eigenmächtig umklemmen.</p>
$(Sources)
</article>
"@
$articles[5002]=$articles[3011]
$articles[20784]=@"
<article class="gk-clean-article">
$(Figure 'apl.png' 'Geöffneter Kupfer-APL mit Mehraderkabel und Anschlussklemmen.' 'APL: Messpunkt zur Trennung von Betreiber-Kupfernetz und gebäudeseitiger Endleitung.')
<h2>Warum wird am APL gemessen?</h2><p>Die Messung am APL trennt das Betreiber-Kupfernetz von der gebäudeseitigen Endleitung. Sie beantwortet eine konkrete Frage: Kommt das DSL-Signal bereits am Hausanschluss fehlerhaft an oder entsteht die Verschlechterung erst zwischen APL und erster TAE?</p>
<h2>Messvergleich in der Praxis</h2><table><thead><tr><th>Ergebnis</th><th>Einordnung</th></tr></thead><tbody><tr><td>APL und erste TAE ähnlich</td><td>Endleitung verursacht wahrscheinlich keinen großen zusätzlichen Verlust.</td></tr><tr><td>APL deutlich besser als erste TAE</td><td>Endleitung, Klemmstelle, Abzweigung oder TAE prüfen.</td></tr><tr><td>Bereits am APL auffällig</td><td>Fehler im Betreiber-Kupfernetz oder am Port weiter eingrenzen.</td></tr></tbody></table>
<h2>Welche Werte zählen?</h2><p>Je nach Messgerät werden unter anderem Synchronisation, erreichbare Datenrate, Störabstand, Dämpfung und Fehler betrachtet. Ein WLAN-Speedtest ersetzt diesen Messvergleich nicht.</p>
<h2>Vorbereitung</h2><ul><li>APL und erste TAE zugänglich machen.</li><li>Router, Netzteil und DSL-Kabel bereithalten.</li><li>Abbruchzeiten und Wetterbezug notieren.</li><li>APL nicht selbst öffnen.</li></ul>
$(Sources)
</article>
"@

$targets=@(
  @{id=26206;slug='dsl-bauteile-im-haus'},@{id=3015;slug='dslam-erklaert'},@{id=5006;slug='dslam-erklaert-voll'},
  @{id=20803;slug='dsl-stoerungen-verstehen'},@{id=3011;slug='tae-erklaert'},@{id=5002;slug='tae-erklaert-voll'},
  @{id=20784;slug='warum-misst-der-techniker-am-apl'}
)
$rows=@()
foreach($target in $targets){
  $id=[long]$target.id;$new=[string]$articles[$id]
  $old=[string](Read-Post $id).content
  if([string]::IsNullOrWhiteSpace($old)){throw "Leerer Ausgangsinhalt: $id"}
  $status=if((Strip $old)-ceq(Strip $new)){'UNCHANGED'}elseif($Mode-eq'Preview'){'READY'}else{'UPDATED'}
  if($status-eq'UPDATED'){
    [IO.File]::WriteAllText((Join-Path $backup ("post-$id-$($target.slug).html")),$old,[Text.UTF8Encoding]::new($false))
    Save-Post $id $new
  }
  $rows+=[pscustomobject]@{id=$id;slug=$target.slug;status=$status}
}
if($Mode-eq'Apply'){
  $cache=Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/clear-cache') -Method Post -Headers $headers -ContentType 'application/json' -Body '{}' -TimeoutSec 90
  if($cache.cache_cleared-ne$true){throw 'Cache-Leerung nicht bestätigt.'}
  $checks=@(
    @{url='/dsl-bauteile-im-haus/';must='Der korrekte Signalweg';forbid='tal.png'},
    @{url='/dslam-erklaert/';must='MFG mit DSLAM/MSAN → KVz';forbid='dslam-msan.png'},
    @{url='/dsl-stoerungen-verstehen/';must='DSL-Störungen systematisch eingrenzen';forbid='glasfaser.png'},
    @{url='/tae-erklaert/';must='Gf-AP, Gf-TA und ONT gehören dagegen';forbid='Prüfen Sie Gf-AP'},
    @{url='/warum-misst-der-techniker-am-apl/';must='Die Messung am APL trennt';forbid='ONT neu starten'}
  )
  foreach($check in $checks){
    $html=[string](Invoke-WebRequest ($site+$check.url+'?dsl_batch_01='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -UseBasicParsing -TimeoutSec 90).Content
    $text=Strip $html
    if($text-notlike('*'+$check.must+'*')){throw "Öffentliche Pflichtaussage fehlt: $($check.url)"}
    if($html-like('*'+$check.forbid+'*')){throw "Öffentlicher Altfehler vorhanden: $($check.url) / $($check.forbid)"}
  }
}
$rows|Export-Csv (Join-Path $report "dsl-cluster-batch-01-$Mode-$stamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host ("FERTIG: Modus=$Mode | Ziele=$($targets.Count) | Aktualisiert="+@($rows|Where-Object status -eq 'UPDATED').Count+" | Fehler=0")
