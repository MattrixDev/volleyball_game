# Architekturprüfung: Code und Arbeitsweise

Stand: 12.11.2026, geprüft am Branch `claude/project-thread-xje4w7`. **Nachtrag:** Empfehlung 1 (neuester Stand nach `main`, gestapelte PRs schließen) ist mit Mattis' OK am 12.11. umgesetzt (PR #21). Diese Seite ist eine ehrliche Bestandsaufnahme: Was trägt, was bremst, und wie weit sich Aufräumen jetzt lohnt. Am Ende stehen Empfehlungen in Reihenfolge und offene Fragen an Mattis.

## Kurzfassung

- **Die Spiellogik ist solide und gut messbar**, aber in einer einzigen Riesendatei (`match.gd`, 5 246 Zeilen) gebündelt. Das ist der größte technische Engpass, sobald mehr als ein Mensch oder Arbeitsstrang gleichzeitig daran baut.
- **Die Arbeitsweise passte für „eine KI baut in parallelen Strängen, ein Mensch testet Builds“**, aber nicht für einen weiteren Mitwirkenden: `main` ist 120 Commits zurück, 13 PRs liegen gestapelt offen, Builds und Design-Entscheidungen leben außerhalb des Repos.
- **Empfehlung:** Zuerst den neuesten Stand nach `main` bringen, einen automatischen Smoke-Test einrichten und einfache Branch-Regeln festlegen. Danach `match.gd` in kleinen, messbar gleichen Schritten aufteilen. Das Animationssystem (`player.gd`, `figure.gd`) erst anfassen, wenn der Weg für den Look entschieden ist, sonst wird es doppelt gebaut.

## Zahlen

| Datei | Zeilen | Funktionen | Rolle |
| --- | ---: | ---: | --- |
| `scripts/match.gd` | 5 246 | 205 | Regeln, Ablauf, KI, Eingabe, Ballberührungen, Wiederholung, Test-Bots, Übungs-Hooks, Statistik |
| `scripts/player.gd` | 2 447 | 79 | Bewegung und Posen-Auswahl eines Spielers |
| `scripts/figure.gd` | 1 186 | 43 | Skelett, Federn, IK, Füße |
| `scripts/main.gd` | 725 | 26 | Komposition, Kamera, Ton, Eingabe-Belegung |
| alle 40 Skripte | 17 669 | | |

`match.gd` hat dazu 166 Variablen auf Dateiebene und 33 Konstantenblöcke. Rund 45 % des Spielcodes stecken in einer Datei.

## Was gut ist (behalten)

1. **Klare Schnittstelle Logik ↔ Animation.** Die Spiellogik setzt nur `anim_kind`, `anim_style` und `contact_pt`; wie das aussieht, entscheidet die Figur. Dadurch konnten Animation und Gameplay wochenlang parallel entstehen. Diese Naht ist auch der Ansatzpunkt für jeden Umbau des Looks.
2. **Messbarkeit.** Headless-Simulation mit festem Seed, simulierte Spieler (Neuling `--autopress`, Könner `--skilled`), Statistik am Ende, Regelprüfung `--check`, Animations-Labor mit Fehlerzählung und Film. Das ist für ein Spiel dieser Größe ungewöhnlich gut und die Grundlage für sicheres Umbauen.
3. **Signale statt Verdrahtung.** `match.gd` meldet `contact`, `big_hit`, `point_won` usw.; Ton, Effekte und Kamera hängen sich in `main.gd` daran.
4. **Daten als Ressourcen.** Teams und Spieler in `.tres`, Einstellungen in einer Klasse, PlayStyles als Katalog.
5. **Deterministische Entscheidungen** (Varianz aus der Lage) machen Verhalten nachvollziehbar und testbar.
6. **Ausführliche, deutsche Commit-Nachrichten** und Doc-Kommentare (`##`) an fast jeder Funktion.

## Was bremst

### 1. `match.gd` ist ein „Gott-Objekt“

Regeln, Spielstand, Aufstellung, Eingabe lesen, menschliche Aktionen, KI-Entscheidungen, Block-Zuteilung, Aufschlag, Wiederholung, Test-Bots, Übungs-Hooks und Statistik liegen in einer Datei und teilen sich 166 globale Variablen.

