# Lastenheft – GK Production Worker 6.0

## Ziel

Der Worker übernimmt die vollständige, wiederaufnehmbare Verarbeitung der
WordPress-Prüfwarteschlange für glasfaser-kompass.de. Manuelle Einzelbefehle pro
Beitrag sind ausgeschlossen. Vorschau und Produktion bleiben klar getrennt.

## Muss-Anforderungen

1. Externer .NET-8-Worker; kein WordPress-Plugin.
2. Batch- und Dauerbetrieb mit Checkpoint und sauberem Abbruch.
3. Bearbeitung einzelner IDs sowie API-gesteuerter Queue-Betrieb.
4. Read-only-Vorschau mit HTML-Bericht.
5. Produktion nur nach expliziter Bestätigung `JA`.
6. Konfigurierbare API-Endpunkte; keine fest verdrahtete Update-Route.
7. Bearer-Authentifizierung ausschließlich über Konfiguration/Umgebung.
8. Retry, exponentielles Backoff, Timeout und nachvollziehbare Fehler.
9. Idempotency-Key für jede Schreiboperation.
10. Nachprüfung des tatsächlich gespeicherten Inhalts.
11. Quality Gate gegen Inhaltsverlust und neu eingeschleusten aktiven Code.
12. Mindestens zwei unabhängige offizielle Quellen je fachlicher Korrektur.
13. Bilder, Alt-Texte, Bildunterschriften und KI-Objekte mitprüfen.
14. JSONL-Auditlog ohne Tokens und HTML-Zusammenfassung je Lauf.
15. OpenAI-Anbindung optional; ohne Key keine erfundene Korrektur.
16. Selbstständiges Windows-x64-Paket, Buildskript und automatische
    Startaufgabe über die Windows-Aufgabenplanung.
17. Automatisierte Tests für Quality Gate und Idempotenz.

## Abnahmekriterien

- `doctor` erreicht die API oder liefert einen eindeutigen Fehler.
- `preview` schreibt WordPress-Inhalte nicht um.
- `publish` ohne `--confirm JA` endet vor dem ersten Schreibaufruf.
- Nicht bestandene Quality Gates verhindern das Speichern.
- Nach einem Neustart werden abgeschlossene IDs nicht erneut verarbeitet.
- Nicht vorhandene Update-Routen werden erkannt; alternative konfigurierte
  Routen werden versucht und protokolliert.
- Ein vollständiger Lauf erzeugt einen Bericht mit geprüft/geändert/gespeichert/
  Fehlern und erfordert keine Befehlswiederholung pro Beitrag.
