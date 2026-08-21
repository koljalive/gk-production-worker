# Glasfaser-Kompass – verbindliche Live-Abnahmeregeln

Diese Regeln gelten für alle weiteren Produktionsänderungen an glasfaser-kompass.de.

## Grundsatz

Eine Änderung ist **nicht erledigt**, nur weil ein API-Aufruf, WordPress-Write, Workflow, SEO-Test oder HTTP-Request erfolgreich war.

**Erledigt = öffentlich sichtbar + fachlich korrekt + visuell geprüft + technisch geprüft.**

## Pflichtablauf für jede Änderung

1. **Ursache vor Änderung nachweisen**
   - Betroffene öffentliche URL prüfen.
   - Tatsächlich sichtbaren Ist-Zustand erfassen.
   - WordPress-/Theme-/Plugin-/Cache-Ursache voneinander unterscheiden.
   - Keine Änderung auf bloßen Verdacht.

2. **Backup / Rollback sicherstellen**
   - Vor produktiven Content-, Medien-, Layout- oder Metadatenänderungen bisherigen Zustand sichern.

3. **Gezielte Änderung durchführen**
   - Nur die nachgewiesene Ursache verändern.
   - Keine unnötigen Bulk-Writes als Ersatz für Diagnose.

4. **Write verifizieren**
   - Prüfen, ob WordPress/API die beabsichtigte Änderung tatsächlich gespeichert hat.
   - HTTP 200 allein gilt nicht als Abnahme.

5. **Öffentliche URL ohne Cache-Buster prüfen**
   - Die normale Besucher-URL muss den neuen Zustand ausliefern.
   - Cache-Buster darf nur zur Diagnose dienen, niemals als Endabnahme.
   - Bei Abweichung Cache/Origin/Theme-Ausgabe zuerst beheben.

6. **Visuelle Frontend-Prüfung**
   - Sichtbares Ergebnis auf Desktop und mobil beurteilen.
   - Bilder nach tatsächlicher Darstellung bewerten, nicht nach Dateiname, ALT-Text, Featured-Media-ID oder Regex.
   - Prüfen: Motiv passend, erkennbar, hochwertig, nicht irreführend, keine schematische Darstellung sofern nicht ausdrücklich sinnvoll, kein Überlauf/Cropping-Fehler.

7. **Technische Prüfung**
   - Relevante Punkte wie H1, Canonical, OpenGraph, responsive Bilder, Links, Layout und HTTP-Status prüfen.
   - Technische Metriken ergänzen die visuelle Prüfung, ersetzen sie nicht.

8. **Erst danach Status ERLEDIGT**
   - Fehlt eine Pflichtprüfung: Status = `NICHT VERIFIZIERT`.
   - Scheitert eine Prüfung: Status = `OFFEN` oder `BLOCKIERT` mit konkreter Ursache.

## 10/10-Regel

Eine Seite darf nur als **10/10** bezeichnet werden, wenn alle folgenden Bedingungen gleichzeitig erfüllt sind:

- öffentliche normale URL zeigt den aktuellen Stand;
- Inhalt fachlich korrekt;
- sichtbare Bilder passen zum konkreten Thema und sind qualitativ geeignet;
- Desktop und Mobil visuell sauber;
- keine relevanten Layout-/H1-/Link-/SEO-/Social-Meta-Fehler;
- keine bekannte offene Abweichung zwischen WordPress und öffentlichem Frontend.

Automatische Scores oder Regex-Gates allein dürfen niemals als 10/10 ausgegeben werden.

## Bildregel

Für Bilder gilt zusätzlich:

- Das tatsächlich sichtbare Bild ist die maßgebliche Wahrheit.
- Featured Image, OpenGraph-Bild und Content-Bild sind getrennt zu prüfen.
- Ein korrekt gesetztes `featured_media` oder `og:image` bedeutet nicht, dass das sichtbare Content-Bild repariert wurde.
- Schematische/illustrative Bilder werden nicht anhand ihres Dateinamens als gut oder schlecht klassifiziert; die sichtbare Darstellung wird geprüft.
- Austausch gilt erst nach öffentlicher visueller Verifikation als abgeschlossen.

## Reporting-Regel

Keine Formulierungen wie „repariert“, „fertig“, „10/10“, „erfolgreich geändert“ oder vergleichbare Erfolgsmeldungen, solange die öffentliche Endabnahme nicht bestanden ist.

Zulässige Zwischenstatus:

- `WRITE ERFOLGT – PUBLIC VERIFY OFFEN`
- `PUBLIC VERIFY BESTANDEN – VISUAL VERIFY OFFEN`
- `BLOCKIERT – <konkrete Ursache>`
- `ERLEDIGT – PUBLIC + VISUAL + TECHNICAL VERIFIED`

## Reihenfolge bei systemischen Änderungen

Bei Bulk-Arbeiten zuerst an einer repräsentativen Seite vollständig bis zur öffentlichen visuellen Abnahme testen. Erst wenn dieser Pilot bestanden ist, denselben Fix auf weitere Inhalte ausrollen. Danach Stichprobe und vollständiger automatisierter Endaudit.

**Keine Massenänderung auf Basis eines unbestätigten Piloten.**
