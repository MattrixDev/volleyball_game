# Einstieg für neue Mitwirkende

Willkommen! Diese Seite bringt dich in etwa zehn Minuten so weit, dass du das Spiel startest, verstehst, worum es geht, und weißt, wo du weiterlesen musst.

## 1. Was ist das hier?

Ein PC-Volleyballspiel (Halle, 6 gegen 6, FIVB-Regeln, Männer). Ziel ist ein Spiel, das sich **wie echtes Volleyball** anfühlt und lange motiviert, mit FIFA als Vorbild für Steuerung und Tiefe. Details: [SPIELIDEE.md](SPIELIDEE.md).

**Wer macht was:** Mattis ist Inhaber und Spieldesigner. Er programmiert selbst nicht, sondern spielt jeden Build, gibt Rückmeldung und trifft die Design-Entscheidungen. Der gesamte Code wurde bisher von Claude (KI-Assistent) in mehreren parallelen Arbeitssträngen geschrieben. Das erklärt einige Eigenheiten des Repos, siehe [ARCHITEKTUR-PRUEFUNG.md](ARCHITEKTUR-PRUEFUNG.md).

**Sprache:** Spieltexte, Commit-Nachrichten und die meisten Code-Kommentare sind Deutsch (ohne Umlaute in Kommentaren, also `ue` statt `ü`). Bezeichner im Code sind Englisch. Bitte so beibehalten.

## 2. Einrichten

1. **Godot 4.4.1 stable** (Standard, nicht .NET): <https://github.com/godotengine/godot/releases/tag/4.4.1-stable>. Andere Versionen bitte nicht verwenden, sonst ändern sich `.import`- und `.uid`-Dateien massenhaft.
2. Repository klonen. `main` ist der neueste Stand.
3. `project.godot` im Godot-Editor öffnen und den ersten Import abwarten.
4. **F5** startet das Spiel. Renderer ist „GL Compatibility“, läuft also auch auf schwächeren Grafikkarten.

Optional, nur wenn du Assets neu bauen willst: Blender bzw. `pip install bpy` (Figuren, Halle), Python 3 mit `numpy` (Mocap, Sounds), MediaPipe (Video-Mocap). Siehe [ENTWICKLUNG.md](ENTWICKLUNG.md).

## 3. Spielen

- Startmenü → **Spielen** (oder „Kurzes Match“ bis 15).
- Du steuerst immer den Spieler mit dem gelben Ring. Die wichtigsten Tasten: linker Stick laufen, **A** Ball spielen, **R2** springen und schlagen, rechter Stick wohin der Ball geht. Alles Weitere in [STEUERUNG.md](STEUERUNG.md).
- Die Kachel **Debug** im Startmenü öffnet Übungen (nur Annahme, nur Angriff, …). Damit testest du eine Änderung viel schneller als im ganzen Match.

## 4. Wo finde ich was?

| Wenn du … ändern willst | schau in |
| --- | --- |
| Spielablauf, Regeln, KI, wer den Ball nimmt, Ballberührungen | `scripts/match.gd` (groß, siehe Inhaltsverzeichnis in [ARCHITEKTUR.md](ARCHITEKTUR.md)) |
| Tastenbelegung | `scripts/main.gd` `_setup_input()`, gelesen in `match.gd` `_read_input()` |
| Laufen, Springen, Hechten, Posen eines Spielers | `scripts/player.gd` |
| Gelenke, Federn, IK, Bodenkontakt der Figur | `scripts/figure.gd` |
| Welche Technik in welcher Lage | `scripts/technique.gd` |
| Spielerwerte, PlayStyles, Teams | `scripts/player_data.gd`, `scripts/play_styles.gd`, `teams/*.tres` |
| KI-Spielplan und Gedächtnis | `scripts/ai_plan.gd` |
| Kamera, Ton, Effekte verbinden | `scripts/main.gd` |
| Menüs, HUD | `scripts/start_menu.gd`, `menu.gd`, `hud.gd`, `ui_theme.gd` |

## 5. Wie wir arbeiten (wichtig)

- Bis 12.11.2026 wurde jede Arbeit als eigener Branch `claude/…` gebaut, und die Branches bauten aufeinander auf („Stacked PRs“ #8–#20). `main` lag dadurch weit zurück. Am 12.11. wurde der gesamte Stand mit PR #21 nach `main` gebracht und die alten PRs geschlossen.
- **Ab jetzt zweigt jede Arbeit von `main` ab** (Regeln in [CONTRIBUTING.md](../CONTRIBUTING.md)).
- Spielbare Windows-Builds bekommt Mattis als ZIP. Jeder Build hat einen Namen (z. B. `varianz-9`), die Liste steht in [HISTORIE.md](HISTORIE.md).
- Vor jeder größeren Änderung fragen wir Mattis, *wie* sie umgesetzt werden soll, und bauen nur, was er freigegeben hat.

Die Regeln für Pull Requests stehen in [../CONTRIBUTING.md](../CONTRIBUTING.md). Was wir an dieser Arbeitsweise ändern wollen, steht in [ARCHITEKTUR-PRUEFUNG.md](ARCHITEKTUR-PRUEFUNG.md).

## 6. Bevor du loslegst

Lies die Design-Prinzipien in [SPIELIDEE.md](SPIELIDEE.md#design-prinzipien). Sie sind keine Geschmacksfragen, sondern Entscheidungen von Mattis, an denen sich jede Änderung messen lassen muss: kein Text im Ballwechsel, realistisch statt Arcade, Varianz aus der Lage statt Zufall, Controller zuerst, Neulinge dürfen nie schlechter spielen als vorher.
