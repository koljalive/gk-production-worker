param([ValidateSet('Preview','Apply')][string]$Mode='Preview')
$ErrorActionPreference='Stop'
$site=$env:GK_SITE_URL.TrimEnd('/')
$token=$env:GK_UNIFIED_API_TOKEN
$wpUser=$env:WP_USERNAME
$wpPass=$env:WP_APPLICATION_PASSWORD
foreach($v in @($site,$token,$wpUser,$wpPass)){if([string]::IsNullOrWhiteSpace($v)){throw 'GK_SITE_URL, GK_UNIFIED_API_TOKEN, WP_USERNAME und WP_APPLICATION_PASSWORD sind erforderlich.'}}
$uh=@{Authorization='Bearer '+$token}
$basic=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($wpUser+':'+$wpPass))
$wh=@{Authorization='Basic '+$basic}
$root=Split-Path -Parent $PSScriptRoot
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$backup=Join-Path $root ('backups\full-site-remediation-'+$stamp)
$report=Join-Path $root 'reports'
New-Item $backup,$report -ItemType Directory -Force|Out-Null
$asset=$site+'/wp-content/plugins/gk-render-guard/assets/'

function Read-Post([long]$id){
  $body=[Text.Encoding]::UTF8.GetBytes((@{id=$id}|ConvertTo-Json -Compress))
  Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/read-post') -Method Post -Headers $uh -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 90
}
function Save-Post([long]$id,[string]$content){
  $body=[Text.Encoding]::UTF8.GetBytes((@{id=$id;content=$content}|ConvertTo-Json -Compress))
  $r=Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/update-post') -Method Post -Headers $uh -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 90
  if($r.updated-ne$true){throw "Speicherung nicht bestätigt: $id"}
  $check=[string](Read-Post $id).content
  if([string]::IsNullOrWhiteSpace($check)){throw "Readback ist leer: $id"}
  if((Strip $check)-cne(Strip $content)){throw "Readback-Text stimmt nicht überein: $id"}
}
function Strip([string]$s){
  $x=[Net.WebUtility]::HtmlDecode([regex]::Replace($s,'(?is)<[^>]+>',' '))
  return ([regex]::Replace($x,'\s+',' ').Trim())
}
function Norm([string]$s){return ([regex]::Replace((Strip $s).ToLowerInvariant(),'[^a-z0-9äöüß]+','')).Trim()}
function Figure([string]$file,[string]$alt,[string]$caption){
  return '<figure class="gk-topic-photo"><img src="'+$asset+$file+'" alt="'+[Net.WebUtility]::HtmlEncode($alt)+'" loading="lazy"><figcaption>'+[Net.WebUtility]::HtmlEncode($caption)+'</figcaption></figure>'
}
function Remove-Injected([string]$x){
  $x=[regex]::Replace($x,'(?is)<figure\b[^>]*>.*?<img\b[^>]*(?:wp-content/plugins/gk-render-guard/assets/|dsl-kupfer-signalweg|ftth-signalweg|koax|coax|placeholder)[^>]*>.*?</figure>','')
  $x=[regex]::Replace($x,'(?is)<img\b[^>]*(?:wp-content/plugins/gk-render-guard/assets/|dsl-kupfer-signalweg|ftth-signalweg|koax|coax|placeholder)[^>]*>','')
  $x=[regex]::Replace($x,'(?is)<section\b[^>]*class=["''][^"'']*(?:gkpr-author|gkpr-affiliate|gk9-authorbox|gk9-tarifcheck)[^"'']*["''][^>]*>.*?</section>','')
  $x=[regex]::Replace($x,'(?is)<!--\s*GK[^>]*-->','')
  return $x
}
function Fix-Links([string]$x,[hashtable]$titles){
  $x=$x.Replace($site+'/author/',$site+'/ueber-den-autor/')
  $x=$x.Replace('/author/','/ueber-den-autor/')
  $x=$x.Replace($site+'/dsl-stoerungen-verstehen-und-beheben/',$site+'/dsl-stoerungen-verstehen/')
  $x=$x.Replace($site+'/glasfaseranschluss-einfach-erklaert-der-grosse-ratgeber/',$site+'/glasfaseranschluss-erklaert/')
  $pattern='(?is)<a\b(?<before>[^>]*?)href=["''](?<url>(?:https?://glasfaser-kompass\.de/)?\?p=211\d+)["''](?<after>[^>]*)>(?<inner>.*?)</a>'
  $x=[regex]::Replace($x,$pattern,{param($m)
    $label=Norm $m.Groups['inner'].Value
    if($titles.ContainsKey($label)){return '<a href="'+$titles[$label]+'">'+$m.Groups['inner'].Value+'</a>'}
    return $m.Groups['inner'].Value
  })
  return $x
}
function Topic-Figure([string]$slug,[string]$title){
  $s=($slug+' '+$title).ToLowerInvariant()
  if($s-match'(impressum|datenschutz|kontakt|startseite|autor|themencluster|lexikon)'){return ''}
  if($s-match'(apl.*gf-ap|gf-ap.*apl)'){
    return '<div class="gk-compare-photos">'+(Figure 'apl.png' 'Geöffneter Kupfer-APL mit Mehraderkabel und Anschlussklemmen.' 'Kupfer-APL: Mehrader-Kupferkabel und Klemmen.')+(Figure 'gf-ap.png' 'Geöffneter Glasfaser-Gebäudeabschlusspunkt mit Fasermanagement.' 'Gf-AP: dünne Glasfasern, Spleißablage und Faserführung.')+'</div>'
  }
  $rules=@(
    @('(apl-tae-signalweg)',''),
    @('(gf[- ]?ta|teilnehmeranschlussdose)','gf-ta.png|Glasfaser-Teilnehmeranschlussdose mit Glasfaseranschluss.|Gf-TA: optische Anschlussdose in Haus oder Wohnung.'),
    @('(gf[- ]?ap|glasfaser.*abschlusspunkt)','gf-ap.png|Geöffneter Glasfaser-Gebäudeabschlusspunkt mit Fasermanagement.|Gf-AP: passiver Abschluss des Glasfasernetzes am Gebäude.'),
    @('(ont|glasfasermodem)','ont.png|ONT mit optischem Eingang, Ethernet-Ausgang und Stromversorgung.|ONT: aktiver Übergang vom optischen Anschluss zu Ethernet.'),
    @('(mfg|multifunktionsgehäuse)','mfg.png|Graues Multifunktionsgehäuse am Straßenrand.|MFG: graues Straßengehäuse mit aktiver Technik.'),
    @('(kvz|kabelverzweiger)','kvz.png|Geöffneter grauer Kabelverzweiger mit Kupfer-Anschlussleisten.|KVz: passiver grauer Kabelverzweiger des Kupfernetzes.'),
    @('(dslam|msan)','dslam-msan.png|DSLAM- oder MSAN-Technik mit Anschlussfeldern.|DSLAM/MSAN: aktive Technik, bei FTTC typischerweise im MFG.'),
    @('(tae)','tae-dose.jpg|Weiße TAE-NFF-Anschlussdose mit drei Buchsen.|TAE: Anschluss- und Messpunkt für DSL in den Kundenräumen.'),
    @('(apl)','apl.png|Geöffneter Kupfer-APL mit Mehraderkabel und Anschlussklemmen.|APL: passiver Gebäudeabschluss des Betreiber-Kupfernetzes.'),
    @('(endleitung|hausverkabelung|tal|kupferleitung)','tal.png|Kupfer-Doppeladern eines Telefon- und DSL-Zugangsnetzes.|Kupfer-Doppeladern im DSL-Zugangs- beziehungsweise Hausnetz.'),
    @('(spleiß|spleiss)','spleissstelle.png|Geordnete Glasfaser-Spleißablage mit geschützten Spleißstellen.|Spleißstelle: dauerhaft verbundene und geschützt abgelegte Fasern.'),
    @('(steckverbinder|lc-stecker|sc-stecker)','steckverbinder.png|Glasfaser-Steckverbinder mit sichtbaren Bauformen.|Optische Steckverbinder müssen sauber, passend und unbeschädigt sein.'),
    @('(splitter)','splitter.png|Passiver optischer Splitter mit Eingang und mehreren Ausgängen.|Optischer Splitter: passive Leistungsverteilung im PON.'),
    @('(speedpipe|mikro(?:rohr|rohrverband))','speedpipe.png|Mikrorohrverband für das Einblasen von Glasfaserkabeln.|Speedpipes führen einblasbare Glasfaserkabel geschützt bis zum Ziel.'),
    @('(nvt|netzverteiler)','nvt.png|Geöffneter passiver Glasfaser-Netzverteiler.|NVT: passiver Verteiler mit Faserführung und Spleißablagen.'),
    @('(olt)','olt.png|Aktive OLT-Technik im Glasfasernetz.|OLT: aktive netzseitige PON-Technik.'),
    @('(pop|point of presence)','pop.png|Technikstandort eines Glasfasernetzes.|PoP: Standort aktiver Netz- und Übertragungstechnik.'),
    @('(muffe)','glasfasermuffe.png|Geöffnete Glasfasermuffe mit Spleißkassetten.|Glasfasermuffe: geschützter passiver Verbindungs- und Abzweigpunkt.'),
    @('(mesh|repeater|access-point|wlan|routerstandort|router-im-keller)','wlan-heimnetz.png|Wohnhaus mit Router, LAN-Verkabelung und WLAN-Versorgung.|Routerstandort, LAN-Anbindung und Funkabdeckung müssen gemeinsam geplant werden.'),
    @('(glasfaser|ftth|faser)','glasfaser.png|Aufgebautes Glasfaserkabel mit Mantel, Zugentlastung und Faser.|Glasfaserkabel: Faser und Schutzaufbau statt Kupfer-Innenleiter.')
  )
  foreach($r in $rules){if($s-match$r[0]){if(-not$r[1]){return ''};$p=$r[1]-split'\|',3;return Figure $p[0] $p[1] $p[2]}}
  return ''
}
function Special-Article([string]$slug){
  if($slug-eq'apl-und-gf-ap-unterschied'){
    $photos=(Topic-Figure $slug 'APL und Gf-AP')
    return @"
<article class="gk-clean-article">$photos
<h2>APL, Gf-AP und Koax-HÜP sicher unterscheiden</h2>
<p>Die drei Gehäuse markieren unterschiedliche Zugangsnetze. Entscheidend sind nicht Farbe oder Größe allein, sondern die ankommende Leitung und die Bauteile im Gehäuse.</p>
<h3>Kupfer-APL</h3><p>Am APL endet das Kupfer-Zugangsnetz für Telefonie und DSL. Erkennbar sind mehradrige Kupferkabel, Doppeladern und Anschlussklemmen. Hinter dem APL führt die Endleitung zur ersten TAE.</p>
<h3>Glasfaser-Gf-AP</h3><p>Am Gf-AP endet die ankommende Glasfaser am Gebäude. Typisch sind dünne Fasern, Spleißschutz, Faserführungen und optische Kupplungen. Von dort führt eine Glasfaser zur Gf-TA oder zum vorgesehenen Netzabschluss.</p>
<h3>Koaxial-HÜP</h3><p>Ein Kabel-HÜP gehört zum Koaxialnetz. Er besitzt Koaxialkabel mit rundem Außenleiter beziehungsweise Schirmung und zentralem Innenleiter. TAE-Doppeladern und Glasfaser-Spleißablagen gehören dort nicht hinein.</p>
<h2>Praktische Zuordnung</h2><table><thead><tr><th>Merkmal</th><th>APL</th><th>Gf-AP</th><th>Koax-HÜP</th></tr></thead><tbody><tr><td>Netz</td><td>Telefon/DSL</td><td>FTTH</td><td>Kabelinternet/TV</td></tr><tr><td>Leitung</td><td>Kupfer-Doppeladern</td><td>Glasfaser</td><td>Koaxialkabel</td></tr><tr><td>Weiterführung</td><td>Endleitung zur TAE</td><td>Glasfaser zur Gf-TA/ONT</td><td>Koax-Verteilnetz</td></tr></tbody></table>
<p><strong>Sicherheit:</strong> Netzabschlüsse nicht eigenmächtig öffnen oder umklemmen. Für Messungen und Arbeiten gelten die Vorgaben des jeweiligen Netzbetreibers.</p>
</article>
"@
  }
  if($slug-eq'router-kaufen-oder-mieten-vergleich'){
    return @"
<article class="gk-clean-article">
<h2>Kaufen oder mieten: Was unterscheidet die beiden Modelle?</h2><p>Die Entscheidung hängt nicht nur vom Gerätepreis ab. Relevant sind Vertragslaufzeit, Support, Austausch im Defektfall, Updateversorgung, benötigte Anschlüsse und die Freiheit bei einem Anbieterwechsel.</p>
<table><thead><tr><th>Kriterium</th><th>Mietrouter</th><th>Kaufrouter</th></tr></thead><tbody><tr><td>Kosten</td><td>laufende monatliche Kosten</td><td>einmaliger Kaufpreis</td></tr><tr><td>Defekt</td><td>Austausch nach Anbieterbedingungen</td><td>Gewährleistung/Garantie des Verkäufers oder Herstellers</td></tr><tr><td>Support</td><td>Anbieter kennt das bereitgestellte Modell</td><td>mehr Eigenverantwortung bei Einrichtung und Fehlersuche</td></tr><tr><td>Flexibilität</td><td>oft an Vertrag und Rückgabe gebunden</td><td>Gerät bleibt Eigentum des Käufers</td></tr></tbody></table>
<h2>Vor der Entscheidung prüfen</h2><ul><li>Anschlussart: DSL, externes ONT oder direkter Glasfaseranschluss</li><li>benötigte Telefonie-, LAN- und WLAN-Funktionen</li><li>Gesamtkosten über die geplante Nutzungszeit</li><li>Rückgabepflichten und Austauschbedingungen</li><li>Hersteller-Updates und erwartete Nutzungsdauer</li></ul>
<h2>Praxisempfehlung</h2><p>Wer möglichst wenig Einrichtungsaufwand und einen klaren Ansprechpartner möchte, fährt mit dem passenden Mietgerät häufig einfacher. Ein Kaufgerät lohnt sich eher, wenn die technischen Anforderungen feststehen, das Modell länger genutzt werden soll und die Gesamtkosten günstiger sind.</p>
<p>Vor dem Kauf immer die Schnittstelle des Anschlusses prüfen: Ein DSL-Router benötigt ein integriertes DSL-Modem. Hinter einem ONT wird dagegen ein Ethernet-WAN-Anschluss benötigt.</p>
</article>
"@
  }
  return $null
}

