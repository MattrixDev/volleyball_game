# Architektur

Ein Überblick, wie der Code zusammenhängt. Eine kritische Bewertung (was gut ist, was wehtut) steht getrennt in [ARCHITEKTUR-PRUEFUNG.md](ARCHITEKTUR-PRUEFUNG.md).

## Grundsätze

- **Fast alles entsteht im Code.** `scenes/main.tscn` enthält nur einen leeren `Node3D` mit `scripts/main.gd`. Halle, Kamera, Spieler, Ball, HUD und Menüs werden in `_ready()` erzeugt. Es gibt keine Autoloads; gemeinsamer Zustand liegt in statischen Klassen (`Teams`, `GameSettings`, `Club`) oder wird als Referenz weitergereicht.
- **Physik mit 120 Hz** und Physik-Interpolation (`project.godot`). Spieler und Ball bewegen sich in `_physics_process`, Kamera, Halle, Publikum und Effekte in `_process`.
- **Koordinaten:** Netz bei `x = 0`. Team 0 (Heim, Mensch) spielt auf `x < 0`, Team 1 auf `x > 0`. „Lokal“ heißt aus Sicht eines Teams: `x` = Abstand zum Netz, `y` = seitlich (+ = rechts). Höhe ist `y` in Godot-Welt-Koordinaten.
- **Deterministisch, wo es geht:** `--seed=N` macht KI-gegen-KI-Spiele reproduzierbar (wichtig für das Animations-Labor). Mit simulierten Eingaben (`--autopress`) ist das nicht Tick-genau.

## Schichten

```
main.gd  (Komposition: Halle, Kamera, Ton, Effekte, Eingabe-Belegung, Menüs)
  ├── match.gd          Spielablauf, Regeln, KI, Eingaben, Ballberührungen   ← Herzstück
  │     ├── ballistics.gd     Flugbahnen und Vorhersage (statisch)
  │     ├── reception.gd      Annahme: Eingabe und Qualität
  │     ├── technique.gd      welche Technik in welcher Lage (anim_style)
  │     ├── formation.gd      Aufstellungen je Rotation (5-1, regelgerecht)
  │     ├── roster.gd         Kader, Rotation, Libero, Wechsel
  │     ├── ai_plan.gd        KI-Spielplan und Gedächtnis (K1/K2, V-5)
  │     ├── play_styles.gd    18 PlayStyles, pls(pl, id)
  │     ├── player_data.gd    Spielerwerte (Resource)
  │     ├── touch_feedback.gd Rumble, Ton, Timing-Ring (Feedback ohne Text)
  │     ├── debug_drill.gd    Übungen im echten Match
  │     └── player.gd (VPlayer) ×12   Laufen, Springen, Hechten, Posen-Auswahl
  │           └── figure.gd (HumanFigure)  Skelett, Federn, IK, Füße, Semi-Ragdoll
  │                 └── move_style.gd      persönlicher Bewegungscharakter (nur Optik)
  ├── arena.gd, net.gd, crowd.gd, referee.gd   Halle, Netz, Publikum, Schiedsrichter
  ├── sfx.gd, fx.gd                             Geräusche, Staub/Blitz
  ├── hud.gd, contact_pad.gd                    Spielstand, Trefferpunkt-Anzeige
  └── start_menu.gd, menu.gd, trainer.gd, club_menu.gd, debug_menu.gd, ui_theme.gd
```

## Datenfluss in einem Ballwechsel

1. `match.gd` `_physics_process` liest die Eingabe (`_read_input` → Dictionary `d`), bewegt den Ball (`ballistics.gd`) und fragt in `plan_next()` / `_try_team()`, **wer den Ball als Nächstes spielt und wann**. Das Ergebnis ist ein `Opp` (innere Klasse: Spieler, Team, Kontaktzeit und -punkt, Technik, Zeitfenster, Trick …).
2. Der gewählte `VPlayer` bekommt ein Ziel und läuft hin; menschliche Reaktionszeit und Beschleunigung stecken in `player.gd`.
3. Kurz vor dem Kontakt setzt `match.gd` am Spieler **`anim_kind`** (pass, dig, set, attack, free, serve …), **`anim_style`** (Technik aus `technique.gd` oder ein 5-Sterne-Move) und **`contact_pt`**. Das ist die zentrale Schnittstelle zwischen Spiellogik und Animation: Die Logik sagt *was*, die Figur entscheidet, *wie es aussieht*. Ein unbekannter Stil fällt auf die normale Bewegung zurück.
4. Beim Kontakt bewertet `match.gd` das Timing (`classify`, `excess`, `_err_dir`) und berechnet den neuen Ballflug. Fehler folgen aus dem Timing, nicht aus Zufall.
5. `match.gd` sendet Signale; `main.gd` hängt Ton, Effekte, Kamera, Vibration daran:
   - `contact(kind, pos, strength)` – Geräusch, Staub
   - `big_hit(strength)` – Kamerawackeln, Vibration, ggf. Zeitlupe
   - `point_won(winner, reason, highlight)` – Publikum, Wiederholung
   - `touch_result(...)` – Debug-Übungen
   - `touch_logged(team, info)` – KI-Gedächtnis
   - `own_block`, `play_called`, `technique_done`, `technique_available`
6. Punkt → `Phase.POINT_PAUSE` → ggf. `REPLAY` (aufgezeichnete Sekunden in Zeitlupe) → `PRE_SERVE`.

Phasen (`match.gd`): `INTRO, PRE_SERVE, TOSS, RALLY, POINT_PAUSE, TIMEOUT, SET_OVER, MATCH_OVER, REPLAY`.

