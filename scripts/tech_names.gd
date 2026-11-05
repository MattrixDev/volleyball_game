class_name TechNames
extends RefCounted
## Namen und Tastenhinweise der Techniken (Schluessel wie im Arbeitsplan Skill-Gap).
## Der Name erscheint kurz nach dem Kontakt, der Hinweis beim ersten Mal, wenn die
## Technik in der Lage gerade moeglich ist.

## Schluessel -> [Name nach dem Kontakt, Tastenhinweis]
const TABLE := {
	# Annahme (Thread "Annahme steuerbar machen")
	"pass_flat": ["Flach ans Netz", "R1 halten beim Annehmen: flacher, schneller Pass ans Netz (kleineres Fenster)"],
	"pass_high": ["Hoch und sicher", "L1 halten beim Annehmen: hoher, sicherer Ball (kein Schnellangriff danach)"],
	"pass_fix": ["Seitlich ausgeglichen", "Ball neben dem Körper: linken Stick im Kontakt zur Gegenseite halten, dann fliegt er nicht weg"],
	"square": ["Frontal angenommen", "Lauf rechtzeitig hinter den Ball: größeres Timing-Fenster, genauere Annahme"],
	"side_taken": ["Seitlich angenommen", ""],
	"dive": ["Hecht", "B: selbst hechten (früh gehechtet reicht weiter)"],
	# Angriff
	"clean": ["Sauber getroffen", "R2 genau am höchsten Punkt loslassen: sauber getroffen, alle Winkel offen"],
	"roll": ["Roll-Shot", "L2 halten + R2: Roll-Shot mit halber Kraft hinter den Block"],
	"corner": ["Tiefe Ecke", "L2 + R2, rechter Stick nach oben: platziert in die tiefe Ecke"],
	"seam": ["In die Lücke", "L2 + R2, rechter Stick zur Seite: zwischen zwei Blocker"],
	"tool_hand": ["Block angeschlagen", "Rechter Stick zur Außenhand des Blocks"],
	"rebound": ["In den Block gelegt", "L2 + rechter Stick unten: Ball weich in den Block legen"],
	"approach_wide": ["Anlauf von außen", "Linker Stick zur Seitenlinie vor dem Absprung: Anlauf von außen, Diagonale offen"],
	"approach_tight": ["Enger Anlauf", "Linker Stick zur Feldmitte vor dem Absprung: enger Anlauf, Linie offen"],
	"approach_delay": ["Verzögerter Anlauf", "Linker Stick vom Netz weg vor dem Absprung: Anlauf verzögern, der Block springt zu früh"],
	"slide": ["Slide", "Mittelblocker: Slide hinter den Zuspieler"],
	# Zuspiel und Block (spaetere Etappen)
	"set_tight": ["Ans Netz gestellt", "Rechter Stick beim Zuspiel: näher ans Netz"],
	"set_off": ["Vom Netz weg", "Rechter Stick beim Zuspiel: weiter vom Netz weg"],
	"disguise": ["Verdecktes Zuspiel", "L2 beim Zuspiel: verdeckt spielen"],
	"block_soft": ["Weicher Block", "L2 beim Block: Hände nach hinten, Ball bremsen"],
}


static func text(key: String) -> String:
	return TABLE[key][0] if TABLE.has(key) else ""


static func hint(key: String) -> String:
	return TABLE[key][1] if TABLE.has(key) else ""
