# Volleyball

Hallenvolleyball 6 gegen 6 für den PC, nach den FIVB-Regeln 2025–2028 (Männer, Netzhöhe 2,43 m), gebaut mit Godot 4.4.

Der Plan mit Spielidee und Phasen steht im [Plan-Dokument](https://claude.ai/code/artifact/7f883522-0f38-4b3f-ad4d-9c40c197b89f).

## Stand: Phase 1c – Ein ganzes Match

Aufbauend auf Steuerung 2.0 und dem Balancing (Phase 1a und 1b):

- Echte Rotation: Aufstellung auf den Positionen 1 bis 6, nach gewonnenem Rückschlag rückt jedes Team eine Position weiter, wer auf Position 1 steht, schlägt auf. Beim Aufschlag stehen alle regelgerecht (keine Überlappung), danach laufen die Vorderspieler auf ihre Angriffsbahn (Außen links, Mitte, Diagonal oder Zuspieler rechts)
- Kader mit 12 Spielern pro Team (Zuspieler, Außen, Mitte, Diagonal, Libero und eine Auswechselbank)
- Libero: ersetzt einen Mittelblocker im Hinterfeld (Position 5 oder 6), darf nicht vorn spielen, nicht aufschlagen und nicht vor der 3-m-Linie pritschen, wenn danach über Netzhöhe angegriffen wird (Liberofehler). Auf Wunsch macht ihn das Spiel automatisch (Menü), sonst über die Trainerbank
- Trainerbank (T / Y, vor dem Anpfiff zum Aufschlag): Auszeit (2 pro Satz), Libero rein und raus, Wechsel (6 pro Satz, Wiedereintritt nur für den eigenen Ersatz)
- Sätze bis 25 mit 2 Punkten Vorsprung, Entscheidungssatz bis 15 mit Seitenwechsel bei 8 Punkten. Spiellänge im Menü: 1 Satz, 2 oder 3 Gewinnsätze. Seitenwechsel nach jedem Satz, die Kamera bleibt hinter deinem Team
- Schiedsrichter: Pfiff zum Aufschlag und nach jedem Ballwechsel, Handzeichen als Bild (Aufschlag, Punkt, Netz, Doppelberührung, Ball gehalten, Aus, Auszeit, Wechsel, Seitenwechsel, Satzende). Aufschlagzeit 8 bis 30 Sekunden (Menü, Regel: 8), Hinterspielerfehler, Liberofehler
- Team-KI: wechselt den Libero selbst, nimmt Auszeiten bei Punkteserien des Gegners, wechselt gelegentlich Spieler gleicher Rolle
- Noch nicht drin: Commit-Block, Profi-Option mit eigenem Angriffssprung, Zwei-Spieler-Doppelblock (braucht lokalen Mehrspieler), animierter Schiedsrichter als 3D-Figur

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
```

| Datei | Inhalt |
| --- | --- |
| `scripts/match.gd` | Spielablauf, Regeln, KI, Ballberührungen |
| `scripts/ballistics.gd` | Flugbahnen und Vorhersage |
| `scripts/player.gd` | Spielerfigur, Laufen, Springen, Hechten |
| `scripts/main.gd` | Halle, Kamera, Steuerung |
| `scripts/hud.gd` | Spielstand und Hinweise |
| `scripts/contact_pad.gd` | Anzeige Trefferpunkt und Kraft |
| `scripts/roster.gd` | Kader, Aufstellung, Rotation, Libero- und Wechselregeln |
| `scripts/trainer.gd` | Trainerbank (Auszeit, Libero, Wechsel) |
| `scripts/referee.gd` | Schiedsrichter: Handzeichen und Pfiff |
| `scripts/menu.gd`, `scripts/settings.gd` | Einstellungsmenü, Stufen, Spiellänge |
