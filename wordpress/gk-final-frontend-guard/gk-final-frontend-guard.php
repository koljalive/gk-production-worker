<?php
/**
 * Plugin Name: GK Final Frontend Guard
 * Description: Bereinigt dynamische Altlinks, Rechtsseiten-Blöcke, Autorenanzeige und Theme-Reste nach dem Rendern.
 * Version: 1.0.1
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
    }

    public static function start_buffer(): void {
        if (is_admin() || wp_doing_ajax() || wp_is_json_request()) { return; }
        self::$is_legal = is_page(['impressum-2', 'datenschutz-2', 'kontakt-2']);
        self::$is_front = is_front_page();
        self::$slug = is_singular() ? (string) get_post_field('post_name', get_queried_object_id()) : '';
        ob_start([self::class, 'clean_html']);
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
            if (str_contains($slug, 'gf-ap') || str_contains($slug, 'glasfaser') || str_contains($slug, 'ftth')) {
                return home_url('/wp-content/plugins/gk-render-guard/assets/gf-ap.png');
            }
            if (str_contains($slug, 'ont')) {
                return home_url('/wp-content/plugins/gk-render-guard/assets/ont.png');
            }
            if (preg_match('/router|wlan|mesh|repeater/', $slug)) {
                return home_url('/wp-content/plugins/gk-render-guard/assets/wlan-heimnetz.png');
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
