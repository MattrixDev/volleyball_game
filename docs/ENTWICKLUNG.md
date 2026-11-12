# Entwicklung: Testen, Messen, Bauen

Alle Befehle gehen davon aus, dass `godot` auf Godot 4.4.1 zeigt und du im Repo-Ordner stehst. Benutzerargumente kommen nach `--`.

## Testmodi

```
# KI gegen KI ohne Fenster, Statistik am Ende
godot --headless --fixed-fps 120 res://scenes/main.tscn -- --autoplay --rallies=500

# zusätzlich Regeln prüfen (Aufstellung, Libero, Sätze)
godot --headless --fixed-fps 240 res://scenes/main.tscn -- --autoplay --rallies=500 --check --sets=3

# simulierter Mensch (Neuling) bzw. Könner, Statistik
godot --headless --fixed-fps 120 res://scenes/main.tscn -- --autopress --rallies=300
godot --headless --fixed-fps 120 res://scenes/main.tscn -- --autopress --skilled --rallies=300

# zum Zuschauen
godot res://scenes/main.tscn -- --demo          # KI gegen KI
godot res://scenes/main.tscn -- --botplay       # simulierter Mensch mit Kamera, Zeitlupe, Wiederholungen
godot res://scenes/main.tscn -- --play          # Startmenü überspringen
```

**Pflicht bei Spiel-Änderungen:** `--autopress` (Neuling) vorher und nachher vergleichen. Der Neuling darf nicht schlechter abschneiden; `--skilled` soll klar profitieren. Die KI-gegen-KI-Statistik soll im Rauschen bleiben, außer die Änderung will genau das verschieben.

## Wichtige Schalter

| Schalter | Wirkung |
| --- | --- |
| `--seed=N` | fester Zufall (reproduzierbar mit `--autoplay` und im Labor) |
| `--rallies=N`, `--sets=N`, `--score=a:b`, `--rot=N` | Länge, Satzanzahl, Startstand, Rotation |
| `--teams=a,b`, `--home=a`, `--away=b` | Teams wählen (Dateiname aus `teams/`) |
| `--quick`, `--stufe=…`, `--pro` | Kurzes Match, Schwierigkeitsstufe, Profi-Optionen |
| `--drill=ID`, `--drill-opt=key:value` | Debug-Übung direkt starten (`annahme`, `zuspiel`, `angriff`, `aufschlag`, `block`, `abwehr`, `ballwechsel`, `laufen`, …) |
| `--debug-menu[=1]`, `--menu`, `--menu-tab=2:3`, `--club`, `--club-tab=…`, `--trainer` | Menüs direkt öffnen |
| `--popups` | alte Text-Einblendungen wieder an (nur zum Debuggen) |
| `--trace`, `--dive-trace` | Ablauf bzw. Hechtsprünge protokollieren |
| `--quit-after=SEK` | nach SEK Sekunden beenden und Statistik ausgeben |
| `--shot=datei.png@t1,t2 --quit-after-shot` | Bildschirmfoto zu Zeitpunkten |
| `--shot-phase=REPLAY:bild.png` | Foto kurz nach Beginn einer Phase |
| `--flow=SEK`, `--perf=SEK` | Messung von Bewegungsfluss bzw. Rechenzeit (`tools/flow_probe.gd`, `tools/perf_probe.gd`) |
| `--lab-…` | Animations-Labor, siehe unten |

Die vollständige Liste: `grep -o '"--[a-z-]*' scripts/*.gd tools/*.gd | sort -u`.

Ohne Grafikkarte (Linux-Server) Bilder mit `xvfb-run -a godot --rendering-driver opengl3 …` erzeugen. Nach dem Zusammenführen von Branches mit neuen `class_name`-Dateien einmal `godot --headless --import` laufen lassen, sonst meldet `main.gd` Parse-Fehler.

## Debug-Modus

Kachel **Debug** im Startmenü (oder **Y / T** im Spiel). Übungen für jede Aktion, Einstellungen (Rotation, Zuspiel auf, Tempo, Aufschlagart, Start mit Zuwurf oder Aufschlag), Abkürzungen für „Mein Verein“ (Münzen, Karten, Aufgaben). Für Beta- und Verkaufsversionen in `scripts/debug_mode.gd` `ENABLED = false` setzen.

