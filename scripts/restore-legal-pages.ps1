param([string]$EnvFile='.\.env')
$ErrorActionPreference='Stop'
$v=@{};Get-Content $EnvFile|Where-Object{$_-match'^[^#].*='}|ForEach-Object{$p=$_-split'=',2;$v[$p[0].Trim()]=$p[1].Trim()}
foreach($n in @('GK_SITE_URL','GK_UNIFIED_API_TOKEN')){if([string]::IsNullOrWhiteSpace($v[$n])){throw "$n fehlt."}}
$site=$v.GK_SITE_URL.TrimEnd('/');$headers=@{Authorization='Bearer '+$v.GK_UNIFIED_API_TOKEN};$base=$site+'/wp-json/gk-unified-api/v1/'
$impressum=@'
<div class="gkpr" data-gk-legal="impressum-v2">
<section class="gkpr-section"><h2>Angaben gem&#228;&#223; &#167; 5 DDG</h2><p><strong>IT Solutions</strong><br>Inhaber: Kolja Seebauer<br>Beisterweg 25<br>44227 Dortmund<br>Deutschland</p></section>
<section class="gkpr-section"><h2>Kontakt</h2><p>Telefon: <a href="tel:+4923113700755">0231 13 70 07 55</a><br>Mobil: <a href="tel:+4915122443820">0151 22 44 38 20</a><br>E-Mail: <a href="mailto:kolja.seebauer@mail.de">kolja.seebauer@mail.de</a></p></section>
<section class="gkpr-section"><h2>Verantwortlich gem&#228; &#167; 18 Abs. 2 MStV</h2><p>Kolja Seebauer<br>Beisterweg 25<br>44227 Dortmund</p></section>
<section class="gkpr-section"><h2>Umsatzsteuer</h2><p>Es besteht keine Umsatzsteuer-Identifikationsnummer.</p></section>
<section class="gkpr-section"><h2>Verbraucherstreitbeilegung</h2><p>Wir sind nicht bereit oder verpflichtet, an Streitbeilegungsverfahren vor einer Verbraucherschlichtungsstelle teilzunehmen.</p></section>
</div>
'@
$datenschutz=@'
<div class="gkpr" data-gk-legal="datenschutz-v1">
<section class="gkpr-section"><h2>1. Verantwortlicher</h2><p>IT Solutions, Inhaber Kolja Seebauer, Beisterweg 25, 44227 Dortmund<br>Telefon: <a href="tel:+4923113700755">0231 13 70 07 55</a><br>Mobil: <a href="tel:+4915122443820">0151 22 44 38 20</a><br>E-Mail: <a href="mailto:kolja.seebauer@mail.de">kolja.seebauer@mail.de</a></p></section>
<section class="gkpr-section"><h2>2. Hosting durch IONOS</h2><p>Diese Website wird bei der IONOS SE gehostet. Beim Aufruf der Website verarbeitet der Hostinganbieter technisch erforderliche Verbindungsdaten. Dazu k&#246;nnen insbesondere IP-Adresse, Datum und Uhrzeit des Zugriffs, aufgerufene Datei, Referrer-URL, Browsertyp, Betriebssystem und HTTP-Status geh&#246;ren.</p><p>Die Verarbeitung erfolgt zur sicheren und stabilen Bereitstellung der Website auf Grundlage von Art. 6 Abs. 1 lit. f DSGVO. Unser berechtigtes Interesse liegt im sicheren Betrieb und in der Abwehr von Missbrauch. Mit dem Hostinganbieter besteht, soweit erforderlich, ein Vertrag zur Auftragsverarbeitung. Protokolldaten werden gel&#246;scht, sobald sie f&#252;r diese Zwecke nicht mehr erforderlich sind, sofern keine gesetzlichen Aufbewahrungspflichten entgegenstehen.</p></section>
<section class="gkpr-section"><h2>3. Verschl&#252;sselte &#220;bertragung</h2><p>Die Website verwendet TLS-Verschl&#252;sselung. Dadurch werden Daten, die zwischen Ihrem Browser und dem Server &#252;bertragen werden, vor dem unbefugten Mitlesen gesch&#252;tzt.</p></section>
<section class="gkpr-section"><h2>4. Kontaktaufnahme</h2><p>Wenn Sie uns per E-Mail oder Telefon kontaktieren, verarbeiten wir die von Ihnen mitgeteilten Daten zur Bearbeitung Ihrer Anfrage. Rechtsgrundlage ist Art. 6 Abs. 1 lit. b DSGVO bei vorvertraglichen oder vertraglichen Anliegen und ansonsten Art. 6 Abs. 1 lit. f DSGVO. Unser berechtigtes Interesse liegt in der Beantwortung von Anfragen. Die Daten werden gel&#246;scht, wenn die Anfrage abschlie&#223;end bearbeitet ist und keine gesetzlichen Aufbewahrungspflichten bestehen.</p></section>
<section class="gkpr-section"><h2>5. Cookies und externe Inhalte</h2><p>Bei der technischen Pr&#252;fung der &#246;ffentlichen Website waren keine Analyse- oder Marketing-Skripte, externen Schriftarten, Video-Frames oder Kontaktformulare eingebunden. Soweit WordPress oder das verwendete Design technisch notwendige Cookies setzt, erfolgt dies zur Bereitstellung der Website. F&#252;r das Speichern oder Auslesen technisch nicht notwendiger Informationen w&#228;re vorab eine Einwilligung nach &#167; 25 TDDDG erforderlich.</p></section>
<section class="gkpr-section"><h2>6. Affiliate-Links</h2><p>Einzelne, ausdr&#252;cklich gekennzeichnete Links f&#252;hren zu externen Anbietern, insbesondere zum Telekom-Verf&#252;gbarkeitscheck oder zu Amazon. Erst wenn Sie einen solchen Link anklicken, wird eine Verbindung zum jeweiligen Anbieter hergestellt. Dabei k&#246;nnen insbesondere Ihre IP-Adresse, Browserinformationen und die Herkunftsseite verarbeitet werden. F&#252;r die weitere Verarbeitung ist der jeweilige Anbieter verantwortlich. Glasfaser-Kompass kann bei einem Vertragsabschluss oder Kauf eine Provision erhalten; f&#252;r Sie entstehen dadurch keine zus&#228;tzlichen Kosten.</p><p>Die Einbindung normaler externer Links erfolgt auf Grundlage unseres berechtigten Interesses an der Finanzierung und thematischen Erg&#228;nzung des Angebots nach Art. 6 Abs. 1 lit. f DSGVO. Die Links sind mit <code>sponsored</code> und <code>nofollow</code> gekennzeichnet.</p></section>
<section class="gkpr-section"><h2>7. Speicherdauer</h2><p>Personenbezogene Daten werden nur so lange gespeichert, wie es f&#252;r den jeweiligen Zweck erforderlich ist oder gesetzliche Aufbewahrungspflichten bestehen. Anschlie&#223;end werden sie gel&#246;scht oder anonymisiert.</p></section>
<section class="gkpr-section"><h2>8. Ihre Rechte</h2><p>Sie haben nach Ma&#223;gabe der DSGVO das Recht auf Auskunft, Berichtigung, L&#246;schung, Einschr&#228;nkung der Verarbeitung, Daten&#252;bertragbarkeit und Widerspruch. Eine erteilte Einwilligung k&#246;nnen Sie mit Wirkung f&#252;r die Zukunft widerrufen. Zur Aus&#252;bung Ihrer Rechte gen&#252;gt eine Nachricht an die oben genannte E-Mail-Adresse.</p></section>
<section class="gkpr-section"><h2>9. Beschwerderecht</h2><p>Sie haben das Recht, sich bei einer Datenschutzaufsichtsbeh&#246;rde zu beschweren. F&#252;r Nordrhein-Westfalen ist dies die Landesbeauftragte f&#252;r Datenschutz und Informationsfreiheit Nordrhein-Westfalen: <a href="https://www.ldi.nrw.de/" rel="noopener noreferrer">www.ldi.nrw.de</a>.</p></section>
<section class="gkpr-section"><h2>10. Stand und Aktualisierung</h2><p>Stand: 17. Juli 2026. Diese Datenschutzerkl&#228;rung wird angepasst, wenn sich die Website oder die eingesetzten Dienste &#228;ndern.</p></section>
</div>
'@
$pages=@(@{id=1011;marker='impressum-v2';content=$impressum},@{id=1012;marker='datenschutz-v1';content=$datenschutz});$root=Split-Path -Parent $PSScriptRoot;$backup=Join-Path $root('backups\legal-'+(Get-Date -Format 'yyyyMMdd-HHmmss'));New-Item $backup -ItemType Directory -Force|Out-Null
foreach($p in $pages){
 $readBody=[Text.Encoding]::UTF8.GetBytes((@{id=$p.id}|ConvertTo-Json -Compress))
 $before=Invoke-RestMethod ($base+'read-post') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $readBody
 $old=[string]$before.content
 if($old -cmatch ('data-gk-legal="'+$p.marker+'"')){Write-Host("$($p.id): ALREADY_VERIFIED");continue}
 [IO.File]::WriteAllText((Join-Path $backup ("post-$($p.id).html")),$old,[Text.UTF8Encoding]::new($false))
 $payload=@{id=$p.id;content=$p.content}|ConvertTo-Json -Compress
 Invoke-RestMethod ($base+'update-post') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($payload))|Out-Null
 $after=Invoke-RestMethod ($base+'read-post') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $readBody
 $live=[string]$after.content
 if($live -cnotmatch ('data-gk-legal="'+$p.marker+'"') -or $live -cmatch 'Premium-Ratgeber|Expert Upgrade|gk-related-box'){throw "Nachpruefung fehlgeschlagen: $($p.id)"}
 Write-Host("$($p.id): UPDATED_AND_VERIFIED")
}
$public=Invoke-WebRequest ($site+'/impressum-2/?_gk='+(Get-Date -Format HHmmssfff)) -UseBasicParsing -TimeoutSec 45
if([int]$public.StatusCode-ne200){throw 'Impressum ist nicht oeffentlich erreichbar.'}
$publicText=[Net.WebUtility]::HtmlDecode([regex]::Replace([string]$public.Content,'(?is)<[^>]+>',' '))
foreach($required in @('IT Solutions','Kolja Seebauer','Beisterweg 25','44227 Dortmund','0231 13 70 07 55','0151 22 44 38 20','kolja.seebauer@mail.de','18 Abs. 2 MStV')){if($publicText-notmatch[regex]::Escape($required)){throw "Impressum-Angabe fehlt live: $required"}}
$home=Invoke-WebRequest ($site+'/?_gk='+(Get-Date -Format HHmmssfff)) -UseBasicParsing -TimeoutSec 45
if([string]$home.Content-notmatch'(?i)href=["''][^"'']*impressum-2/?["'']'){throw 'Impressum ist auf der Startseite nicht verlinkt.'}
Write-Host 'IMPRESSUM_LIVE: HTTP=200 | Pflichtangaben=VERIFIED | Startseitenlink=VERIFIED'
$cache=Invoke-RestMethod ($base+'clear-cache') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('{}'))
if($cache.cache_cleared -ne $true){throw 'Cache nicht geleert.'}
Write-Host ('FERTIG: Rechtstext-Seiten=2 | Verifiziert=2 | Backup='+$backup)
