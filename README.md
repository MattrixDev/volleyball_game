# Volleyball

Hallenvolleyball 6 gegen 6 für den PC, nach den FIVB-Regeln 2025–2028 (Männer, Netzhöhe 2,43 m), gebaut mit Godot 4.4.

Der Plan mit Spielidee und Phasen steht im [Plan-Dokument](https://claude.ai/code/artifact/7f883522-0f38-4b3f-ad4d-9c40c197b89f).

## Stand: Phase 0 – Prototyp „ein Ballwechsel“

- Halle, Netz, Antennen und 12 Spieler als einfache Figuren
- Ballflug mit Schatten, Landepunkt und Timing-Ring
- Aufschlag, Annahme, Zuspiel (Außen, Mitte, Diagonal), Angriff, Legen, Block, Abwehr
- Zu früh oder zu spät gedrückt hat sichtbare Folgen: Ball ins Aus, ins Netz, schlechter Pass
- Gegner-KI, Zählweise bis 25 mit 2 Punkten Vorsprung
- Noch nicht drin: Rotation, Libero-Regeln, Auszeiten, Wechsel, mehrere Sätze (Phase 1)

## Spielen

Windows: `Volleyball.exe` starten (aus dem Download-Ordner entpackt).

| Aktion | Gamepad | Tastatur |
| --- | --- | --- |
| Laufen, zielen | linker Stick | WASD oder Pfeiltasten |
| Annahme, Schlag, Aufschlag, Block | A | Leertaste |
| Zuspiel auf Außen / Mitte / Diagonal | X / Y / B | J / K / L |
| Legen statt schlagen | RB | Umschalt |
| Laufhilfe an/aus | Select | F1 |
| Beenden | | Esc |

Du steuerst immer den Spieler mit dem gelben Ring. Drücke, wenn sich der schrumpfende Ring am Boden mit dem weißen Ring deckt (er wird dann grün).

## Für Entwickler

Projekt in Godot 4.4 öffnen (`project.godot`). Testmodi über die Kommandozeile:

```
godot --headless --fixed-fps 120 res://scenes/main.tscn -- --autoplay --rallies=500   # KI gegen KI, Statistik
godot res://scenes/main.tscn -- --demo                                                  # KI gegen KI zum Zuschauen
```

| Datei | Inhalt |
| --- | --- |
| `scripts/match.gd` | Spielablauf, Regeln, KI, Ballberührungen |
| `scripts/ballistics.gd` | Flugbahnen und Vorhersage |
| `scripts/player.gd` | Spielerfigur, Laufen, Springen, Hechten |
| `scripts/main.gd` | Halle, Kamera, Steuerung |
| `scripts/hud.gd` | Spielstand und Hinweise |
