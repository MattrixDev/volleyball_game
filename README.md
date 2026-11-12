# Volleyball

Hallenvolleyball 6 gegen 6 für den PC, nach den FIVB-Regeln 2025–2028 (Männer, Netzhöhe 2,43 m), gebaut mit **Godot 4.4.1**. Gespielt wird mit dem Controller, die Teams sind erfunden.

Das Ziel ist ein Volleyballspiel, das sich **realistisch** anfühlt (kein Arcade) und lange Spaß macht: leicht zu lernen, aber mit viel Raum für Können, ähnlich wie FIFA beim Fußball.

> **Neu im Projekt?** Fang mit [docs/EINSTIEG.md](docs/EINSTIEG.md) an. Dort steht in zehn Minuten, was das Spiel ist, wie du es startest und wo du was findest.

## Dokumentation

| Datei | Worum es geht |
| --- | --- |
| [docs/EINSTIEG.md](docs/EINSTIEG.md) | Erste Schritte: Projekt öffnen, starten, testen, wie wir arbeiten |
| [docs/SPIELIDEE.md](docs/SPIELIDEE.md) | Was für ein Spiel das ist, Regelumfang und die Design-Prinzipien, die für jede Änderung gelten |
| [docs/STEUERUNG.md](docs/STEUERUNG.md) | Der aktuelle Tastenplan (Controller und Tastatur), Spielzüge, 5-Sterne-Moves |
| [docs/ARCHITEKTUR.md](docs/ARCHITEKTUR.md) | Wie der Code aufgebaut ist: Szenen, Skripte, Datenfluss, Schnittstellen, Werkzeuge |
| [docs/ENTWICKLUNG.md](docs/ENTWICKLUNG.md) | Testmodi, Kommandozeilen-Schalter, Animations-Labor, Windows-Build, Assets aus Blender |
| [docs/HISTORIE.md](docs/HISTORIE.md) | Was bisher gebaut wurde, Etappe für Etappe |
| [docs/ZIELE.md](docs/ZIELE.md) | Die nächsten großen Ziele: fertiger Look und mehr Spielvielfalt |
| [docs/ARCHITEKTUR-PRUEFUNG.md](docs/ARCHITEKTUR-PRUEFUNG.md) | Ehrliche Bestandsaufnahme von Code und Arbeitsweise, Empfehlungen und offene Fragen |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Regeln für Beiträge: Branches, Pull Requests, Code-Stil, Checkliste |

## Schnellstart

1. [Godot 4.4.1](https://github.com/godotengine/godot/releases/tag/4.4.1-stable) (Standard-Version, nicht .NET) herunterladen.
2. Dieses Repository klonen und `project.godot` in Godot öffnen. Beim ersten Öffnen importiert Godot alle Assets, das dauert einen Moment.
3. **F5** startet das Spiel mit dem Startmenü. Ein Controller (Xbox- oder PlayStation-Layout) wird empfohlen.

Schneller Funktionstest ohne Fenster:

```
godot --headless --fixed-fps 120 res://scenes/main.tscn -- --autoplay --rallies=200
```

Das spielt 200 Ballwechsel KI gegen KI und gibt am Ende eine Statistik aus. Mehr Testmodi stehen in [docs/ENTWICKLUNG.md](docs/ENTWICKLUNG.md).

## Stand (November 2026)

- Ganzes Match nach FIVB-Regeln: Rotation, 5-1-Aufstellung, Libero, Wechsel, Auszeiten, Sätze mit Entscheidungssatz, Schiedsrichter.
- Steuerung „aus einem Guss“ nach FIFA-Vorbild, mit Halten-und-Loslassen-Timing, Spielzügen mit Täuschern und seltenen 5-Sterne-Moves.
- Varianz aus der Lage: Technik, Folgen schlechter Annahmen, Overpass, Netzkampf, Hechtbälle.
- KI mit Spielplan und Gedächtnis, die sich auf deine Lieblingsschläge einstellt.
- 8 erfundene Teams mit je 14 Spielern (Größe, Reichweite, 8 Werte, 18 PlayStyles), Spielerkarten und „Mein Verein“.
- Low-Poly-Figuren aus eigenen Meshy-Modellen, Bewegungen aus Posen, CMU-Mocap und frei lizenzierten Videos, eigene Physik für Füße und Treffer.
- Bento-Menüs, Debug-Modus mit Übungen, Einstellungen für Spiel, Ton und Kamera.

Noch nicht drin: lokaler Mehrspieler, Saison/Karriere, Musik und Hallensprecher, verschiedene Hallen.

## Lizenzen der Inhalte

- Spielerfigur: aus Mattis' Meshy-Modell „Low-Poly Volleyball Player“ (CC BY 4.0).
- Mocap: [CMU Graphics Lab Motion Capture Database](http://mocap.cs.cmu.edu/) (frei nutzbar).
- Bewegungen aus Videos: nur die abgeleiteten Gelenkdaten liegen im Repo (`assets/models/video_clips.json`), die Pexels-Rohvideos werden nicht weitergegeben.
- Geräusche: im Projekt selbst erzeugt (`tools/make_sounds.py`).
