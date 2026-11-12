# Steuerung

Stand: Tastenplan „aus einem Guss“ (November 2026). Grundidee wie bei FIFA: **Jede Taste ist ein Verb und bedeutet überall dasselbe.** Der Spieler wählt, *was* passiert; *welche* Technik der Körper dafür nimmt, ergibt sich aus der Lage.

Belegt wird in `scripts/main.gd` `_setup_input()`, gelesen in `scripts/match.gd` `_read_input()`. Achtung: Einige interne Aktionsnamen stammen aus älteren Tastenplänen und passen nicht mehr zur Bedeutung (z. B. `set_fast` = B = Hechten, `serve_prev` = L1). Siehe [ARCHITEKTUR-PRUEFUNG.md](ARCHITEKTUR-PRUEFUNG.md).

## Controller

| Taste | Bedeutung | Im Detail |
| --- | --- | --- |
| **Linker Stick** | Spieler bewegen | Laufen, Block verschieben, beim Angriff Anlaufrichtung |
| **Rechter Stick** | Wohin der Ball geht | Angriffsrichtung/Trefferpunkt, Zuspiel-Feinziel, Dump-Richtung, Aufschlagziel |
| **A** | Ball spielen | Das Spiel wählt Baggern oder Pritschen. Beim 3. Kontakt: sicherer Ball rüber. Beim Aufschlag: einfacher, sicherer Aufschlag |
| **X** | Bewusst pritschen | erzwingt das obere Zuspiel |
| **B** | Hechten | immer; früh drücken (ideal etwa 0,3 s vor dem Ball) = Absprung |
| **R2** | Springen und schlagen | Halten = ausholen, Loslassen = Treffer. Sprungaufschlag, Angriff beim 2. und 3. Kontakt (Zuspieler-Angriff), Blocksprung |
| **L2** | Gefühl | mit R2: Leger/Roll-Shot, beim Zuspieler **Dump**, beim Aufschlag **Flatteraufschlag**; im Block: weicher Block |
| **R1** | Schnell und flach | flache Annahme, schnelles Zuspiel |
| **L1** | Hoch und sicher | hohe, sichere Annahme bzw. hohes Zuspiel |
| **Steuerkreuz** | Zuspielrichtung | links Außen, rechts Diagonal, oben Mitte, unten Hinterfeld |
| **Y + Steuerkreuz** | Spielzug ansagen | oben Schnellangriff Mitte, rechts Slide, unten Pipe, links Kombi. Geht auch vor dem Aufschlag (Handzeichen). Nochmal drücken = zurücknehmen |
| **Y gehalten** | Trick-Taste | 5-Sterne-Moves, siehe unten |
| **Y (kurz, zwischen den Punkten)** | Trainerbank | Auszeit, Libero, Wechsel |
| **R3** | Spieler wechseln | übernimmt den Mitspieler, der am schnellsten am Ball ist |
| **Select** | Laufhilfe an/aus | |
| **Start** | Pause / Einstellungen | |

**Timing:** Annahme, Zuspiel und Angriff funktionieren mit **Halten und Loslassen**. Der Moment des Loslassens ist der Ballkontakt. Je genauer, desto besser der Ball; ein Fehler verschiebt den Ball in die Richtung, die aus dem eigenen Timing folgt (zu früh / zu spät), nicht zufällig. Rückmeldung ohne Text über Ton, Vibration und einen kleinen Ring am Spieler (`scripts/touch_feedback.gd`).

**Menüs:** A bestätigt, B zurück, Steuerkreuz/linker Stick bewegen, LB/RB wechseln Seiten.

## Tastatur (zweitrangig)

| Aktion | Taste |
| --- | --- |
| Laufen | WASD / Pfeiltasten |
| Ball spielen (A) | Leertaste / Enter |
| Pritschen (X) | Q |
| Springen und schlagen (R2) | E |
| Gefühl (L2) | Umschalt |
| Schnell und flach (R1) | V |
| Hoch und sicher (L1) | 1 |
| Hechten (B) | R |
| Richtung (rechter Stick) | Maus oder I J K L |
| Spieler wechseln (R3) | Tab |
| Trainerbank / Y | T |
| Laufhilfe, Zeitlupe, Zoom | F1, F2, F3 |
| Pause | Esc |

Das Steuerkreuz (Zuspielrichtung, Spielzüge) hat noch keine eigene Tastaturbelegung.

## Spielzüge (V-1)

Mit **Y + Steuerkreuz** sagst du einen Spielzug an. Alle Angreifer laufen dann an, auch die, die den Ball nicht bekommen (Täuscher). Mit dem Steuerkreuz beim Zuspiel entscheidest du, wer ihn wirklich bekommt. Der gegnerische Mittelblocker muss raten; wie oft er auf die Täuschung hereinfällt, hängt von seinem Wert „Block lesen“ ab.

## 5-Sterne-Moves (V-4)

Selten, schwerer zu timen und **nur möglich, wenn der gesteuerte Spieler den passenden PlayStyle hat**. Ein Neuling braucht sie nie.

| Move | Eingabe | PlayStyle |
| --- | --- | --- |
| Schwachhand-Angriff | Y + R2 | Beidhänder |
| Dreh-Schlag hinter dem Kopf | Y + R2, Stick zur Anlaufseite | Winkelkünstler |
| Sprungzuspiel | Y + A/X | Sprungzuspieler |
| Skyball-Aufschlag | Y + A beim Aufschlag | Aufschlagtaktiker |
| Einarmige Rettung | Y + B | Hechtkönig |

Bekanntes Problem (Playtest 07.11.2026): Mattis hat PlayStyles und Moves im Spiel nicht bemerkt, weil sie still wirken. Vorgeschlagen sind spürbares Feedback beim Auslösen, ein kleines Symbol über dem Spieler (ohne Text) und stärkere Plus-Effekte. Noch nicht entschieden.

## Hilfen

Hilfen sind pro Bereich einstellbar (Einstellungen → Spiel): Timing-Fenster, Laufhilfe, Timing-Ausgleich für Bildschirm-/Controller-Verzögerung, Zeitlupe je Spielsituation, Gegnerstärke.
