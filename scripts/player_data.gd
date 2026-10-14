## Ein Spieler mit fester Identitaet: Name, Groesse, Staerken und Spielstil. Die Daten liegen in
## den Team-Dateien (teams/*.tres, Liste players) und werden von tools/make_teams.py erzeugt.
## Staerken gehen von 1 bis 99; 70 ist ein normaler Spieler (so stark wie alle Spieler vor den
## Spielerdaten), 85 ein Nationalspieler.
class_name PlayerData
extends Resource

## Spielstile (traits): kleine, feste Eigenheiten. Schluessel -> Anzeige.
const TRAITS := {
	"linkshaender": "Linkshänder",
	"sprungwunder": "Sprungwunder",
	"lange_arme": "Lange Arme",
	"kanone": "Aufschlagkanone",
	"flatter": "Flatterkünstler",
	"katze": "Abwehrkatze",
	"blockleser": "Blockleser",
	"spielmacher": "Spielmacher",
	"kraftpaket": "Kraftpaket",
}
## Bezugsgroesse: so gross ist die Figur im Modell, und so weit reichen alle Spieler ohne Daten.
const REF_HEIGHT := 1.95
const REF_JUMP_H := 0.80

@export var id := ""  ## eindeutig, z. B. "nordhafen_07"; auch Schluessel fuer den Bewegungscharakter
@export var first_name := ""
@export var last_name := ""
@export var number := 1
@export var role := "OH"  ## S, OH, MB, OP, L
@export_range(1.70, 2.20, 0.01) var height_m := 1.95
@export_group("Staerken (1 bis 99)")
@export_range(1, 99) var jump := 70
@export_range(1, 99) var power := 70
@export_range(1, 99) var serve := 70
@export_range(1, 99) var receive := 70
@export_range(1, 99) var defense := 70
@export_range(1, 99) var setting := 70
@export_range(1, 99) var block := 70
@export_range(1, 99) var speed := 70
@export_group("Aussehen und Stil")
@export var traits: PackedStringArray = []
@export var left_handed := false
@export var skin := 0
@export var hair := 0
@export var movement_style := ""  ## leer = id


func full_name() -> String:
	return "%s %s" % [first_name, last_name]


func has_trait(t: String) -> bool:
	return traits.has(t)


## Abweichung einer Staerke vom normalen Spieler: 40 -> -1, 70 -> 0, 99 -> knapp +1.
func f(key: String) -> float:
	return clampf((float(get(key)) - 70.0) / 30.0, -1.5, 1.0)


## So viel hoeher (m) als ein Spieler mit 1,95 m reicht er im Stand mit gestrecktem Arm.
## Die Reichweite im Stand ist bei Volleyballern etwa das 1,33-Fache der Koerpergroesse.
func reach_add() -> float:
	return (height_m - REF_HEIGHT) * 1.33 + (0.06 if has_trait("lange_arme") else 0.0)


## Sprunghoehe (m) beim Angriff und Block.
func jump_h() -> float:
	return REF_JUMP_H + 0.004 * float(jump - 70) + (0.05 if has_trait("sprungwunder") else 0.0)


## Absprunggeschwindigkeit (m/s) fuer diese Sprunghoehe.
func jump_v() -> float:
	return sqrt(2.0 * 9.81 * jump_h())


## Gesamtwertung fuer die Position (gewichtet nach dem, was die Rolle braucht).
func overall() -> int:
	var w: Dictionary = {
		"S": {"setting": 4, "defense": 1, "serve": 1, "block": 1, "speed": 1},
		"OH": {"power": 2, "receive": 2, "jump": 1, "serve": 1, "defense": 1, "block": 1},
		"OP": {"power": 3, "jump": 2, "serve": 1, "block": 1},
		"MB": {"block": 3, "jump": 2, "power": 1, "speed": 1, "serve": 1},
		"L": {"receive": 3, "defense": 3, "speed": 1},
	}[role]
	var sum := 0.0
	var n := 0
	for k in w:
		sum += float(get(k)) * w[k]
		n += w[k]
	return roundi(sum / n)


## Kurzbeschreibung fuer Listen: "2,04 m · Mittelblocker 78 · Lange Arme".
func summary() -> String:
	var t := "%s m · %d" % [("%.2f" % height_m).replace(".", ","), overall()]
	for tr in traits:
		t += " · " + str(TRAITS.get(tr, tr))
	return t
