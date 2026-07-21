<?php
/**
 * Plugin Name: GK Final Frontend Guard
 * Description: Bereinigt dynamische Altlinks, Rechtsseiten-Blöcke, Autorenanzeige und Theme-Reste nach dem Rendern.
 * Version: 1.0.7
 * Author: IT Solutions – Kolja Seebauer
 * Requires at least: 6.4
 * Requires PHP: 8.0
 */
if (!defined('ABSPATH')) { exit; }

final class GK_Final_Frontend_Guard {
    private static bool $is_legal = false;
    private static bool $is_front = false;
    private static string $slug = '';
    private const AUTHOR_NAME = 'Kolja Seebauer';
    private const AUTHOR_URL  = 'https://glasfaser-kompass.de/ueber-den-autor/';
    private const HOME_TITLE  = 'Glasfaser, DSL, Router und WLAN aus der Praxis';

    public static function boot(): void {
        add_action('template_redirect', [self::class, 'start_buffer'], PHP_INT_MIN);
        add_filter('the_author', [self::class, 'author_name'], PHP_INT_MAX);
        add_filter('get_the_author_display_name', [self::class, 'author_name'], PHP_INT_MAX);
        add_filter('author_link', [self::class, 'author_link'], PHP_INT_MAX);
        add_filter('astra_footer_copyright', [self::class, 'footer'], PHP_INT_MAX);
        add_filter('rank_math/opengraph/facebook/image', [self::class, 'social_image'], PHP_INT_MAX);
        add_filter('rank_math/opengraph/twitter/image', [self::class, 'social_image'], PHP_INT_MAX);
        add_filter('rank_math/opengraph/twitter/card_type', static fn() => 'summary_large_image', PHP_INT_MAX);
        add_action('wp_head', [self::class, 'legal_visibility_guard'], PHP_INT_MAX);
        add_action('wp', [self::class, 'install_content_repairs'], PHP_INT_MAX);
    }

    public static function install_content_repairs(): void {
        if (is_admin() || wp_doing_ajax() || wp_is_json_request() || !is_singular()) { return; }
        /* Registered on wp, after normal plugin bootstrap. This makes the repair
           filter run after GK Render Guard even when both use PHP_INT_MAX. */
        add_filter('the_content', [self::class, 'repair_content'], PHP_INT_MAX);
    }

    private static function photo(string $file, string $alt, string $caption): string {
        $url = home_url('/wp-content/plugins/gk-render-guard/assets/' . $file);
        return '<figure class="gk-topic-photo"><img src="' . esc_url($url) . '" alt="' . esc_attr($alt) . '" loading="lazy"><figcaption>' . esc_html($caption) . '</figcaption></figure>';
    }

    private static function sources(): string {
        return '<h2>Offizielle Quellen</h2><ul><li><a href="https://www.bundesnetzagentur.de/DE/Vportal/TK/InternetTelefon/Internetgeschwindigkeit/start.html">Bundesnetzagentur: Internetzugang und Geschwindigkeit</a></li><li><a href="https://www.telekom.de/hilfe/internet-telefonie/internet">Deutsche Telekom: Hilfe zu Internet und Anschluss</a></li></ul>';
    }

    public static function repair_content(string $content): string {
        if (!is_singular() || !in_the_loop() || !is_main_query()) { return $content; }
        $slug = (string) get_post_field('post_name', get_queried_object_id());
        $articles = self::repair_articles();
        return isset($articles[$slug]) ? $articles[$slug] : $content;
    }

