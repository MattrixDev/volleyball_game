# Mitwirken

Danke, dass du mithilfst! Zum Einlesen: [docs/EINSTIEG.md](docs/EINSTIEG.md).

## Grundregeln

1. **Mattis entscheidet über das Spieldesign.** Bevor du eine größere Änderung baust (neue Mechanik, anderer Tastenplan, neuer Look), beschreibe sie kurz in einem Issue und warte auf sein OK. Kleine Fehlerbehebungen gehen direkt als PR.
2. **Die Design-Prinzipien gelten immer**: [docs/SPIELIDEE.md](docs/SPIELIDEE.md#design-prinzipien). Besonders: kein Text im Ballwechsel, realistisch statt Arcade, Varianz aus der Lage statt Zufall, alles mit dem Controller bedienbar, Neulinge spielen nie schlechter als vorher.
3. **Spielbar zuerst.** Am Ende jeder Arbeit steht etwas, das Mattis spielen kann.

## Branches und Pull Requests

- Zweige von `main` ab, mit sprechendem Namen: `feature/<thema>`, `fix/<thema>`, `docs/<thema>`.
- Ein Thema pro PR, möglichst klein. Keine gestapelten PRs ohne Absprache.
- PR-Beschreibung: was sich für den Spieler ändert (in einfachen Worten), wie getestet, Vorher/Nachher-Zahlen aus den Simulationen.
- `main` muss jederzeit spielbar bleiben.
- Gemergt wird nach Mattis' OK (bei Gameplay nach seinem Playtest).

## Code-Stil

- **GDScript, Godot 4.4.1.** Keine andere Engine-Version, kein C#.
- Bezeichner Englisch, **Kommentare Deutsch ohne Umlaute** (`ue`, `ae`, `oe`, `ss`), Spieltexte Deutsch mit Umlauten.
- Jede öffentliche Funktion bekommt einen `##`-Doc-Kommentar, der erklärt, *warum* sie tut, was sie tut.
- Typisierung wo möglich (`var x: float`, `-> void`).
- Neue Dateien: die von Godot erzeugte `.uid`-Datei mit einchecken.
- Neue Klassen mit `class_name` brauchen danach `godot --headless --import`, sonst Parse-Fehler im Headless-Lauf.
- **Nichts Neues in `scripts/match.gd`, was auch in eine eigene Datei passt.** Die Datei ist schon zu groß (siehe [docs/ARCHITEKTUR-PRUEFUNG.md](docs/ARCHITEKTUR-PRUEFUNG.md)).
- Zufall nur mit dem Match-RNG (`rng`), damit `--seed` reproduzierbar bleibt. Spielerfolg nie würfeln.
- Debug-Ausgaben (`print`) nur hinter einem Schalter.

## Vor dem Pull Request

- [ ] Spiel startet ohne Fehler im Editor (F5) und mit `--headless`.
- [ ] `godot --headless --fixed-fps 240 res://scenes/main.tscn -- --autoplay --check --seed=1 --rallies=200 --sets=3` ohne `SCRIPT ERROR` und ohne Regelverletzung.
- [ ] Gameplay-Änderung: `--autopress` (Neuling) und `--autopress --skilled` vorher/nachher verglichen, Zahlen im PR.
- [ ] Reine Umstrukturierung: `--autoplay --seed=N` vorher/nachher **identisch**.
- [ ] Animations-Änderung: Labor-Audit (Seeds 11, 23, 37, 51) vorher/nachher, kurzer Film der betroffenen Stelle.
- [ ] Menüs mit dem Controller durchgeklickt (A, B, Steuerkreuz).
- [ ] Kein neuer Text im Ballwechsel.
- [ ] Doku angepasst, wenn sich Steuerung, Schalter oder Struktur ändern ([docs/STEUERUNG.md](docs/STEUERUNG.md), [docs/ENTWICKLUNG.md](docs/ENTWICKLUNG.md), [docs/ARCHITEKTUR.md](docs/ARCHITEKTUR.md)).

## Assets und Lizenzen

Das Repository ist öffentlich. Lege nur Dateien ab, die wir weitergeben dürfen (eigene Modelle, freie Daten, abgeleitete Daten). Gekaufte Assets, Rohvideos oder Dateien mit unklarer Lizenz gehören nicht ins Repo. Im Zweifel vorher fragen.
