# Historie: Was bisher gebaut wurde

Das Projekt startete am 09.10.2026. Jede Etappe endete mit einem spielbaren Windows-Build für Mattis (Name in Klammern) und seiner Rückmeldung, aus der die nächste Etappe entstand. Die Commit-Nachrichten im Repo sind ausführlich und auf Deutsch; `git log` ist die genaueste Quelle.

## Phase 0 und 1: Grundspiel und Regeln (09.–11.10.)

- **Phase 0** (`phase0`): spielbarer Prototyp eines Ballwechsels in Godot 4.4.1.
- **Steuerung 2.0** (`phase1a`): Baggern/Pritschen auf zwei Tasten, Aufladen-und-Loslassen beim Schlag, Trefferpunkt mit dem rechten Stick, Zoom, Zeitlupe, Doppelblock.
- **Balancing und Einstellungsmenü** (`phase1b`), Normal-Stufe nach Mattis' Werten.
- **Ganzes Match** (`phase1c`/`phase1d`): Rotation, 12er-Kader, Libero, Wechsel, Auszeiten, Sätze mit Entscheidungssatz, Schiedsrichter mit Handzeichen, Commit-Block.
- **5-1-Aufstellung** (`aufstellung-1/-2`): regelgerechte Annahme-Aufstellung je Rotation, Regellinien zwischen den Spielern.

## Phase 2: Spielgefühl und Look (09.–11.10.)