    private static function repair_articles(): array {
        $sources = self::sources();
        return [
            'dsl-bauteile-im-haus' => '<article class="gk-clean-article"><h2>DSL-Bauteile im Haus eindeutig erkennen</h2>'
                . self::photo('apl.png', 'Geöffneter Kupfer-APL mit Mehraderkabel und Anschlussklemmen.', 'APL: passiver Abschluss des Betreiber-Kupfernetzes am Gebäude.')
                . self::photo('tae-dose.jpg', 'Weiße TAE-NFF-Anschlussdose mit drei Buchsen.', 'Erste TAE: Anschluss- und Messpunkt in den Kundenräumen. Foto: Uwe Schwöbel, GNU FDL 1.2, via Wikimedia Commons.')
                . '<h2>Der korrekte Signalweg</h2><p><strong>MFG mit DSLAM/MSAN → KVz → Kupfer-Zugangsnetz → APL → Endleitung → erste TAE → DSL-Router</strong></p><h3>APL</h3><p>Der APL beendet das öffentliche Kupfer-Zugangsnetz am Gebäude. Mehraderkabel, Doppeladern und Anschlussklemmen unterscheiden ihn von einem Glasfaser-Gf-AP und einem Koax-HÜP.</p><h3>Endleitung</h3><p>Die Endleitung ist das Kupfer-Adernpaar zwischen APL und erster TAE. Abzweigungen, lose Klemmstellen und parallel geschaltete Dosen können DSL-Werte verschlechtern.</p><h3>Erste TAE und Router</h3><p>Die erste TAE ist der reguläre Anschluss- und Messpunkt. Das DSL-Modem im Router synchronisiert sich mit dem DSLAM/MSAN. Erst danach werden LAN und WLAN getrennt beurteilt.</p><h2>Vor einem Technikertermin</h2><ul><li>APL und erste TAE zugänglich machen.</li><li>Router, Netzteil und DSL-Kabel bereithalten.</li><li>Weitere Dosen und Abzweigungen nennen.</li><li>APL nicht selbst öffnen oder umklemmen.</li></ul>' . $sources . '</article>',
            'dslam-erklaert' => '<article class="gk-clean-article">' . self::photo('mfg.png', 'Graues Multifunktionsgehäuse am Straßenrand.', 'Bei FTTC/VDSL befindet sich die aktive DSLAM-/MSAN-Technik typischerweise im grauen MFG.') . '<h2>Was macht ein DSLAM oder MSAN?</h2><p>Der DSLAM stellt DSL-Verbindungen für viele Teilnehmer bereit. Bei FTTC/VDSL sitzt diese aktive Technik typischerweise <strong>im Multifunktionsgehäuse</strong>. Das MFG ist das Gehäuse und keine zusätzliche Signalstufe.</p><h2>Der korrekte FTTC-/VDSL-Signalweg</h2><p><strong>Glasfaserzuführung → MFG mit DSLAM/MSAN → KVz → Kupfer-Zugangsnetz → APL → Endleitung → erste TAE → DSL-Router</strong></p><p>Der KVz ist ein eigener passiver Kabelverzweiger. MFG und KVz sind üblicherweise graue Straßengehäuse.</p><h2>Abgrenzung zu FTTH</h2><p>Bei FTTH gibt es auf der Teilnehmerstrecke keinen DSLAM. Dort sind OLT, passives Glasfasernetz, Gf-AP, Gf-TA und gegebenenfalls ONT relevant.</p>' . $sources . '</article>',
            'dsl-stoerungen-verstehen' => '<article class="gk-clean-article">' . self::photo('apl.png', 'Geöffneter Kupfer-APL mit Mehraderkabel und Anschlussklemmen.', 'Bei DSL führt die Gebäudediagnose vom Kupfer-APL über Endleitung und erste TAE zum Router.') . '<h2>DSL-Störungen systematisch eingrenzen</h2><ol><li><strong>Synchronisation prüfen:</strong> Ohne DSL-Synchronisation liegt der Fehler vor der Internet-Einwahl.</li><li><strong>Routerwerte sichern:</strong> Datenrate, Störabstand, Dämpfung und Fehlerzähler notieren.</li><li><strong>APL und erste TAE vergleichen:</strong> Schlechtere Werte an der TAE sprechen häufig für Endleitung, Klemmstelle oder Dose.</li><li><strong>LAN vor WLAN testen:</strong> Das Heimnetz erst nach stabiler DSL-Verbindung beurteilen.</li></ol><h2>Typische Einordnung</h2><table><thead><tr><th>Beobachtung</th><th>Zu prüfender Bereich</th></tr></thead><tbody><tr><td>Keine Synchronisation</td><td>Port, Kupfernetz, APL, Endleitung, TAE oder DSL-Kabel</td></tr><tr><td>Abbrüche bei Regen</td><td>Feuchtigkeit an Muffe, Kabel, APL oder Klemmstelle</td></tr><tr><td>Am APL gut, an der TAE schlecht</td><td>Endleitung, Abzweigung oder TAE</td></tr><tr><td>LAN stabil, WLAN langsam</td><td>Routerstandort, Funkkanal und Heimnetz</td></tr></tbody></table><p>Ein Speedtest allein trennt Anschlussfehler nicht von WLAN-, LAN- oder Endgeräteproblemen.</p>' . $sources . '</article>',
            'tae-erklaert' => '<article class="gk-clean-article">' . self::photo('tae-dose.jpg', 'Weiße TAE-NFF-Anschlussdose mit drei Buchsen.', 'TAE-Dose: Anschluss- und Messpunkt eines kupferbasierten Telefon- oder DSL-Anschlusses. Foto: Uwe Schwöbel, GNU FDL 1.2, via Wikimedia Commons.') . '<h2>Was ist eine TAE?</h2><p>Die Telekommunikations-Anschluss-Einheit ist eine Anschlussdose für kupferbasierte Telefon- und DSL-Anschlüsse. Die erste TAE liegt hinter APL und Endleitung. Gf-AP, Gf-TA und ONT gehören dagegen zu Glasfaseranschlüssen.</p><h2>Warum ist die erste TAE wichtig?</h2><p>Der Vergleich einer Messung am APL mit der Messung an der ersten TAE zeigt, ob Endleitung oder Dose die DSL-Verbindung verschlechtern.</p><h2>Typische Fehler</h2><ul><li>lose oder korrodierte Kontakte</li><li>parallel angeschlossene weitere Dosen</li><li>unnötige Verlängerungen und Abzweigungen</li><li>beschädigte Anschlussleitung zum Router</li></ul><p>Dose freiräumen, DSL-Kabel kontrollieren und Routerwerte dokumentieren. Feste Leitungen nicht eigenmächtig umklemmen.</p>' . $sources . '</article>',
            'warum-misst-der-techniker-am-apl' => '<article class="gk-clean-article">' . self::photo('apl.png', 'Geöffneter Kupfer-APL mit Mehraderkabel und Anschlussklemmen.', 'APL: Messpunkt zur Trennung von Betreiber-Kupfernetz und gebäudeseitiger Endleitung.') . '<h2>Warum wird am APL gemessen?</h2><p>Die Messung am APL trennt das Betreiber-Kupfernetz von der gebäudeseitigen Endleitung. Sie zeigt, ob das DSL-Signal bereits am Hausanschluss fehlerhaft ankommt oder erst zwischen APL und erster TAE schlechter wird.</p><h2>Messvergleich in der Praxis</h2><table><thead><tr><th>Ergebnis</th><th>Einordnung</th></tr></thead><tbody><tr><td>APL und erste TAE ähnlich</td><td>Endleitung verursacht wahrscheinlich keinen großen zusätzlichen Verlust.</td></tr><tr><td>APL deutlich besser als erste TAE</td><td>Endleitung, Klemmstelle, Abzweigung oder TAE prüfen.</td></tr><tr><td>Bereits am APL auffällig</td><td>Fehler im Betreiber-Kupfernetz oder am Port weiter eingrenzen.</td></tr></tbody></table><p>Ein WLAN-Speedtest ersetzt diesen Messvergleich nicht. APL und erste TAE sollten vor dem Termin zugänglich sein; den APL nicht selbst öffnen.</p>' . $sources . '</article>',
            'ftth-anschlussarten-erklaert' => '<article class="gk-clean-article">' . self::photo('glasfaser.png', 'Aufgebautes Glasfaserkabel mit Außenmantel, Zugentlastung und einzelner Faser.', 'Glasfaserkabel transportieren Daten optisch; entscheidend ist, wie weit die Faser bis zum Nutzer geführt wird.') . '<h2>FTTH, FTTB und FTTC eindeutig unterscheiden</h2><table><thead><tr><th>Ausbauart</th><th>Glasfaser endet</th><th>Letzter Abschnitt</th></tr></thead><tbody><tr><td>FTTH</td><td>im Haus oder in der Wohnung</td><td>Glasfaser bis Gf-TA beziehungsweise ONT</td></tr><tr><td>FTTB</td><td>im Gebäude</td><td>gebäudeinterne Weiterführung nach Ausbaukonzept</td></tr><tr><td>FTTC</td><td>am Straßenverteiler</td><td>Kupfer vom MFG/KVz bis APL und TAE</td></tr></tbody></table><h2>Warum die Unterscheidung wichtig ist</h2><p>Nur bei FTTH reicht die Glasfaser bis in den Teilnehmerbereich. Ein Koaxialkabel ist weder eine DSL-Endleitung noch ein FTTH-Glasfaserkabel. Bei FTTC bleiben APL, Endleitung und TAE relevant; bei FTTH dagegen Gf-AP, Gf-TA und gegebenenfalls ONT.</p><h2>Praxisprüfung</h2><ul><li>Vertragliche Ausbauart nicht mit der beworbenen Tarifgeschwindigkeit verwechseln.</li><li>Ankommende Leitung und Netzabschluss identifizieren.</li><li>Routeranschluss prüfen: DSL-Port, Ethernet-WAN hinter ONT oder direkter Glasfaserport.</li></ul>' . $sources . '</article>',
            'gf-ap-erklaert' => '<article class="gk-clean-article">' . self::photo('gf-ap.png', 'Geöffneter Gf-AP mit Faserführung und Spleißablage.', 'Gf-AP: passiver Gebäudeabschluss des Glasfasernetzes.') . '<h2>Was ist ein Gf-AP?</h2><p>Der Glasfaser-Abschlusspunkt ist der passive Abschluss der ankommenden Glasfaser am Gebäude. Er enthält Faserführung, Spleißablage und je nach Ausbau Kupplungen oder vorbereitete Abgänge. Er ist kein Router und benötigt für seine passive Funktion keinen Strom.</p><h2>So lässt er sich einordnen</h2><ul><li><strong>Gf-AP:</strong> Gebäudeabschluss der Glasfaser.</li><li><strong>Gf-TA:</strong> optische Teilnehmeranschlussdose in Haus oder Wohnung.</li><li><strong>ONT:</strong> aktives Gerät zur Umsetzung des optischen Signals auf Ethernet.</li><li><strong>APL:</strong> Gebäudeabschluss des Kupfernetzes für Telefonie und DSL.</li></ul><h2>Montage und Zugang</h2><p>Der Gf-AP liegt häufig im Hausanschluss- oder Technikraum nahe der Gebäudeeinführung. Leitungsweg, Biegeradien und Zugang müssen vor der Montage geklärt sein. Das Gehäuse nicht eigenmächtig öffnen oder Fasern bewegen.</p>' . $sources . '</article>',
            'gf-ta-erklaert' => '<article class="gk-clean-article">' . self::photo('gf-ta.png', 'Glasfaser-Teilnehmeranschlussdose mit optischer Buchse.', 'Gf-TA: passiver optischer Anschluss in Haus oder Wohnung.') . '<h2>Was ist eine Gf-TA?</h2><p>Die Glasfaser-Teilnehmeranschlussdose stellt den passiven optischen Anschluss im Nutzungsbereich bereit. Sie liegt im Signalweg hinter dem Gf-AP und vor ONT oder Glasfaserrouter. Sie ist keine TAE-Dose und wandelt das Signal nicht elektrisch um.</p><h2>Typischer Signalweg</h2><p><strong>Gf-AP → gebäudeinterne Glasfaser → Gf-TA → optisches Patchkabel → ONT oder Glasfaserrouter</strong></p><h2>Praxis</h2><ul><li>Stecker und Buchse müssen zum Anschlusskonzept passen.</li><li>Schutzkappen erst unmittelbar vor dem Verbinden entfernen.</li><li>Faser nicht knicken, quetschen oder an verschmutzten Steckflächen berühren.</li><li>Standort so wählen, dass ONT, Router und Stromversorgung sinnvoll erreichbar sind.</li></ul>' . $sources . '</article>',
            'glasfaser-bauteile-im-haus' => '<article class="gk-clean-article"><h2>Glasfaser-Bauteile im Haus erkennen</h2><div class="gk-compare-photos">' . self::photo('gf-ap.png', 'Geöffneter Gf-AP mit Faserführung und Spleißablage.', 'Gf-AP: passiver Gebäudeabschluss.') . self::photo('gf-ta.png', 'Glasfaser-Teilnehmeranschlussdose mit optischer Buchse.', 'Gf-TA: optischer Anschluss im Nutzungsbereich.') . self::photo('ont.png', 'ONT mit optischem Eingang, Ethernet-Ausgang und Stromversorgung.', 'ONT: aktiver Übergang von Glasfaser zu Ethernet.') . '</div><h2>Der typische FTTH-Signalweg im Haus</h2><p><strong>Gf-AP → gebäudeinterne Glasfaser → Gf-TA → ONT oder Glasfaserrouter → LAN/WLAN</strong></p><h2>Aufgaben klar trennen</h2><p>Gf-AP und Gf-TA sind passive optische Abschlusspunkte. Ein ONT benötigt Strom und stellt Ethernet bereit. Der Router baut die Internetverbindung nach Anbietervorgabe auf und verteilt sie im Heimnetz.</p><h2>Häufige Verwechslungen</h2><ul><li>Ein Kupfer-APL besitzt Doppeladern und Klemmen, keine Glasfaser-Spleißablage.</li><li>Ein Koax-HÜP besitzt Koaxialkabel mit Innenleiter und Schirmung.</li><li>Der ONT ist nicht automatisch der WLAN-Router.</li></ul>' . $sources . '</article>',
            'speedpipe-erklaert' => '<article class="gk-clean-article">' . self::photo('speedpipe.png', 'Verband aus farbigen Mikrorohren für Glasfaserkabel.', 'Speedpipes sind Schutz- und Führungsrohre; sie übertragen selbst kein Signal.') . '<h2>Was ist eine Speedpipe?</h2><p>Speedpipe ist eine gebräuchliche Bezeichnung für ein Mikrorohr, in das ein dafür vorgesehenes Glasfaserkabel eingeblasen wird. Das Rohr schützt und führt das Kabel, enthält aber nicht automatisch bereits eine Faser.</p><h2>Vom Rohr zur nutzbaren Verbindung</h2><ol><li>Mikrorohrverband verlegen und dokumentieren.</li><li>Durchgängigkeit und Dichtheit prüfen.</li><li>Einblaskabel mit geeigneter Technik einbringen.</li><li>Fasern an Muffe, NVT oder Gf-AP spleißen und messen.</li></ol><h2>Typische Fehler</h2><ul><li>zu enge Biegeradien oder gequetschte Rohre</li><li>undichte Kupplungen und eindringende Feuchtigkeit</li><li>verschmutzte oder nicht verschlossene Rohrenden</li><li>nicht dokumentierte Rohrbelegung</li></ul>' . $sources . '</article>',
            'ont-erklaert' => '<article class="gk-clean-article">' . self::photo('ont.png', 'ONT mit optischem Eingang, Ethernet-Ausgang und Stromversorgung.', 'ONT: aktiver Netzabschluss zwischen optischem Anschluss und Ethernet.') . '<h2>Was macht ein ONT?</h2><p>Das Optical Network Terminal beendet die optische Teilnehmerverbindung und stellt auf der Kundenseite Ethernet bereit. Es benötigt Strom. Der ONT ist nicht automatisch ein Router und erzeugt nicht zwingend WLAN.</p><h2>Typischer Anschluss</h2><p><strong>Gf-TA → optisches Patchkabel → ONT → Ethernetkabel → WAN-Port des Routers</strong></p><p>Das Ethernetkabel gehört an den vom Hersteller vorgesehenen WAN-Port, nicht an einen DSL-Port. Anbieter können Registrierung, VLAN oder Zugangsdaten vorgeben.</p><h2>Status und Fehlersuche</h2><ul><li>Stromversorgung und Statusanzeigen prüfen.</li><li>Optisches Patchkabel nicht knicken und Steckflächen nicht berühren.</li><li>Ethernet-Link zwischen ONT und Router kontrollieren.</li><li>LAN-Test durchführen, bevor WLAN bewertet wird.</li></ul>' . $sources . '</article>',
            'ont-erklaert-einfach-erklaert' => '<article class="gk-clean-article">' . self::photo('ont.png', 'ONT mit optischem Eingang, Ethernet-Ausgang und Stromversorgung.', 'ONT: wandelt den optischen Teilnehmeranschluss in eine Ethernet-Schnittstelle für den Router um.') . '<h2>ONT kurz erklärt</h2><p>Ein ONT ist das aktive Abschlussgerät einer FTTH-Verbindung. Es setzt die optische Verbindung auf eine Ethernet-Schnittstelle um. Die Formulierung „wandelt Licht in Internet“ ist verkürzt: Zugangsdaten, Routerfunktion und Heimnetz bleiben eigenständige Aufgaben.</p><h2>ONT und Router unterscheiden</h2><table><thead><tr><th>Gerät</th><th>Aufgabe</th></tr></thead><tbody><tr><td>ONT</td><td>optische Teilnehmerverbindung abschließen und Ethernet bereitstellen</td></tr><tr><td>Router</td><td>Internetverbindung aufbauen, routen, Firewall sowie LAN/WLAN bereitstellen</td></tr></tbody></table><h2>Richtig verbinden</h2><p><strong>Gf-TA → ONT → WAN-Port des Routers.</strong> Das DSL-Modem eines Kombirouters wird hinter dem ONT nicht verwendet. Maßgeblich bleiben die Vorgaben des Anbieters.</p>' . $sources . '</article>',
            'glasfaser-spleissen-erklaert' => '<article class="gk-clean-article">' . self::photo('spleissstelle.png', 'Geschützte Glasfaser-Spleißstelle in einer Spleißkassette.', 'Fusionsspleiß: dauerhaft verbundene Fasern mit Spleißschutz in geordneter Ablage.') . '<h2>Was bedeutet Spleißen?</h2><p>Beim Fusionsspleißen werden zwei vorbereitete Glasfasern präzise ausgerichtet und mit einem Lichtbogen dauerhaft verbunden. Danach schützt eine Spleißschutzhülse die Verbindungsstelle.</p><h2>Arbeitsablauf</h2><ol><li>Faser absetzen und Beschichtung entfernen.</li><li>Faser reinigen und mit einem Cleaver rechtwinklig brechen.</li><li>Fasern im Spleißgerät ausrichten und verbinden.</li><li>Dämpfung beziehungsweise Spleißqualität bewerten.</li><li>Spleiß schützen und ohne enge Biegung in der Kassette ablegen.</li></ol><h2>Warum Fachpersonal nötig ist</h2><p>Verschmutzung, schlechter Faserbruch, ungeeignete Parameter oder falsche Ablage erhöhen die Dämpfung und können spätere Ausfälle verursachen. Offene Fasern und Laserstrahlung erfordern geeignete Arbeits- und Schutzregeln.</p>' . $sources . '</article>',
            'lc-stecker-erklaert' => '<article class="gk-clean-article">' . self::photo('steckverbinder.png', 'LC/UPC- und SC/APC-Glasfasersteckverbinder im Vergleich.', 'LC ist eine kompakte Steckverbinderbauform; Schliffart und Kupplung müssen zum Anschluss passen.') . '<h2>Was ist ein LC-Stecker?</h2><p>LC ist eine kompakte Glasfaser-Steckverbinderbauform mit 1,25-Millimeter-Ferrule und Rastmechanik. Die Bauform allein sagt noch nichts über Faserart oder Schliff aus.</p><h2>UPC und APC nicht verwechseln</h2><p>UPC- und APC-Schliffe besitzen unterschiedliche Stirnflächen. APC ist schräg geschliffen und häufig grün gekennzeichnet. Unpassende Schliffe dürfen nicht miteinander verbunden werden, auch wenn mechanisch ähnliche Adapter vorhanden sind.</p><h2>Praxisregeln</h2><ul><li>Stecker nur an gereinigte und passende Kupplungen anschließen.</li><li>Schutzkappen sauber halten.</li><li>Steckfläche vor dem Verbinden prüfen und fachgerecht reinigen.</li><li>Patchkabel nicht knicken, ziehen oder unter Spannung verlegen.</li></ul>' . $sources . '</article>',
        ];
    }