## Inhaltsverzeichnis von `match.gd` (≈ 5 200 Zeilen)

Die Datei ist grob in diese Blöcke gegliedert (Stand November 2026; die Reihenfolge in der Datei ist nicht ganz so sauber):

| Bereich | Wichtige Funktionen |
| --- | --- |
| Zustand, Signale, Konstanten | `Opp`, `Phase`, `Q`, `play_call`, `stats` |
| Aufbau, Spielerdaten, PlayStyles | `_ready`, `_spawn_team`, `pdata`, `pf`, `pls`, `_set_trick` |
| Aufstellung, Formationen, Hilfslinien | `formation_pos`, `_receive_spots`, `_assign_lanes` |
| Timing-Bewertung | `windows`, `classify`, `excess`, `human_clock`, `ai_e` |
| Match, Sätze, Ballwechsel starten | `new_match`, `_start_set`, `start_rally`, `_check_rules` |
| Libero, Wechsel, Auszeit, Trainerbank | `libero_enter`, `substitute`, `call_timeout`, `_ai_maybe_sub` |
| Eingabe lesen | `_empty_input`, `_read_input`, `_held_stick` |
| Hauptschleife, Wiederholung | `_physics_process`, `_record`, `_step_replay` |
| Simulierte Eingaben (Tests) | `_auto_input`, `_skilled_attack`, `_pro_reception` |
| Aufschlag | `_do_toss`, `serve_style`, `_serve_hit`, `_serve_seam` |
| Wer spielt den Ball | `plan_next`, `_try_team`, `_overpass_hitter`, `_receiver`, `_nearest`, `_switch_player` |
| Block | `_assign_block` und folgende |
| Menschliche Aktionen: Zuspiel, Angriff, Dump, Spielzüge | `_set_input`, `_attack_input`, `_play_call_input`, `_dump_lane` |
| KI-Entscheidungen (über die Datei verteilt) | `_ai_attack_choice`, `_ai_serve_gap`, `_ai_pick_play`, `_ai_set_tempo` |
| Kontakt ausführen, Netzkampf, Punkt | `execute_touch`, `_net_fight`, `_end_rally` (hinterer Teil) |

Tipp: `grep -n "^func \|^## " scripts/match.gd` liefert die aktuelle Gliederung samt Kommentaren.

## Spielerfigur und Animation

Die Figur ist **prozedural animiert**, nicht über AnimationPlayer-Clips:

- `player.gd` (`VPlayer`, ≈ 2 400 Zeilen) bestimmt aus `anim_kind`/`anim_style`, Bewegung und Zeit bis zum Kontakt eine **Zielpose**. Quellen werden gemischt: handgebaute Posen, Meshy-Clips (`assets/models/player_clips.json`), CMU-Mocap-Sprünge (`mocap_jumps.json`) und Bewegungen aus Videos (`video_clips.json`).
- `figure.gd` (`HumanFigure`, ≈ 1 200 Zeilen) bringt die Pose auf das Skelett: Gelenkfedern (Drehung als Quaternion), Gelenkgrenzen (Swing-Twist), geometrische IK für Hände zum Ball und Füße auf den Boden, Semi-Ragdoll für Stöße und Landungen, Finger als Federn um den Ball.
- `move_style.gd` gibt jedem Spieler einen eigenen Bewegungscharakter (Haltung, Tempo, Ruhe-Eigenheiten), rein optisch, aus einem Hash des Spielers.
- Per-Spieler-Werte, die vor `setup()` gesetzt werden: `height_m` (gleichmäßige Skalierung, Modell = 1,88 m), `left_handed` (gespiegelte Angriffs-/Aufschlagposen), `movement_style`, `reach_add`, Sprungkraft.

Wichtig: **Das Spiel bewegt die Figur, die Animation läuft hinterher** (keine Root-Motion). Das macht die Spiellogik einfach und exakt, ist aber der Hauptgrund für rutschende Füße und den „zusammengewürfelten“ Look. Siehe [ZIELE.md](ZIELE.md).

## Daten

- `teams/*.tres` (`TeamStyle`): Name, Kürzel, Trikotfarben, Libero-Trikot und 14 `PlayerData` (Name, Rolle, Größe, Reichweite, 8 Werte 40–99, Eigenschaften). Erzeugt mit `tools/make_teams.py` (fester Seed). Ein neues Team = eine neue `.tres`.
- Stärke-Formel: `f = (Wert − 70) / 20` als Abweichung vom Normalspieler (`player_data.gd`).
- `club/nachwuchs.tres`: Startkader für „Mein Verein“. Spielstand des Vereins in `user://verein.json` (`club.gd`).
- Einstellungen in `user://einstellungen.cfg` (`settings.gd`).

## Werkzeuge im Repo

| Pfad | Zweck |
| --- | --- |
| `tools/blender/` | Figuren, Halle, Ball, Netz, Requisiten aus Blender bzw. Meshy-Modellen bauen (`pip install bpy`) |
| `tools/mocap/` | CMU-BVH und Video-Posen (MediaPipe) auf unser Skelett übertragen |
| `tools/lab/`, `scripts/anim_lab.gd` | Animations-Labor: misst Animationsfehler, filmt die schlimmsten Stellen |
| `tools/*.gd` | Prüfbilder und Messungen (Posen, Nahaufnahmen, Fluss, Performance, Formationen, Netz, Tempo) |
| `tools/make_sounds.py`, `tools/make_teams.py` | Geräusche und Teams erzeugen |

Bedienung: [ENTWICKLUNG.md](ENTWICKLUNG.md).