## Animations-Labor

Ein Match mit festem Seed läuft erst ohne Bild und misst in jedem Physik-Takt alle zwölf Spieler: Fuß im Boden, Schweben, rutschende Füße, ruckende Gelenke („pops“), Teleport, überstreckte Knie, Arm durch den Rumpf, Körper im Netz, Spieler ineinander, Hand weit weg vom Ball beim Kontakt. Danach wird dasselbe Match mit Bild abgespielt und nur an den schlimmsten Stellen gefilmt.

```
tools/lab/lab.sh audit 11 36000 lab/      # 5 Minuten Spielzeit prüfen -> lab/audit.json, lab/zusammenfassung.txt
tools/lab/lab.sh film 11 lab/ 8           # die 8 schlimmsten Stellen filmen -> lab/sNN.mp4, lab/sNN_bogen.jpg
tools/lab/lab.sh film 11 lab/ 4 pop,float # nur bestimmte Fehlerarten
```

Braucht `xvfb-run`, `ffmpeg`, Python 3; Godot über `GODOT=/pfad/zu/godot`. Einzelne Bausteine abschalten zum Vergleichen: `--lab-off=video,mocap,loco,gaze,iksoft,chain,inert,varianten`. Vergleichsbasis sind die Seeds 11, 23, 37, 51.

Vorsicht: `pkill -f <muster>` trifft leicht die eigene Shell.

## Windows-Build

1. Export-Vorlagen für 4.4.1 installieren (Editor: *Editor → Export-Vorlagen verwalten*, oder nach `~/.local/share/godot/export_templates/4.4.1.stable/`).
2. Exportieren:
   ```
   godot --headless --export-release "Windows Desktop" build/Volleyball.exe
   ```
   Das Preset steht in `export_presets.cfg` (PCK eingebettet, x86_64). `build/` und `*.zip` sind in `.gitignore`.
3. `build/Volleyball.exe` zippen. Name nach dem Schema `Volleyball-<Name><Nummer>-Windows.zip`, z. B. `Volleyball-Varianz9-Windows.zip`.

Bisher wurden Builds nicht im Repo oder als GitHub-Release abgelegt, sondern in einem gemeinsamen Projektordner (`builds/<name>-<n>/`). Vorschlag dazu in [ARCHITEKTUR-PRUEFUNG.md](ARCHITEKTUR-PRUEFUNG.md).

## Assets neu bauen

| Was | Wie |
| --- | --- |
| Spielerfigur aus Meshy | `tools/blender/build_player_meshy.py <meshy.blend> assets/models/player.glb`, danach `build_figure_rigged.py`, `add_forearm_twist.py`, `add_finger_bones.py` (**nur einmal** auf eine frische glb anwenden) |
| Halle, Ball, Fahne, Fans | `tools/blender/build_arena.py` (bzw. `build_ball_meshy.py`, `build_net_meshy.py`, `build_props_meshy.py`) |
| Meshy-Clips | `tools/blender/extract_clips_meshy.py` → `assets/models/player_clips.json` |
| CMU-Mocap-Sprünge | `tools/mocap/build_jumps.sh` (nutzt `cmu_to_clips.py`) → `assets/models/mocap_jumps.json` |
| Bewegung aus Video | `tools/mocap/video_pose.py` (MediaPipe) → `video_to_clip.py <von> <bis> <sigma> <heading_smooth_s>` → `assets/models/video_clips.json` |
| Clip ansehen | `tools/mocap/view_clip.gd` |
| Geräusche | `python3 tools/make_sounds.py` → `assets/sounds/*.wav` |
| Teams | `python3 tools/make_teams.py` → `teams/*.tres` (fester Seed 20261014; überschreibt Handänderungen) |

Die Roh-Quellen (Meshy-Modelle, CMU-BVH, Pexels-Videos) liegen nicht im Repo. Die CMU-Daten sind frei; die Meshy-Modelle stammen aus Mattis' Account (CC BY 4.0).

## Neues Team anlegen

Eine Datei in `teams/` kopieren (z. B. `teams/seewald.tres`), `id`, `name`, Kürzel, Farben und Spieler ändern. Im Godot-Editor geht das per Doppelklick mit Farbwählern. Testen mit `-- --teams=neu,nordhafen`.