    public static function start_buffer(): void {
        if (is_admin() || wp_doing_ajax() || wp_is_json_request()) { return; }
        $request_path = trim((string) parse_url((string) ($_SERVER['REQUEST_URI'] ?? ''), PHP_URL_PATH), '/');
        self::$is_legal = is_page(['impressum-2', 'datenschutz-2', 'kontakt-2']) || in_array($request_path, ['impressum-2', 'datenschutz-2', 'kontakt-2'], true);
        self::$is_front = is_front_page();
        self::$slug = is_singular() ? (string) get_post_field('post_name', get_queried_object_id()) : '';
        ob_start([self::class, 'clean_html']);
    }

    public static function legal_visibility_guard(): void {
        $request_path = trim((string) parse_url((string) ($_SERVER['REQUEST_URI'] ?? ''), PHP_URL_PATH), '/');
        if (!in_array($request_path, ['impressum-2', 'datenschutz-2', 'kontakt-2'], true)) { return; }
        echo '<style id="gk-final-legal-guard">.gk9-tarifcheck,.gkpr-affiliate,.gk9-authorbox,.gkpr-author{display:none!important}</style>';
    }

    public static function author_name($name): string {
        $name = trim(wp_strip_all_tags((string) $name));
        return $name !== '' ? $name : self::AUTHOR_NAME;
    }

