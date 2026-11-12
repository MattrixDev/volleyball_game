# Ziele

Stand: 12.11.2026. Drei übergeordnete Ziele für die nächste Zeit:

1. **Es sieht fertig aus** (Visual Fix)
2. **Mehr Spielvielfalt**: kein Ballwechsel wie der andere, mehr Einfluss für den Spieler
3. **Eine Architektur, mit der mehrere Leute gut weiterbauen können**, siehe [ARCHITEKTUR-PRUEFUNG.md](ARCHITEKTUR-PRUEFUNG.md)

Für alle gilt: Wer die neuen Möglichkeiten nicht nutzt, spielt wie heute. Kein Text im Ballwechsel. Varianz aus der Lage, nicht aus Zufall. Faires Balancing (siehe [SPIELIDEE.md](SPIELIDEE.md#design-prinzipien)).

---

## Ziel 1: Sieht fertig aus (Visual Fix)

### Wo wir stehen

Die Spiellogik ist deutlich weiter als der Look. Mattis' Eindruck nach dem letzten Build: Das Spiel wirkt **„clunky“ und „zusammengewürfelt“**, die Spieler bewegen sich nicht wie Menschen. Bereits erledigt sind der saubere Bildschirm (nur Spielstand oben in der Mitte) und echte Bewegungen für Angriff und Aufschlag aus Videos.

### Warum es zusammengewürfelt wirkt (Diagnose vom 07.11.)

1. **Fünf Bewegungsquellen** werden je nach Lage anders gemischt: handgebaute Posen, Meshy-Clips, CMU-Mocap, Video-Bewegungen und Arm-IK. Jede hat ihre eigene Handschrift, Übergänge wirken wie Schnitte.
2. **Das Spiel schiebt die Figur, die Animation läuft hinterher.** Bei FIFA oder NBA 2K ist es umgekehrt: Die Animation bewegt den Körper (Root-Motion), das Spiel biegt sie nur zum Ball. Bei uns rutschen deshalb Füße, Hände werden zum Ball gezogen, Sprünge sehen aus wie Flugbahnen.
3. **Zu wenig Weite und Gewicht**: Die Figur bleibt kompakt, es fehlen Ausholen, Gewichtsverlagerung und Nachfedern.
4. **Figur und Bewegung passen nicht zusammen**: Eine fast echte Bewegung an einer facettierten, gesichtslosen Puppe wirkt seltsam; harte Gelenkknicke, flaches Licht.

### Drei Wege (Entscheidung von Mattis offen)

| Weg | Was | Vorteil | Nachteil |
| --- | --- | --- | --- |
| **A – Echt, aber aus einem Guss** (empfohlen) | Eine professionelle Volleyball-Mocap-Bibliothek ersetzt das Flickwerk; Animation treibt den Körper (AnimationTree mit Root-Motion, ggf. Motion-Matching-Plugin für Godot 4.4); etwas glattere Figuren, besseres Licht | einziger Weg zu „wie echtes Volleyball“ | größtes Stück Arbeit; Spieltempo muss zu den Animationen passen; Bibliothek kostet Geld (Lizenz prüfen) |
| **B – Stilisiert-sportlich** | Look wie Nintendo-Sportspiele: Comic-Figuren, übertriebene, handgemachte Posen | sieht schneller fertig aus, kleine Fehler fallen kaum auf | weicht von „realistisch“ ab; Figuren und Teile der UI neu |
| **C – Weiter polieren** | heutiges System behalten, Übergänge, Fußrutschen, Ausholen verbessern | billig, bricht nichts | stößt an dieselbe Grenze |

Vorgeschlagener erster Schritt für A: **nur den Angriff** mit einer Mocap-Bibliothek und Root-Motion bauen und als Vorher/Nachher-Video zeigen, bevor alles umgestellt wird.

### Was sonst noch zu „fertig“ gehört

- Licht und Materialien (weniger flach), ggf. weichere Figuren-Shading.
- Hallen in mehreren Stufen (Schulturnhalle bis Arena), später auch spielerisch relevant (Deckenhöhe).
- Präsentation zwischen den Punkten: Wiederholungen, Kamerafahrten, Körpersprache, Jubel (später als Kosmetik pro Team).
- Ton: Hallensprecher, Musik, Teamrufe.
- Einheitliche Menüs im Bento-Stil (Trainerbank-Redesign steht noch aus).

### Offene Fragen

- Welcher Weg (A, B, C)? Budget für eine Mocap-Bibliothek?
- Bei A: Lizenz erlaubt sie die Weitergabe der Dateien in einem **öffentlichen** Repository? Wahrscheinlich nicht, siehe [ARCHITEKTUR-PRUEFUNG.md](ARCHITEKTUR-PRUEFUNG.md#7-assets-und-lizenzen-im-öffentlichen-repo).
- Bleibt der facettierte Low-Poly-Stil, oder werden die Figuren glatter?

---

## Ziel 2: Mehr Spielvielfalt

### Leitbild

„Varianz, Varianz, Varianz“: Kein Ballwechsel soll wie der andere ablaufen, und der Spieler soll spüren, dass **er** den Unterschied macht. Vorbild FIFA: einfacher Einstieg, viel Tiefe.

### Die sechs Bausteine und ihr Stand

| Nr. | Baustein | Stand |
| --- | --- | --- |
| **V-1** | **Spielzüge wie bei FIFA**: Y + Steuerkreuz sagt Schnellangriff, Slide, Pipe oder Kombi an, Täuscher laufen mit, der Block muss raten | gebaut (Etappe 1) |
| **V-2** | **Keine zwei Ballwechsel gleich**: schlechte Annahme hat echte Folgen, Overpass, Netzkampf, Bälle nur per Hecht | gebaut (Etappe 1), Netzkampf in ca. 4–6 % der Ballwechsel |
| **V-3** | **Aufschlag als Waffe**: Spezialisten, Lücke zwischen zwei Annahmespielern, schwachen Annehmer anspielen | gebaut (Etappe 2) |
| **V-4** | **5-Sterne-Moves**: selten, an PlayStyles gebunden, per Trick-Taste Y | gebaut (Etappe 3), **im Playtest nicht bemerkt** |
| **V-5** | **KI mit eigenem Plan**: Spielweise pro Team, merkt sich deine Lieblingsschläge | gebaut (Etappe 2 und vorher K1/K2) |
| **V-6** | **Sieht fertig aus** | siehe Ziel 1 |

### Was als Nächstes fehlt

Die Mechaniken sind da, aber sie müssen **spürbar** werden. Der wichtigste Befund des letzten Playtests: Was der Spieler nicht bemerkt, erzeugt keine Vielfalt.

1. **Sichtbarkeit ohne Text**: Auslösen eines Moves spürbar machen (Ton, Vibration, Kamera, eigene Bewegung), kleines Symbol über dem Spieler, wenn ein Move möglich ist, Plus-PlayStyles mit deutlich stärkerer Wirkung. *(Vorschlag liegt bei Mattis.)*
2. **Spieler unterscheiden sich sichtbar**: ein Aufschlagspezialist muss anders aussehen und klingen als ein Durchschnittsspieler.
3. **Momentum und Spielverlauf** (K3): Druckphasen, Serien, Reaktion der Halle.
4. **Rotationen spielen eine Rolle** (K4): starke und schwache Rotationen, gezielter Einsatz von Spezialisten.
5. **Hallen als Spielfaktor**: niedrige Decke in der Schulhalle, Freizone.
6. **Mehr Spielmodi für Abwechslung**: lokaler Mehrspieler, Herausforderungen, Saison (gehört zu Spielerbindung, kommt nach dem Spielgefühl).

### Offene Fragen

- Wie sichtbar dürfen Moves und PlayStyles werden, ohne Text? (Symbol über dem Spieler ja/nein)
- Wie selten sollen 5-Sterne-Moves sein? Wie viel schwerer zu timen?
- Wann ist „Varianz genug“, um den Fokus auf den Look (Ziel 1) zu legen? Empfehlung: Sichtbarkeit (Punkt 1) noch fertig machen, dann Ziel 1 priorisieren, weil jeder neue Move sonst doppelt animiert werden muss.

---

## Ziel 3: Architektur

Siehe [ARCHITEKTUR-PRUEFUNG.md](ARCHITEKTUR-PRUEFUNG.md). Kurz: erst den neuesten Stand nach `main` bringen und einen automatischen Test einrichten, dann `match.gd` schrittweise aufteilen. Das Animationssystem erst umbauen, wenn der Weg für Ziel 1 entschieden ist.
