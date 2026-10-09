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
	["whistle", "Lautstärke Pfiff", 0, 100, 5, "%", "Wie laut der Schiedsrichter pfeift (0 = aus)"],
	["serve_time", "Zeit für den Aufschlag", 8, 30, 1, "s", "So lange hast du nach dem Pfiff Zeit zum Aufschlagen (Regel: 8 Sekunden)"],
]

const PRESETS := {
	"leicht": {"slow_serve": 60, "slow_receive": 45, "slow_set": 30, "slow_attack": 75, "slow_block": 75,
		"receive_help": 180, "stick_hold": 300, "ai_defense": 25, "ai_block": 25, "faults": 15, "serve_time": 20},
	"normal": {"slow_serve": 50, "slow_receive": 20, "slow_set": 0, "slow_attack": 60, "slow_block": 50,
		"receive_help": 120, "stick_hold": 200, "ai_defense": 70, "ai_block": 70, "faults": 35, "serve_time": 12},
	"profi": {"slow_serve": 30, "slow_receive": 0, "slow_set": 0, "slow_attack": 45, "slow_block": 45,
		"receive_help": 100, "stick_hold": 150, "ai_defense": 80, "ai_block": 75, "faults": 100, "serve_time": 8},
}
const PRESET_TEXT := {"leicht": "Leicht", "normal": "Normal", "profi": "Profi", "eigene": "Eigene"}

var preset := "normal"
var values := {}
## Spielregeln (gehoeren zu keiner Stufe): Gewinnsaetze und Libero-Wechsel.
var sets_to_win := 2  # 1 = ein Satz, 2 = Best of 3, 3 = Best of 5
var libero_auto := false


func _init() -> void:
	apply_preset("normal")


func apply_preset(name: String) -> void:
	preset = name
	var keep: float = float(values.get("whistle", 35))  # Lautstärke gehört zu keiner Stufe
	values = (PRESETS[name] as Dictionary).duplicate()
	values["whistle"] = keep


func set_value(key: String, v: float) -> void:
	values[key] = v
	_detect_preset()


## Passen die Werte genau zu einer Stufe, heisst sie so, sonst "Eigene".
func _detect_preset() -> void:
	preset = "eigene"
	for p in PRESETS:
		var same := true
		for k in PRESETS[p]:
			if not is_equal_approx(float(PRESETS[p][k]), float(values.get(k, -1))):
				same = false
		if same:
			preset = p


func get_v(key: String) -> float:
	return float(values.get(key, PRESETS["normal"].get(key, 35)))


## Spieltempo in einer Phase (1 = normal, 0,1 = zehnmal langsamer).
func time_scale(key: String) -> float:
	return 1.0 - get_v(key) / 100.0


## 0..1
func unit(key: String) -> float:
	return get_v(key) / 100.0


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("spiel", "stufe", preset)
	cf.set_value("spiel", "gewinnsaetze", sets_to_win)
	cf.set_value("spiel", "libero_auto", libero_auto)
	for k in values:
		cf.set_value("werte", k, values[k])
	cf.save(PATH)


func load_file() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	sets_to_win = clampi(int(cf.get_value("spiel", "gewinnsaetze", 2)), 1, 3)
	libero_auto = bool(cf.get_value("spiel", "libero_auto", false))
	var p: String = cf.get_value("spiel", "stufe", "normal")
	apply_preset(p if PRESETS.has(p) else "normal")
	values["whistle"] = float(cf.get_value("werte", "whistle", 35))
	if p == "eigene":
		for s in SLIDERS:
			values[s[0]] = cf.get_value("werte", s[0], values[s[0]])
		_detect_preset()
