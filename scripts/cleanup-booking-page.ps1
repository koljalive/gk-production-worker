param([string]$EnvFile='.\.env')
$ErrorActionPreference='Stop'
$v=@{};Get-Content $EnvFile|Where-Object{$_-match'^[^#].*='}|ForEach-Object{$p=$_-split'=',2;$v[$p[0].Trim()]=$p[1].Trim()}
foreach($n in @('GK_SITE_URL','GK_UNIFIED_API_TOKEN')){if([string]::IsNullOrWhiteSpace($v[$n])){throw "$n fehlt."}}
$site=$v.GK_SITE_URL.TrimEnd('/')
$headers=@{Authorization='Bearer '+$v.GK_UNIFIED_API_TOKEN}
$base=$site+'/wp-json/gk-unified-api/v1/'
$id=21066
$body=[Text.Encoding]::UTF8.GetBytes('{"id":21066}')
$post=Invoke-RestMethod ($base+'read-post') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $body
$old=[string]$post.content
$new=@'
<div class="gkpr" data-gk-clean="booking-v2">
<section class="gkpr-hero">
<p class="gkpr-kicker">TARIF UND ANSCHLUSSART PRÜFEN</p>
<h2>Internet buchen: erst Technik klären, dann Tarif wählen</h2>
<p>Ein hoher Tarifwert allein sagt wenig darüber aus, was am Standort wirklich ankommt. Prüfen Sie zuerst die verfügbare Anschlussart, den Übergabepunkt im Haus und die benötigte Leistung. Danach lässt sich ein Angebot sinnvoll vergleichen.</p>
</section>
<section class="gkpr-section">
<h2>Vor der Buchung in vier Schritten</h2>
<ol>
<li><strong>Verfügbarkeit prüfen:</strong> Entscheidend ist die konkrete Adresse, nicht nur der Ortsname.</li>
<li><strong>Anschlussart unterscheiden:</strong> FTTH führt Glasfaser bis ins Gebäude oder in die Wohnung; DSL nutzt auf dem letzten Abschnitt die Kupferleitung.</li>
<li><strong>Bedarf festlegen:</strong> Berücksichtigen Sie gleichzeitige Nutzer, Homeoffice, Uploads, Streaming und die vorhandene Hausverkabelung.</li>
<li><strong>Vertrag lesen:</strong> Prüfen Sie Laufzeit, Bereitstellungsentgelt, Routerkosten, Preis nach einer Aktionsphase und Kündigungsbedingungen direkt beim Anbieter.</li>
</ol>
</section>
<section class="gkpr-section">
<h2>Technik vor dem Termin vorbereiten</h2>
<div class="gkpr-grid">
<article class="gkpr-card"><h3>Glasfaseranschluss planen</h3><p>Leitungsweg, Gf-AP, Gf-TA und ONT vor der Montage richtig einordnen.</p><p><a href="https://glasfaser-kompass.de/glasfaser/">Zum Bereich Glasfaser</a></p></article>
<article class="gkpr-card"><h3>Router passend auswählen</h3><p>Prüfen, ob Modem, ONT oder ein integriertes Glasfasermodul benötigt wird.</p><p><a href="https://glasfaser-kompass.de/router/">Zum Bereich Router</a></p></article>
<article class="gkpr-card"><h3>WLAN realistisch planen</h3><p>Tarifgeschwindigkeit und Funkabdeckung sind zwei getrennte Themen.</p><p><a href="https://glasfaser-kompass.de/wlan-heimnetz/">Zum Bereich WLAN</a></p></article>
</div>
</section>
<section class="gkpr-note"><h2>Transparenzhinweis</h2><p>Der folgende Verfügbarkeitscheck ist ein Affiliate-Link. Wenn darüber ein Vertrag zustande kommt, kann Glasfaser-Kompass eine Provision erhalten. Für Sie entstehen dadurch keine zusätzlichen Kosten. Verbindliche Preise und Vertragsbedingungen zeigt ausschließlich der Anbieter vor Abschluss.</p></section>
<section class="gkpr-cta"><h2>Verfügbarkeit an der eigenen Adresse prüfen</h2><p>Öffnen Sie den Anbieter-Check und vergleichen Sie das Ergebnis anschließend mit den technischen Voraussetzungen im Haus.</p><p><a class="gkpr-btn" href="https://glasfaser-kompass.telekom-profis.de/" target="_blank" rel="nofollow sponsored noopener">Telekom-Verfügbarkeit prüfen (Werbelink)</a></p></section>
</div>
'@
if($old -cmatch 'data-gk-clean="booking-v2"'){$new=$old -replace 'gkpr-button','gkpr-btn';if($new -ceq $old){Write-Host 'FERTIG: Bereits bereinigt und verifiziert.';exit 0}}
$root=Split-Path -Parent $PSScriptRoot
$backup=Join-Path $root ('backups\booking-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item $backup -ItemType Directory -Force|Out-Null
[IO.File]::WriteAllText((Join-Path $backup 'post-21066.html'),$old,[Text.UTF8Encoding]::new($false))
$payload=@{id=$id;content=$new}|ConvertTo-Json -Compress
Invoke-RestMethod ($base+'update-post') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($payload))|Out-Null
$check=Invoke-RestMethod ($base+'read-post') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $body
$live=[string]$check.content
if($live -cnotmatch 'data-gk-clean="booking-v2"' -or $live -match '\?p=2119[037968]'){throw 'Speicherprüfung fehlgeschlagen.'}
$links=[regex]::Matches($live,'(?is)<a\b[^>]*href=["''](?<u>[^"'']+)')|ForEach-Object{$_.Groups['u'].Value}
foreach($u in $links){if($u -notmatch '^https://'){throw "Unsicheres Linkziel: $u"}}
$cache=Invoke-RestMethod ($base+'clear-cache') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('{}'))
if($cache.cache_cleared -ne $true){throw 'Cache nicht geleert.'}
Write-Host ('FERTIG: Seite=21066 | Aktualisiert=1 | Verifiziert=1 | Backup='+$backup)