    public static function author_link($url): string {
        return self::AUTHOR_URL;
    }

    public static function footer($text): string {
        return 'Copyright © ' . wp_date('Y') . ' Glasfaser-Kompass';
    }

    public static function social_image($url): string {
        if (is_singular()) {
            $slug = self::$slug !== '' ? self::$slug : (string) get_post_field('post_name', get_queried_object_id());
            if (str_contains($slug, 'apl') || str_contains($slug, 'tae') || str_contains($slug, 'dsl')) {
                return home_url('/wp-content/plugins/gk-render-guard/assets/apl.png');
            }
            if (preg_match('/router|wlan|mesh|repeater|fritzbox|speedport/', $slug)) {
                return home_url('/wp-content/plugins/gk-render-guard/assets/wlan-heimnetz.png');
            }
            if (str_contains($slug, 'gf-ap') || str_contains($slug, 'glasfaser') || str_contains($slug, 'ftth')) {
                return home_url('/wp-content/plugins/gk-render-guard/assets/gf-ap.png');
            }
            if (str_contains($slug, 'ont')) {
                return home_url('/wp-content/plugins/gk-render-guard/assets/ont.png');
            }
        }
        return (string) $url;
    }

    private static function strip_dynamic_sections(string $html): string {
        $classes = '(?:gk9-tarifcheck|gk9-authorbox|gkpr-affiliate|gkpr-author)';
        $pattern = '~<section\b[^>]*class=(["\'])[^"\']*' . $classes . '[^"\']*\1[^>]*>.*?</section>~is';
        return (string) preg_replace($pattern, '', $html);
    }

