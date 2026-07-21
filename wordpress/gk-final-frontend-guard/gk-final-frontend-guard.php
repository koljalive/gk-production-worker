<?php
/**
 * Plugin Name: GK Final Frontend Guard
 * Description: Bereinigt dynamische Altlinks, Rechtsseiten-Blöcke, Autorenanzeige und Theme-Reste nach dem Rendern.
 * Version: 1.0.4
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