- **Phase 2** (`phase2`): Startmenü, Pausenmenü, Publikum, Ballgeräusche, Treffer-Effekte, Wiederholungen starker Punkte.
- **Phase 2b** (`phase2b`): neue Hallen-Sounds (Mattis' Favoriten, bleiben so) und erster Low-Poly-Look.
- **Phase 2c–2p**: eigene Spielerfiguren aus Blender, Trikot-System pro Team, ganze Halle mit Linienrichtern, Zuspiel-Varianten (hoch, schnell, Schnellangriff, Dump), Block lesen, kraftvollere Angriffe, Kill-Block, Zuspielrichtung auf dem Steuerkreuz, Pritschen nach Lehrbildern.
- **Meshy-Modelle** (`meshy-alles-1`, `meshy-animationen-1`, `kernanimationen-1`): Mattis' eigene Meshy-Figuren für Spieler, Schiedsrichter, Netz, Ball; Halten-und-Loslassen für alle Aktionen (`halten-loslassen-1/-2`); Timing-Spaß (`timing-spass-1`).

Bis hierhin wurde alles direkt in `main` gemergt (PR #1–#7). Alles Folgende entstand in aufeinander aufbauenden PRs und kam am 12.11. gesammelt mit PR #21 nach `main`.

## Visual Overhaul: Animation (13.–15.10., läuft weiter)

- **Animations-Labor** zum Messen und Filmen von Animationsfehlern.
- Feste Füße, Gelenkfedern, geometrische IK, Semi-Ragdoll für Stöße und Landungen, genaue Treffpunkte (`visual-1`).
- Bogenspannung beim Schlag, Pritschen nach Lehrbild (`visual-2`), Finger als Federn um den Ball, Daumen-Dreieck beim Pritschen (`visual-3` bis `visual-6`).
- Persönlicher Bewegungscharakter pro Spieler, Körpergröße und Linkshänder (`visual-7`).
- Weichere, menschlichere Übergänge: Trägheit, Kettenzeitpunkte, Gelenkgrenzen, Ausfallschritt zu weiten Bällen (`visual-8`, `visual-9`), Unterarm-Drehknochen (`visual-10`).

## Wiederspielwert, Spieler und Verein (14.–15.10.)

- **UI Version 5 „Bento“** (`ui-bento-1/-2`): helles Kachel-Startmenü, neue Spielanzeige, Schrift Inter.
- **Tempo und Kraft** (`tempo-kraft-1`): weniger Zeitlupe, Wucht-Zone im Kraftbalken, mehr Topspin, lebendigere Kamera, Kurzes Match bis 15.
- **Echte Spieler** (`spieler-1`): 8 erfundene Teams × 14 Spieler mit Größe, Reichweite, 8 Werten und Eigenschaften.
- **Mein Verein** (`karten-1`): Spielerkarten sammeln, eigenes Team, Münzen, Aufgaben, Kartenshop. Bewusst pausiert, bis sich das Match richtig gut anfühlt.
- **Debug-Modus** (`debug-1` bis `debug-4`): Übungen, Abkürzungen, alle Menüs per Controller, Einstellungen mit Seiten Spiel/Ton/Kamera.

## Varianz, Skill-Gap und KI (03.–05.11.)

Auslöser: Playtester-Rückmeldung „jeder Punkt läuft gleich ab“ („Schema F“).

- **Varianz aus der Lage** (`visual-11`): Abwehr-, Zuspiel-, Angriffs- und Blocktechniken folgen aus der Situation, Folgen und lernbare Fehler; echte Mocap-Sprünge (CMU).
- **Skill-Gap-Ziel** (04.11.): leicht anzufangen, viel mehr für Könner, FIFA als Vorbild.
- **Annahme steuerbar** (`annahme-1`), **Angriff mit mehr Gefühl** (`angriff-gefuehl-1`): Timing öffnet Winkel, L2-Gefühlsschläge, Anlauf mit dem linken Stick.
- **KI mit Spielplan und Gedächtnis** (`ki-spielplan-1`).
- **Block aus der Physik** (`block-physik-1`), **Block belohnend ohne Text** (`block-gefuehl-1`).
- **Flüssiges Spielgefühl** (`fluss-1`, `fluss-2`): versetzte Reaktionen, menschliche Beschleunigung, Drehgrenze, ruhigere Kamera, kein Hitstop ohne Zeitlupe, echter Hechtsprung mit Flug.

## Zwischenziel: Steuerung aus einem Guss und „Varianz, Varianz, Varianz“ (05.–07.11.)

- **Steuerung aus einem Guss** (`guss-1` bis `guss-3`): neuer FIFA-artiger Tastenplan, Zuspieler-Angriff auf R2, Dump auf L2+R2, Block-Netzfehler abgeschafft, **aller Text im Ballwechsel entfernt**, Spielstand oben in der Mitte.
- **Bewegungen aus echten Videos**: Angriff, Sprung- und Standaufschlag aus frei lizenzierten Pexels-Videos (MediaPipe).
- **Etappe 1 – Spielzüge und Rally-Varianz** (`varianz-1` bis `varianz-5`): Y + Steuerkreuz sagt Spielzüge an, Täuscher laufen mit an, Overpass angreifbar, Netzkampf, harte Annahme fliegt über das Netz, Bälle nur per Hecht erreichbar. Passende Bewegungen für Täuscher, Slide, Pipe, Netzkampf.
- **Etappe 2 – Aufschlag als Waffe, KI mit Plan** (`varianz-6`): Aufschlag-Spezialisten, Aufschlag in die Lücke, KI meidet gelesene Spielzüge.
- **Etappe 3 – PlayStyles und 5-Sterne-Moves** (`varianz-7` bis `varianz-9`): 18 PlayStyles in 6 Gruppen mit Plus-Stufe, 5 Moves auf Y als Trick-Taste mit eigenen Bewegungen.

Neuester Build: **`varianz-9`** (06.11.). Neuester Code-Stand: Branch `claude/project-thread-xje4w7` (12.11., enthält zusätzlich einen Fix, dass der Aufschläger nicht mehr im Jubel des letzten Punkts aufschlägt).

## Offen nach dem letzten Playtest (07.11.)

- Mattis hat PlayStyles und 5-Sterne-Moves in `varianz-9` nicht bemerkt (wirken still). Vorschläge zu Feedback und Sichtbarkeit warten auf Entscheidung.
- Der Look wirkt für Mattis noch „clunky“ und „zusammengewürfelt“. Drei Wege liegen auf dem Tisch, siehe [ZIELE.md](ZIELE.md).

## Der frühere PR-Stapel (bis 12.11.)

```
main (PR #1–#7)
 ├── #8  Meshy-Modelle, Halten und Loslassen
 │    └── #11 Visual Overhaul (Animation)
 │         └── #13 UI Bento
 │              └── #14 Tempo, Spieler, Mein Verein
 │                   └── #15 Debug-Modus
 │                        └── #16 Varianz, KI-Spielplan
 │                             ├── #18 Angriff mit Gefühl ── #17 Annahme steuerbar
 │                             └── #19 Flüssiges Spielgefühl
 │                                  └── #20 Steuerung aus einem Guss, Spielzüge, Varianz, PlayStyles
 └── #9  Zuspiel mit Steuerkreuz in main nachziehen (überholt)
```

Alle diese Stände wurden im Branch `claude/project-thread-xje4w7` zusammengeführt (geprüft am 12.11.: kein Commit fehlte außer einer doppelten `.uid`-Datei), mit PR #21 nach `main` gebracht und die PRs #8–#20 geschlossen.