$items=@()
foreach($kind in @('posts','pages')){
  for($page=1;$page-le20;$page++){
    try{$batch=@(Invoke-RestMethod ($site+"/wp-json/wp/v2/$kind`?status=publish&per_page=100&page=$page&_fields=id,slug,title,link") -TimeoutSec 90)}catch{if($_.Exception.Response-and[int]$_.Exception.Response.StatusCode-eq400){break}else{throw}}
    if($batch.Count-eq1-and$batch[0]-is[Array]){$batch=@($batch[0])}
    if(-not$batch.Count){break};$items+=@($batch|ForEach-Object{[pscustomobject]@{kind=$kind;id=[long]$_.id;slug=[string]$_.slug;title=[string]$_.title.rendered;link=[string]$_.link}})
    if($batch.Count-lt100){break}
  }
}
if($items.Count-lt300){throw "Unvollständige Inventur: $($items.Count) Inhalte"}
$titleIndex=@{}
foreach($i in $items){$n=Norm $i.title;if($n-and-not$titleIndex.ContainsKey($n)){$titleIndex[$n]=$i.link}}
$rows=@();$failures=@()
foreach($i in $items){
  try{
    $old=[string](Read-Post $i.id).content
    $new=Remove-Injected $old
    $new=Fix-Links $new $titleIndex
    $new=$new.Replace('Verantwortlich gemä §','Verantwortlich gemäß §')
    $new=[regex]::Replace($new,'(?is)(<section\b[^>]*>.*?</section>)(?:\s*\1)+','$1')
    $new=[regex]::Replace($new,'(?is)(<p\b[^>]*>\s*Die wichtigste Regel lautet: Anschluss, Router, Verkabelung, WLAN und Endgerät müssen getrennt betrachtet werden\.?\s*</p>)(?:\s*\1)+','$1')
    $special=Special-Article $i.slug
    if($null-ne$special){$new=$special.Trim()}else{
      $fig=Topic-Figure $i.slug $i.title
      if($fig){$new=$fig+"`n"+$new.Trim()}
    }
    if($i.slug-match'^(impressum|datenschutz|kontakt)'){
      $new=[regex]::Replace($new,'(?is)<section\b[^>]*class=["''][^"'']*(?:affiliate|tarifcheck)[^"'']*["''][^>]*>.*?</section>','')
      $new=[regex]::Replace($new,'(?is)<h2[^>]*>\s*Internet an Ihrer Adresse verfügbar\?\s*</h2>.*?(?=<h2|$)','')
    }
    $new=$new.Trim()
    $changed=$new-cne$old
    if($changed-and(Strip $new)-ceq(Strip $old)){$changed=$false}
    if($changed-and$Mode-eq'Apply'){
      [IO.File]::WriteAllText((Join-Path $backup ("post-$($i.id)-$($i.slug).html")),$old,[Text.UTF8Encoding]::new($false))
      Save-Post $i.id $new
    }
    $rows+=[pscustomobject]@{id=$i.id;kind=$i.kind;slug=$i.slug;changed=$changed;status=if($changed){if($Mode-eq'Apply'){'UPDATED_AND_READBACK_VERIFIED'}else{'READY'}}else{'UNCHANGED'}}
  }catch{$failures+=[pscustomobject]@{id=$i.id;slug=$i.slug;error=$_.Exception.Message}}
}
if($failures.Count){$failures|Export-Csv (Join-Path $report "full-site-failures-$stamp.csv") -NoTypeInformation -Encoding UTF8;throw "Abbruch: $($failures.Count) Inhalte fehlgeschlagen."}