Folgen:
- **Merge-Konflikte**: Fast jede Etappe der letzten Wochen hat `match.gd` geändert. Mit zwei Menschen (oder Mensch plus KI) gleichzeitig wird das zum Dauerproblem.
- **Einarbeitung**: Ein neuer Mitwirkender muss 5 000 Zeilen überblicken, um eine Annahme-Regel zu ändern.
- **Versteckte Kopplung**: KI und Mensch teilen sich Pfade über Flags (`human`, `drill`, `_auto_input`), und Test-Code liegt zwischen Spielcode.

**Wie weit lohnt sich Aufteilen?** Ein kompletter Neubau lohnt sich **nicht**: Die Logik funktioniert, ist abgestimmt und durch viele Playtests gegangen. Sinnvoll ist ein **schrittweises Herauslösen** entlang der vorhandenen Blöcke, jeweils mit dem Nachweis, dass sich nichts ändert:

| Schritt | Herauslösen nach | Risiko | Nutzen |
| --- | --- | --- | --- |
| 1 | Test-Bots (`_auto_input`, `_skilled_attack`, `_pro_reception`, `_auto_set_plan`) → `autopilot.gd` | sehr klein | Spielcode und Test-Code getrennt |
| 2 | Wiederholung (`_record`, `_start_replay`, `_step_replay` …) → `replay.gd` | klein | eigenständiges Feature |
| 3 | Eingabe lesen (`_read_input`, `_held_stick`, Stick-/Steuerkreuz-Logik) → `match_input.gd`, liefert ein typisiertes Objekt statt Dictionary | mittel | Tastenplan an einer Stelle; Grundlage für lokalen Mehrspieler |
| 4 | KI-Entscheidungen (`_ai_*`) → `ai_decisions.gd` neben `ai_plan.gd` | mittel | KI unabhängig weiterentwickelbar |
| 5 | Spielstand, Sätze, Rotation, Wechsel → `match_rules.gd` | mittel | Regeln einzeln testbar |
| 6 | Ballzuteilung und Block (`plan_next`, `_try_team`, `_assign_block`) | hoch | erst angehen, wenn 1–5 sitzen |

**Sicherheitsnetz für jeden Schritt:** Vorher und nachher `--autoplay --seed=N --rallies=500` laufen lassen; die Statistik muss **identisch** sein (reine Umstrukturierung ändert bei festem Seed nichts). Das ist ein sehr starker, billiger Regressionstest, den dieses Projekt schon hat.

### 2. Kein automatischer Test, keine CI

Es gibt viele Testwerkzeuge, aber nichts, das bei einem Pull Request automatisch läuft. Mit einem zweiten Mitwirkenden ist das das wichtigste fehlende Stück.

**Empfehlung:** Eine GitHub Action, die Godot 4.4.1 headless startet, importiert und folgendes prüft:
- `--autoplay --check --seed=1 --rallies=200 --sets=3`: keine `SCRIPT ERROR`, keine Regelverletzung.
- `--autopress --seed=1 --rallies=200`: Neuling-Werte innerhalb einer Toleranz.
- optional: Windows-Export als Artefakt, damit jeder PR einen spielbaren Build hat.

### 3. Animationssystem: viele Quellen, Spiel schiebt die Figur

