class_name GameSettings
extends RefCounted
## Einstellungen fuer Schwierigkeit und Zeitlupe. Werden im Spiel ueber das Menue
## (Esc / Start) geaendert und in user://einstellungen.cfg gespeichert.

const PATH := "user://einstellungen.cfg"

## Reihenfolge, Text und Bereich der Regler im Menue.
## [Schluessel, Anzeige, min, max, Schritt, Einheit, Erklaerung]
const SLIDERS := [
	["slow_serve", "Zeitlupe Aufschlag", 0, 90, 5, "%", "Wie stark das Spiel beim eigenen Aufschlag verlangsamt wird"],
	["slow_receive", "Zeitlupe Annahme / Abwehr", 0, 90, 5, "%", "Kurz bevor du den Ball annimmst oder abwehrst"],
	["slow_set", "Zeitlupe Zuspiel", 0, 90, 5, "%", "Kurz bevor du zuspielst"],
	["slow_attack", "Zeitlupe Angriff", 0, 90, 5, "%", "Solange dein Angreifer in der Luft ist"],
	["slow_block", "Zeitlupe Block", 0, 90, 5, "%", "Solange dein Blocker oder der Angreifer in der Luft ist"],
	["receive_help", "Annahme-Hilfe", 100, 220, 10, "%", "Wie groß das Timing-Fenster bei Annahme und Abwehr ist"],
	["stick_hold", "Stick nachhalten", 0, 400, 25, "ms", "So lange gilt die Schlagrichtung noch, wenn du den rechten Stick loslässt"],
	["ai_defense", "Gegner-Abwehr", 0, 100, 5, "", "Wie gut der Gegner deine Angriffe abwehrt"],
	["ai_block", "Gegner-Block", 0, 100, 5, "", "Wie oft der Gegner dich blockt"],
	["faults", "Fehler-Strenge", 0, 100, 5, "%", "Wie oft Netzfehler, Doppelberührung und Ball gehalten passieren"],
]

const PRESETS := {
	"leicht": {"slow_serve": 60, "slow_receive": 45, "slow_set": 30, "slow_attack": 75, "slow_block": 75,
		"receive_help": 180, "stick_hold": 300, "ai_defense": 25, "ai_block": 25, "faults": 15},
	"normal": {"slow_serve": 50, "slow_receive": 30, "slow_set": 0, "slow_attack": 65, "slow_block": 65,
		"receive_help": 140, "stick_hold": 250, "ai_defense": 50, "ai_block": 50, "faults": 35},
	"profi": {"slow_serve": 30, "slow_receive": 0, "slow_set": 0, "slow_attack": 45, "slow_block": 45,
		"receive_help": 100, "stick_hold": 150, "ai_defense": 80, "ai_block": 75, "faults": 100},
}
const PRESET_TEXT := {"leicht": "Leicht", "normal": "Normal", "profi": "Profi", "eigene": "Eigene"}

var preset := "normal"
var values := {}


func _init() -> void:
	apply_preset("normal")


func apply_preset(name: String) -> void:
	preset = name
	values = (PRESETS[name] as Dictionary).duplicate()


func set_value(key: String, v: float) -> void:
	values[key] = v
	preset = "eigene"
	for p in PRESETS:
		var same := true
		for k in PRESETS[p]:
			if not is_equal_approx(float(PRESETS[p][k]), float(values.get(k, -1))):
				same = false
		if same:
			preset = p


func get_v(key: String) -> float:
	return float(values.get(key, PRESETS["normal"][key]))


## Spieltempo in einer Phase (1 = normal, 0,1 = zehnmal langsamer).
func time_scale(key: String) -> float:
	return 1.0 - get_v(key) / 100.0


## 0..1
func unit(key: String) -> float:
	return get_v(key) / 100.0


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("spiel", "stufe", preset)
	for k in values:
		cf.set_value("werte", k, values[k])
	cf.save(PATH)


func load_file() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	var p: String = cf.get_value("spiel", "stufe", "normal")
	apply_preset(p if PRESETS.has(p) else "normal")
	if p == "eigene":
		for s in SLIDERS:
			values[s[0]] = cf.get_value("werte", s[0], values[s[0]])
		preset = "eigene"