if($Mode-eq'Apply'){
  $cache=Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/clear-cache') -Method Post -Headers $uh -ContentType 'application/json' -Body '{}' -TimeoutSec 90
  if($cache.cache_cleared-ne$true){throw 'Cache-Leerung nicht bestätigt.'}
  foreach($slug in @('apl-tae-signalweg','apl-und-gf-ap-unterschied','router-kaufen-oder-mieten-vergleich','impressum-2','datenschutz-2')){
    $it=$items|Where-Object slug -eq $slug|Select-Object -First 1
    $public=[string](Invoke-WebRequest ($it.link+'?final_audit='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -UseBasicParsing -TimeoutSec 90).Content
    if($public-match'(?is)<img\b[^>]*(?:dsl-kupfer-signalweg|ftth-signalweg|koax_huep|gk-symbol-koax)[^>]*>'){throw "Öffentlich gerendertes Altbild weiterhin vorhanden: $slug"}
    if($slug-eq'apl-und-gf-ap-unterschied'-and($public-notmatch'apl\.png'-or$public-notmatch'gf-ap\.png')){throw 'APL/Gf-AP-Vergleich nicht vollständig öffentlich.'}
    if($slug-eq'impressum-2'-and$public-notmatch'Verantwortlich gemäß § 18 Abs\. 2 MStV'){throw 'Korrigierte Verantwortlichenangabe ist öffentlich nicht nachgewiesen.'}
  }
}
$rows|Export-Csv (Join-Path $report "full-site-remediation-$Mode-$stamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host ("FERTIG: Modus=$Mode | Inventar=$($items.Count) | Geändert="+@($rows|Where-Object changed).Count+" | Fehler=0")
