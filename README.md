# GK Production Worker 6.0.0

Der GK Production Worker verarbeitet die Prüf- und Korrekturwarteschlange von
glasfaser-kompass.de vollautomatisch. Er kann im sicheren Vorschaumodus oder im
Produktionsmodus laufen, setzt fehlgeschlagene Läufe fort und schreibt
maschinenlesbare sowie HTML-Berichte.

## Voraussetzungen

- Windows 10/11 oder Windows Server
- .NET 8 SDK zum Bauen; das veröffentlichte Paket ist selbstständig lauffähig
- eine GK Site Audit/Core API mit Lese- und Schreibroute
- optional ein OpenAI API-Key für KI-gestützte Korrekturvorschläge

## Schnellstart

1. `config.example.json` als `config.json` kopieren.
2. Vorhandene `.env` daneben ablegen; `GK_SITE_AUDIT_TOKEN` und `OPENAI_API_KEY` werden automatisch erkannt.
3. Verbindung prüfen: `GkProductionWorker.exe doctor`
4. Vorschau: `GkProductionWorker.exe preview`
5. Veröffentlichung: `GkProductionWorker.exe publish --confirm JA`
6. Dauerbetrieb: `GkProductionWorker.exe watch --confirm JA`

Ein produktiver Schreibvorgang ist nur mit `--confirm JA` möglich. Der Worker
sendet einen Idempotency-Key, prüft den Inhalt vor und nach jeder Änderung und
speichert niemals Geheimnisse in Logs oder Berichten.

## Befehle

| Befehl | Wirkung |
|---|---|
| `doctor` | Konfiguration und API-Verbindung prüfen |
| `status` | Queue-Status anzeigen |
| `preview` | Batch prüfen und Änderungen nur als Vorschau erzeugen |
| `publish --confirm JA` | geprüfte Änderungen veröffentlichen |
| `watch --confirm JA` | Batches bis zum Ende bzw. dauerhaft verarbeiten |

Optionen: `--config PATH`, `--limit N`, `--post ID` (mehrfach), `--once`.

## Konfiguration

Alle Endpunkte sind relativ zu `Api.BaseUrl` konfigurierbar. Platzhalter:
`{id}`, `{limit}`, `{offset}`. Damit ist der Worker nicht mehr von einer
historischen, fest verdrahteten Route abhängig.

Umgebungsvariablen überschreiben Geheimnisse:

- `GK_API_TOKEN`
- `GK_UNIFIED_API_TOKEN`
- `OPENAI_API_KEY`
- `GK_API_BASE_URL`

## Sicherheit und Wiederaufnahme

- Standardmodus ist `preview`.
- Produktionsänderungen benötigen die exakte Bestätigung `JA`.
- Getrennte Checkpoints: `state/preview/checkpoint.json` und
  `state/production/checkpoint.json` (atomar geschrieben).
- JSONL-Auditlog: `logs/worker-YYYYMMDD.jsonl`.
- Antworten werden gekürzt und Tokens werden niemals protokolliert.
- Retries verwenden exponentielles Backoff mit Jitter.
- Eine Änderung wird nur gespeichert, wenn das Quality Gate keine Blocker meldet.

## Bauen und testen

Unter Windows `scripts\build-windows.ps1` ausführen. Die Tests laufen ohne
externe Testbibliothek über `dotnet run --project tests/GkProductionWorker.Tests`.
Für automatischen Start kann anschließend `scripts\install-startup-task.ps1`
als Administrator ausgeführt werden. Der Worker wird dabei über die Windows-
Aufgabenplanung beim Systemstart gestartet.
