# Volleyball

Hallenvolleyball 6 gegen 6 für den PC, nach den FIVB-Regeln 2025–2028 (Männer, Netzhöhe 2,43 m), gebaut mit Godot 4.4.

Der Plan mit Spielidee und Phasen steht im [Plan-Dokument](https://claude.ai/code/artifact/7f883522-0f38-4b3f-ad4d-9c40c197b89f).

## Stand: Phase 2e – Einheitlicher Low-Poly-Stil

- Alles im Stil der Vorlage (facettierte Dreiecke, gedämpfte Farben, weiches Licht), komplett in Blender gebaut
- Spielerfigur: Gesicht ohne Augen und Mund nur aus Flächen, V-Ausschnitt mit Kragen, Seitenteile, Dreieck-Logo, Nummer hinten, vorn und auf dem linken Hosenbein, Knieschoner, hohe Schuhe. Vier Frisuren (wellig, kurz, länger, lockig) und leicht verschiedene Körpergrößen
- Trikots pro Team als eigene Datei in `teams/` (Name, alle Trikotfarben, Libero-Trikot). Ein neues Team = eine neue `.tres`-Datei, siehe unten
- Neue Halle aus Blender: Spielfeld, Netz mit Antennen, Pfosten mit Polster, Schiedsrichterstuhl mit Leiter, Kampfgericht, Bänke mit Flaschen und Handtüchern, Tribünen mit Sitzschalen, Banden, Anzeigetafeln, Fenster, Dachträger, Lampen, Fahnen an der Wand
- Ball und sitzende Fans aus Blender; vier Linienrichter mit Fahne an den Ecken (der nächste zeigt „im Feld“ oder „Aus“)
- Schiedsrichter, Linienrichter und Schreiber in langer Hose

### Neues Team anlegen

Eine Datei in `teams/` kopieren (zum Beispiel `teams/seewald.tres`), `id`, `name` und die Farben ändern. Im Godot-Editor geht das auch per Doppelklick mit Farbwählern. Die beiden Teams wählt man im Startmenü aus (Dein Team, Gegner). Zum Testen: `-- --teams=seewald,nordhafen`.

## Phase 2b – Sounds und Low-Poly-Look

- Neue Geräusche: Pfiff, Ballkontakte, Netz, Boden, Schuhquietschen und Publikum klingen näher an einer echten Halle (mit Hall). Erzeugt mit `tools/make_sounds.py`, liegen als WAV in `assets/sounds/`
- Eigene Spielerfiguren, weich gerundet: Gesicht mit Augen und Brauen, Finger, Trikot mit Kragen und Säumen, Knieschoner und Schuhe mit Sohle; Bewegungen für Laufen (auch rückwärts und Seitschritt), Bereitschaft, Baggern, Pritschen, Angriff mit Ausholen, Block, Hechten flach auf den Boden, Landung, Aufschlag und Jubel
- Flüssige Bewegungen: Gelenke federn weich in jede Haltung, der tiefste Körperpunkt steht immer genau auf dem Boden, Physik-Interpolation für jeden Bildschirm-Frame, Zeitlupe mischt zwischen den aufgezeichneten Bildern
- Ganze Arena: Hallenboden mit Freizone, Tribünen mit Stufen, Deckenlampen, Werbebanden, Anzeigetafeln, Schiedsrichter als 3D-Figur auf dem Stuhl, Kampfgericht und Ersatzbänke
- Helle, kräftige Farben; Ball mit Streifen, der sich dreht
- Keine Namensschilder über den Köpfen, nur der eigene Spieler hat den gelben Ring

## Phase 2 – Spielgefühl

- Startmenü (Spielen, Einstellungen, Steuerung, Beenden), dahinter läuft ein Spiel KI gegen KI
- Neues Pausenmenü (Esc / Start): Regler in Gruppen (Zeitlupe, Ton, Hilfen und Gegner, Regeln), Weg zurück ins Hauptmenü
- Halle mit Publikum auf den Tribünen: Fans springen bei Punkten auf, Gemurmel wird in langen Ballwechseln lauter, Jubel, Raunen und Applaus
- Ballgeräusche (Baggern, Pritschen, Aufschlag, Angriff, Leger, Block, Netz, Aufprall), alle Klänge werden im Spiel selbst erzeugt
- Dezente Treffer-Effekte: Staubwolke und Abdruck am Boden, kurzer Lichtblitz bei harten Schlägen und Blocks, leichtes Kamerawackeln
- Wiederholung starker Punkte (Ass, Blockpunkt, sehr harter Angriff, langer Ballwechsel) in Zeitlupe aus der Fernsehkamera, überspringen mit A / Leertaste, im Menü abschaltbar. Höchstens alle 4 Punkte eine
- Keine große Meldung mehr in der Mitte nach jedem Punkt: der Schiedsrichter zeigt den Grund, der Spielstand leuchtet kurz auf. Satzende, Matchende, Auszeit und Seitenwechsel stehen in einer schmalen Leiste unter dem Spielstand
- Wechsel-Einblendung unten links: wer rein und wer raus geht (auch beim Libero und beim Gegner)
- Lautstärke für Pfiff, Ball und Publikum im Menü

Aus Phase 1 (Regeln): Rotation, Kader mit 12 Spielern, Libero, Trainerbank (T / Y), Sätze mit Entscheidungssatz, Schiedsrichter mit Handzeichen, Team-KI, Doppelblock mit beiden Sticks, Commit-Block.
Noch nicht drin: Profi-Option mit eigenem Angriffssprung, Spielerwerte, lokaler Mehrspieler.

## Spielen

Windows: `Volleyball.exe` starten (aus dem Download-Ordner entpackt).

| Aktion | Gamepad | Tastatur |
| --- | --- | --- |
| Laufen, Zuspiel-Richtung, Aufschlagziel, Block verschieben | linker Stick | WASD oder Pfeiltasten |
| Baggern | A | Leertaste |
| Pritschen | X | Q |
| Schlagen (halten, loslassen), Blocksprung | R2 | E |
| Trefferpunkt am Ball | rechter Stick | Maus oder I J K L |
| Aufschlag Stand / Sprung | LB / RB | 1 / 2 |
| Laufhilfe an/aus | Select | F1 |
| Zeitlupe an/aus | Start | F2 |
| Zoom an/aus | | F3 |
| Trainerbank (vor dem Aufschlag) | Y | T |
| Einstellungen | Start | Esc |

Du steuerst immer den Spieler mit dem gelben Ring. Bei Annahme und Zuspiel drückst du, wenn sich der schrumpfende Ring mit dem weißen Ring deckt. Der weiße Ring wird mit Laufhilfe grün, wenn Pritschen sicher geht, und orange, wenn du besser baggerst.

## Für Entwickler

Projekt in Godot 4.4 öffnen (`project.godot`). Testmodi über die Kommandozeile:

```
godot --headless --fixed-fps 120 res://scenes/main.tscn -- --autoplay --rallies=500   # KI gegen KI, Statistik
godot --headless --fixed-fps 240 res://scenes/main.tscn -- --autoplay --rallies=500 --check --sets=3   # prüft Aufstellung, Libero, Sätze
godot res://scenes/main.tscn -- --demo                                                  # KI gegen KI zum Zuschauen
godot --headless --fixed-fps 120 res://scenes/main.tscn -- --autopress --rallies=300  # simulierte Eingaben, Statistik
godot res://scenes/main.tscn -- --botplay                                               # simulierte Eingaben mit Kamera und Zeitlupe
godot res://scenes/main.tscn -- --play                                                  # Startmenü überspringen
godot --headless --fixed-fps 120 res://scenes/main.tscn -- --botplay --quit-after=900  # simulierte Eingaben mit Wiederholungen, Statistik nach 900 s
godot res://scenes/main.tscn -- --botplay --shot-phase=REPLAY:bild.png --quit-after-shot  # Bild kurz nach Beginn einer Phase
```

| Datei | Inhalt |
| --- | --- |
| `scripts/match.gd` | Spielablauf, Regeln, KI, Ballberührungen |
| `scripts/ballistics.gd` | Flugbahnen und Vorhersage |
| `scripts/player.gd` | Spieler: Laufen, Springen, Hechten, Posen |
| `scripts/figure.gd` | Spielerfigur: lädt das Blender-Modell, Gelenke, weiche Posen, Bodenkontakt |
| `tools/blender/build_player.py` | Baut das Spielermodell in Blender (`pip install bpy`) und schreibt `assets/models/player.glb` |
| `tools/anim_strip.gd`, `tools/closeup.gd`, `tools/pose_shot.gd` | Prüfbilder für Bewegungen und Figuren |
| `scripts/arena.gd` | Lädt die Halle, Licht, Banden- und Anzeigetafel-Schrift, Schiedsrichter, Linienrichter, Bänke |
| `tools/blender/build_arena.py` | Baut Halle, Ball, Fahne und Fans in Blender (`assets/models/arena.glb`, `ball.glb`, `flag.glb`, `fan.glb`) |
| `scripts/team_style.gd`, `scripts/teams.gd`, `teams/*.tres` | Teams: Name und Trikotfarben |
| `scripts/main.gd` | Halle, Kamera, Steuerung, verbindet Geräusche und Effekte |
| `scripts/sfx.gd` | Spielt Geräusche und Publikumsklänge ab |
| `tools/make_sounds.py` | Erzeugt die Geräusche in `assets/sounds/` |
| `scripts/fx.gd` | Staub, Abdruck, Lichtblitz |
| `scripts/crowd.gd` | Zuschauer auf den Tribünen |
| `scripts/start_menu.gd` | Startmenü und Steuerungsseite |
| `scripts/ui_theme.gd` | Gemeinsames Aussehen der Menüs |
| `scripts/hud.gd` | Spielstand und Hinweise |
| `scripts/contact_pad.gd` | Anzeige Trefferpunkt und Kraft |
| `scripts/roster.gd` | Kader, Aufstellung, Rotation, Libero- und Wechselregeln |
| `scripts/trainer.gd` | Trainerbank (Auszeit, Libero, Wechsel) |
| `scripts/referee.gd` | Schiedsrichter: Handzeichen und Pfiff |
| `scripts/menu.gd`, `scripts/settings.gd` | Einstellungsmenü, Stufen, Spiellänge |

## Spielerfigur aus dem Meshy-Modell (Phase 2i)

`tools/blender/build_player_meshy.py <meshy.blend> assets/models/player.glb` baut die Figur aus Mattis' Meshy-Modell (CC BY 4.0, Quelle: Low-Poly Volleyball Player): drehen, vereinfachen, nach Bereichen einfärben (Materialnamen wie im Team-System), Skelett mit den Gelenknamen aus `figure.gd`, Arme senken. Die ältere, selbst modellierte Figur steckt weiter in `build_player.py` (4 Frisuren); die Meshy-Figur hat eine Frisur, die Haarfarbe wechselt pro Spieler.
