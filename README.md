# Volleyball

Hallenvolleyball 6 gegen 6 für den PC, nach den FIVB-Regeln 2025–2028 (Männer, Netzhöhe 2,43 m), gebaut mit Godot 4.4.

Der Plan mit Spielidee und Phasen steht im [Plan-Dokument](https://claude.ai/code/artifact/7f883522-0f38-4b3f-ad4d-9c40c197b89f).

## Stand: Phase 1a – Steuerung 2.0

Aufbauend auf dem Prototyp aus Phase 0:

- Baggern und Pritschen auf zwei Tasten. Pritschen ist genauer, bei harten Bällen droht „Ball gehalten“, ein schwaches Pritsch-Zuspiel kann eine Doppelberührung sein
- Aufschlag und Angriff: R2 / E halten zum Aufladen, loslassen zum Treffen. Mehr Kraft macht das Timing enger, zu lange halten überzieht
- Trefferpunkt am Ball mit dem rechten Stick (Maus oder I J K L): oben Topspin, Mitte flach bzw. Flatter, unten Leger bzw. kurzer Aufschlag, seitlich Richtung, ganz außen Cut Shot oder Block-Out
- Aufschläge: Stand oder Sprung (LB/RB, 1/2), daraus Flatter, Sprungflatter, Topspin, Sprung-Topspin, kurz. Flatterbälle wackeln im Flug
- Zoom vor Aufschlag und Angriff, Zeitlupe, sobald der eigene Angreifer oder Blocker in der Luft ist
- Block: linker Stick verschiebt den Block, in der Luft die Hände, nach vorn greift über das Netz (Risiko Netzberührung)
- Doppel- und Dreierblock: Mittelblocker läuft zum Außenblocker, bei schnellen Zuspielen kommt er zu spät. Blockschatten am Boden zeigt den abgedeckten Bereich
- Noch nicht drin: Rotation, Libero-Regeln, Auszeiten, Wechsel, mehrere Sätze (restliche Phase 1)

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
| Beenden | | Esc |

Du steuerst immer den Spieler mit dem gelben Ring. Bei Annahme und Zuspiel drückst du, wenn sich der schrumpfende Ring mit dem weißen Ring deckt. Der weiße Ring wird mit Laufhilfe grün, wenn Pritschen sicher geht, und orange, wenn du besser baggerst.

## Für Entwickler

Projekt in Godot 4.4 öffnen (`project.godot`). Testmodi über die Kommandozeile:

```
godot --headless --fixed-fps 120 res://scenes/main.tscn -- --autoplay --rallies=500   # KI gegen KI, Statistik
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
