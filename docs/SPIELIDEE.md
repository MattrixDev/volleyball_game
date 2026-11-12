# Spielidee, Regelumfang und Design-Prinzipien

## Die Idee in drei Sätzen

Ein Hallenvolleyballspiel für den PC, das sich anfühlt wie echtes Volleyball: echte Regeln, echte Techniken, echte Spielzüge. Der Einstieg ist leicht (ein Neuling kommt mit A und dem linken Stick durch), aber gute Spieler können viel mehr: Timing, Richtung, Spielzüge, Täuschungen, seltene Spezialmoves. Vorbild für Steuerung, Präsentation und Tiefe ist **FIFA / EA FC**.

## Regelumfang

- **FIVB-Hallenregeln 2025–2028**, 6 gegen 6, **nur Männer** (Netzhöhe 2,43 m). Frauen (2,24 m) sind vorerst nicht geplant.
- Ganzes Match: 2 oder 3 Gewinnsätze (einstellbar), Sätze bis 25, Entscheidungssatz bis 15, zwei Punkte Vorsprung, Seitenwechsel.
- Rotation und regelgerechte **5-1-Aufstellung** je Rotation (Positionsfehler werden mit `--check` geprüft).
- Kader mit 12–14 Spielern, **Libero** mit Libero-Regeln, Wechsel, Auszeiten (Mensch per Taste, KI selbst).
- Drei Berührungen, Block zählt nicht, Doppelberührung, gehaltener Ball, Netzfehler.
  - Ausnahme auf Mattis' Wunsch: **Block-Netzfehler gibt es nicht**. Greifen über das Netz macht den Block nur stärker.
- Zuspieler im Hinterfeld darf den zweiten Ball nicht oberhalb der Netzkante angreifen (dann wird still hoch gestellt).
- Schiedsrichter als 3D-Figur mit Handzeichen und Pfiff, vier Linienrichter.
- **Nur erfundene Teams und Spieler** (keine Lizenzen). Zurzeit 8 Teams mit je 14 Spielern.

## Design-Prinzipien

Diese Regeln hat Mattis über viele Playtests festgelegt. Sie gelten für jede Änderung.

1. **Realistisch, nicht Arcade.** Keine leuchtenden Schweife, keine übertriebenen Effekte. Jubel-Animationen und Effekte für Ass, Monsterblock usw. kommen später als kosmetische Ebene pro Team.
2. **Kein Text im Ballwechsel.** Während gespielt wird, steht nur der Spielstand oben in der Mitte (wie bei FIFA). Rückmeldung gibt es über Ton, Controller-Vibration, Kamera, Körpersprache der Spieler, Publikum, Wiederholungen und echte Spielfolgen. Wer ein Problem „fühlt sich nicht belohnend an“ mit einer Texteinblendung lösen will, liegt falsch. Einblendungen (Wechsel, Auszeit) nur zwischen den Punkten und knapp.
3. **Controller zuerst.** Jedes Menü muss vollständig mit dem Controller bedienbar sein: A bestätigt, B geht zurück, Steuerkreuz und linker Stick bewegen die Auswahl. Tastatur ist zweitrangig.
4. **Varianz aus der Lage, nie aus Zufall.** Welche Technik ein Spieler wählt, folgt aus der Situation (Abstand, Zeit, Druck). Gleiche Lage ergibt gleiche Technik. Fehler entstehen nur aus dem eigenen Spiel (Timing, Position, Entscheidung), damit der Spieler sie beeinflussen kann. Kein Würfeln über Erfolg.
5. **Hoher Skill-Gap, niedriger Einstieg.** Leicht anzufangen, viel mehr möglich für gute Spieler. Jede neue Eingabe ist optional. Wer sie nicht nutzt, spielt mindestens so gut wie vorher (geprüft mit dem simulierten Neuling `--autopress`). Hilfen sind pro Bereich einstellbar.
6. **Faires Balancing.** Mehr Können soll sich lohnen, aber keine 25:3-Spiele. Stärkere Teams gewinnen etwa 58–60 % der Punkte, nicht 90 %.
7. **Flüssig statt zusammengeklebt.** Aktionen sollen ineinander übergehen und nicht „plötzlich“ auf Tastendruck passieren. Keine Treffer-Pause (Hitstop) ohne aktivierte Zeitlupe.
8. **Menschliche Bewegungen.** Echte Bewegungsquellen (Mocap, Video) vor handgebauten Posen. Jede neue Bewegung wird gefilmt und auf Ruckler, unnatürliche Gelenke und fehlende Gewichtsverlagerung geprüft. Unmenschlich aussehende Ergebnisse gelten als Fehler, nicht als Feinschliff.
9. **Die Kamera darf dynamisch sein, aber nie das Spiel verdecken.**
10. **Ton einfach halten.** Gesamt, Effekte, Musik; Einzelregler nur unter „Erweitert“.

## Stil

- **Facettierter Low-Poly-Look**: athletische, männliche Figuren, Gesichter ohne Augen und Mund, matte Farben, weiches Licht.
- Alle 3D-Assets stammen aus Mattis' eigenen Meshy-Modellen oder aus Blender-Skripten in `tools/blender/`.
- Trikots modular pro Team (`teams/*.tres`).
- Menüs im hellen **„Bento“-Kachelstil** mit der Schrift Inter (`scripts/ui_theme.gd`).
- Ob der Look so bleibt, ist offen, siehe [ZIELE.md](ZIELE.md#ziel-1-sieht-fertig-aus-visual-fix).

## Reihenfolge Richtung Beta

Mattis' Prioritäten: **1. Wiederspielwert** (Spielgefühl, Varianz, Können lohnt sich), **2. Spielerbindung** (Verein, Saison, Herausforderungen), **3. Monetarisierung** (Plan: Premium-Spiel auf Steam mit Demo, später Inhalts-DLC und Kosmetik; kein Free-to-Play). „Mein Verein“ und die Karten werden erst weiterentwickelt, wenn sich das Match richtig gut anfühlt.

Spätere Wünsche: Hallensprecher, Musik, Teamrufe (auch als Kosmetik), verschiedene Hallen (Schulturnhalle bis Arena), lokaler Mehrspieler, Saison/Liga, Team-Editor.