    public static function clean_html(string $html): string {
        $html = str_replace(
            [
                '/dsl-stoerungen-verstehen-und-beheben/',
                '/glasfaseranschluss-einfach-erklaert-der-grosse-ratgeber/',
                'https://glasfaser-kompass.de/author/',
                'Präsentiert von Astra-WordPress-Theme',
                'Proudly powered by Astra WordPress Theme',
            ],
            [
                '/dsl-stoerungen-verstehen/',
                '/glasfaseranschluss-erklaert/',
                self::AUTHOR_URL,
                '',
                '',
            ],
            $html
        );

        if (self::$is_legal) {
            $html = self::strip_dynamic_sections($html);
        }

        if (self::$slug === 'dslam-erklaert') {
            /* Ein älterer Renderer hängt diesen unvollständigen Block nach dem
               reparierten Artikel an und überspringt darin den KVz. */
            $html = (string) preg_replace(
                '~<h2\b[^>]*>\s*Technischer Signalweg bei VDSL\s*</h2>.*?Bei reinen FTTH-Glasfaseranschlüssen.*?</p>~is',
                '',
                $html,
                1
            );
        }

        if (in_array(self::$slug, ['gf-ap-erklaert', 'gf-ta-erklaert', 'ont-erklaert'], true)) {
            /* Diese drei Beiträge zeigen das kuratierte Bauteilbild bereits im
               Fachartikel. Das Theme-Featured-Image wäre exakt dieselbe Datei. */
            $html = (string) preg_replace(
                '~<div\b[^>]*class=(["\'])[^"\']*ast-single-post-featured-section[^"\']*\1[^>]*>.*?</div>~is',
                '',
                $html,
                1
            );
        }

        if (self::$is_front) {
            $html = (string) preg_replace(
                '~(<h1\b[^>]*>)\s*Startseite\s*(</h1>)~iu',
                '$1' . self::HOME_TITLE . '$2',
                $html,
                1
            );
            $html = str_replace(
                ['<title>Startseite - glasfaser-kompass.de</title>', '<title>Startseite – glasfaser-kompass.de</title>'],
                '<title>' . self::HOME_TITLE . ' – Glasfaser-Kompass</title>',
                $html
            );
        }

        $html = (string) preg_replace(
            "~<div class=([\\\"'])ast-footer-copyright\\1><p>.*?</p>\\s*</div>~is",
            '<div class="ast-footer-copyright"><p>Copyright © ' . wp_date('Y') . ' Glasfaser-Kompass</p></div>',
            $html,
            1
        );

        $social = self::social_image('');
        if ($social !== '') {
            $escaped = esc_url($social);
            $html = (string) preg_replace("~<meta\\b[^>]*(?:property|name)=([\\\"'])(?:og:image|twitter:image)\\1[^>]*>\\s*~is", '', $html);
            $html = str_replace('</head>', '<meta property="og:image" content="' . $escaped . '"><meta name="twitter:image" content="' . $escaped . '"></head>', $html);
        }
        $html = (string) preg_replace("~<meta\\b[^>]*name=([\\\"'])twitter:card\\1[^>]*>\\s*~is", '', $html);
        $html = str_replace('</head>', '<meta name="twitter:card" content="summary_large_image"></head>', $html);

        return $html;
    }
}

GK_Final_Frontend_Guard::boot();