`player.gd` mischt fünf Bewegungsquellen; die Figur folgt der Spielposition statt sie zu treiben. Das ist der technische Kern des „zusammengewürfelt“-Eindrucks (siehe [ZIELE.md](ZIELE.md#ziel-1-sieht-fertig-aus-visual-fix)).

**Wie weit lohnt sich Aufräumen?** Jetzt **nicht**. Bei Weg A (Mocap-Bibliothek, Root-Motion, AnimationTree) würde ein Großteil von `player.gd` ersetzt. Erst die Stilentscheidung, dann ein kleiner Prototyp (nur Angriff), dann umbauen. Bis dahin nur Fehler beheben. Die Naht `anim_kind`/`anim_style`/`contact_pt` sollte dabei erhalten bleiben. Bei Root-Motion kommt eine zweite Richtung hinzu: Die Animation meldet, wann und wo der Kontakt *kann*; das betrifft dann auch das Timing in `match.gd` und muss gemeinsam geplant werden.

Ebenfalls offen: Die Animation kostet rund 7 ms pro Physik-Takt für 12 Spieler bei 120 Hz (gemessen 05.11.). Für schwächere PCs lohnt sich später, die Figur mit 60 Hz zu rechnen oder entfernte Spieler einfacher zu animieren.

### 4. Altlasten und Namensschulden

- Eingabe-Aktionen tragen Namen aus alten Tastenplänen: `set_fast` ist B (Hechten), `serve_prev` ist L1 (hoch und sicher), `set_dump` ist R1 (schnell und flach). Verwirrend für jeden Neuen.
- Nach „Kein Text im Spiel“ sind Text-Pfade noch vorhanden (`popup()` mit 28 Aufrufen, `Q_TEXT`, `tech_hints.gd`, hinter `--popups`). Entscheiden: löschen oder bewusst als Debug-Hilfe behalten.
- Reste älterer Steuerungen (z. B. `kind_prev`/`kind_next` im Eingabe-Dictionary).
- Debug-Ausgaben (`print`) im Spielcode, teilweise ohne Schalter.

**Empfehlung:** Ein Aufräum-PR nach dem Abgleich mit `main`, mit dem gleichen Seed-Vergleich als Sicherheitsnetz.

### 5. Arbeitsweise: Branch-Stapel und veraltetes `main`

Bisher: Jeder Arbeitsstrang baute einen eigenen Branch (`claude/project-thread-<zufall>`) auf dem vorherigen auf. PRs wurden nicht gemergt, sondern gestapelt; Mattis bekam kombinierte Builds aus lokalen Zusammenführungen.

| | Für die bisherige Situation | Für mehrere Mitwirkende |
| --- | --- | --- |
| Gestapelte PRs | erlaubte parallele Arbeit ohne Warten auf Merges | 11 Ebenen tief, niemand weiß, wo er abzweigen soll |
| `main` veraltet | egal, solange nur Builds zählten | neuer Mitwirkender startet vom falschen Stand |
| Branch-Namen ohne Inhalt | intern zuordenbar | unlesbar (`project-thread-xje4w7`) |
| Kombinierte Builds lokal gemerged | schnell | nicht reproduzierbar: welcher Commit steckt in `varianz-9`? |

**Empfehlung (trunk-basiert, einfach):**
1. **Einmalig:** Den neuesten Stand per **einem** PR nach `main` bringen und die gestapelten PRs #8–#20 als „in main enthalten“ schließen. Die Stapel einzeln nacheinander zu mergen bringt nichts, weil der Gesamtstand schon geprüft zusammengeführt ist (siehe [HISTORIE.md](HISTORIE.md#der-frühere-pr-stapel-bis-1211)). (Umgesetzt am 12.11., PR #21.)
2. **Danach:** Jede Arbeit zweigt von `main` ab, kurzlebig, mit sprechendem Namen (`feature/sichtbare-moves`, `fix/aufschlag-jubel`). Ein PR pro Thema, gemergt nach Mattis' Playtest-OK. Kein Stapeln mehr, außer kurzfristig und mit Absprache.
3. **`main` ist immer spielbar.** CI muss grün sein.
4. **Builds aus `main` oder einem PR**, mit Git-Tag pro Build (`varianz-9` → Tag `build/varianz-9`), ZIP als GitHub-Release. Damit ist jeder Build einem Commit zugeordnet und auch für Mitwirkende greifbar.
5. **Branch-Schutz für `main`**: nur über PR, CI muss grün sein.

### 6. Wissen außerhalb des Repos

Entscheidungen, Tastenpläne, Analysen und Vorher/Nachher-Videos lagen bisher in einem gemeinsamen Projektordner bzw. Chat-Verläufen, auf die ein Mitwirkender keinen Zugriff hat. Diese Doku holt das Wichtigste ins Repo.

**Empfehlung:** Neue Design-Entscheidungen kurz in `docs/` festhalten (eine Zeile pro Entscheidung mit Datum und Grund reicht, z. B. als Abschnitt in [SPIELIDEE.md](SPIELIDEE.md) oder eigene `docs/ENTSCHEIDUNGEN.md`). Für Aufgaben und Fehler GitHub-Issues nutzen, damit Mensch und KI dieselbe Liste sehen.

### 7. Assets und Lizenzen im öffentlichen Repo

Das Repository ist **öffentlich**. Heute ist das unkritisch (eigene Meshy-Modelle unter CC BY 4.0, freie CMU-Daten, aus Videos abgeleitete Gelenkdaten). Aber:
- Gekaufte Mocap-Bibliotheken (Weg A) erlauben fast nie die Weitergabe der Rohdaten. Sie dürften dann **nicht** in ein öffentliches Repo.
- Für einen späteren Verkauf auf Steam ist ein öffentlicher Quellcode eine Geschäftsentscheidung.
- Die Assets sind ~36 MB, die größte Datei 7 MB. Noch kein Bedarf für Git LFS; bei Mocap-Bibliotheken oder Videos ändert sich das.

### 8. Kleinere Punkte

- **Godot-Version** ist auf 4.4.1 festgelegt. Ein Upgrade ist nicht dringend; wenn, dann bewusst in einem eigenen PR (Import-Dateien ändern sich massenhaft).
- **Sprache**: Deutsche Kommentare ohne Umlaute, englische Bezeichner, deutsche Spieltexte. Funktioniert, sollte aber als Regel festgehalten sein (siehe [CONTRIBUTING.md](../CONTRIBUTING.md)).
- **Lokaler Mehrspieler** ist durch `human_team` (genau ein Mensch) in `match.gd` fest verdrahtet. Schritt 3 der Aufteilung (Eingabe als Objekt pro Spieler) ist die Vorbereitung dafür.
- **Keine Szenen-Struktur im Editor**: Alles entsteht im Code. Gut für Diffs und KI-Bearbeitung, schlecht für jemanden, der im Godot-Editor visuell arbeiten will (UI, Halle, Licht). Für einen menschlichen Mitwirkenden mit Editor-Erfahrung könnten einzelne Teile (Menüs, Halle) als `.tscn` angenehmer sein. Nicht dringend.

## Empfohlene Reihenfolge

| Wann | Was | Aufwand |
| --- | --- | --- |
| **Vor dem Start des Mitwirkenden** | ~~Neuesten Stand nach `main`, gestapelte PRs schließen~~ (erledigt), Branch-Regeln aus [CONTRIBUTING.md](../CONTRIBUTING.md) | klein |
| | CI mit Smoke-Test (Autoplay + Regelprüfung) | klein |
| **Bald** | Aufräum-PR (Namensschulden, Text-Reste) | klein |
| | `match.gd` Schritte 1–3 (Bots, Wiederholung, Eingabe) mit Seed-Vergleich | mittel |
| | Builds als Tags/Releases | klein |
| **Nach der Stilentscheidung** | Animationsarchitektur (Root-Motion-Prototyp, nur Angriff) | groß |
| **Später** | `match.gd` Schritte 4–6, Performance der Figur, LFS bei Bedarf, ggf. Editor-Szenen für UI/Halle | mittel bis groß |

## Offene Fragen an Mattis

1. ~~Darf der neueste Stand nach `main`?~~ Ja, am 12.11. erledigt.
2. Soll das Repo öffentlich bleiben (wichtig für gekaufte Assets und den späteren Verkauf)?
3. Welche Bereiche soll der neue Mitwirkende übernehmen? Eine klare Aufteilung (z. B. er: Menüs/Verein/Hallen, Claude: Spiellogik/Animation) vermeidet Konflikte in `match.gd`, bis es aufgeteilt ist.
4. Wer gibt Pull Requests frei: nur Mattis nach Playtest, oder darf der Mitwirkende selbst mergen, wenn die CI grün ist?
5. Soll `match.gd` jetzt schrittweise aufgeteilt werden, oder erst nach dem nächsten Gameplay-Meilenstein?
6. Welcher Weg für den Look (A, B, C)? Davon hängt ab, wie viel Arbeit in `player.gd`/`figure.gd` noch sinnvoll ist.
