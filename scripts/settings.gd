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
	["input_lag", "Timing-Ausgleich", 0, 200, 10, "ms", "Gleicht die Verzögerung von Bildschirm und Controller aus: so viel später darfst du drücken oder loslassen"],
	["stick_hold", "Stick nachhalten", 0, 400, 25, "ms", "So lange gilt die Schlagrichtung noch, wenn du den rechten Stick loslässt"],
	["ai_defense", "Gegner-Abwehr", 0, 100, 5, "", "Wie gut der Gegner deine Angriffe abwehrt"],
	["ai_block", "Gegner-Block", 0, 100, 5, "", "Wie oft der Gegner dich blockt"],
	["faults", "Fehler-Strenge", 0, 100, 5, "%", "Wie oft Netzfehler, Doppelberührung und Ball gehalten passieren"],
	["master", "Gesamtlautstärke", 0, 100, 5, "%", "Alles zusammen: Effekte und später die Musik (0 = stumm)"],
	["fx_vol", "Effektlautstärke", 0, 100, 5, "%", "Alle Geräusche im Spiel: Ball, Pfiff, Schuhe und Publikum (0 = aus). Einzeln einstellbar unter Erweitert"],
	["music", "Musiklautstärke", 0, 100, 5, "%", "Noch gibt es keine Musik im Spiel, der Regler ist schon da"],
	["whistle", "Pfiff", 0, 100, 5, "%", "Wie laut der Schiedsrichter pfeift (0 = aus)"],
	["sfx", "Ball (Baggern, Pritschen, Netz, Aufprall)", 0, 100, 5, "%", "Lautstärke dieser Ballgeräusche (0 = aus)"],
	["snd_hit", "Schlag und Aufschlag", 0, 100, 5, "%", "Wie laut Angriff, Aufschlag und Leger knallen (0 = aus)"],
	["snd_block", "Block", 0, 100, 5, "%", "Wie laut der Ball am Block klingt (0 = aus)"],
	["snd_shoes", "Schuhquietschen", 0, 100, 5, "%", "Quietschen beim Absprung und Hechten (0 = aus)"],
	["crowd", "Publikum Grundgeräusch", 0, 100, 5, "%", "Gemurmel in der Halle, das in langen Ballwechseln lauter wird (0 = aus)"],
	["crowd_fx", "Publikum Jubel und Raunen", 0, 100, 5, "%", "Jubel, Applaus und Raunen nach Punkten (0 = aus)"],
	["serve_time", "Zeit für den Aufschlag", 8, 30, 1, "s", "So lange hast du nach dem Pfiff Zeit zum Aufschlagen (Regel: 8 Sekunden)"],
]

const PRESETS := {
	"leicht": {"slow_serve": 40, "slow_receive": 35, "slow_set": 20, "slow_attack": 50, "slow_block": 50,
		"receive_help": 180, "stick_hold": 300, "input_lag": 90, "ai_defense": 25, "ai_block": 25, "faults": 15, "serve_time": 20},
	"normal": {"slow_serve": 25, "slow_receive": 10, "slow_set": 0, "slow_attack": 30, "slow_block": 30,
		"receive_help": 120, "stick_hold": 200, "input_lag": 80, "ai_defense": 70, "ai_block": 70, "faults": 35, "serve_time": 12},
	"profi": {"slow_serve": 10, "slow_receive": 0, "slow_set": 0, "slow_attack": 15, "slow_block": 15,
		"receive_help": 100, "stick_hold": 150, "input_lag": 70, "ai_defense": 80, "ai_block": 75, "faults": 100, "serve_time": 8},
}
const PRESET_TEXT := {"leicht": "Leicht", "normal": "Normal", "profi": "Profi", "eigene": "Eigene"}

var preset := "normal"
var values := {}
## Spielregeln (gehoeren zu keiner Stufe): Gewinnsaetze und Libero-Wechsel.
var sets_to_win := 2  # 1 = ein Satz, 2 = Best of 3, 3 = Best of 5
var libero_auto := false
var replays := true  # Wiederholung starker Punkte

## Lautstaerken gehoeren zu keiner Stufe. Die Einzelregler (Pfiff, Ball, ...) gelten relativ zur
## Effektlautstaerke, die Effektlautstaerke relativ zur Gesamtlautstaerke.
const AUDIO := {"master": 100, "fx_vol": 100, "music": 100, "whistle": 35, "sfx": 70, "snd_hit": 100,
	"snd_block": 100, "snd_shoes": 100, "crowd": 60, "crowd_fx": 100}
const AUDIO_SIMPLE := ["master", "fx_vol", "music"]
const AUDIO_ADVANCED := ["whistle", "sfx", "snd_hit", "snd_block", "snd_shoes", "crowd", "crowd_fx"]

## Kamera je Spielablauf. Entfernung und Hoehe in Prozent der Standardansicht, Neigung (Blick hoch
## oder runter) und Sichtfeld in Grad dazu.
const CAM_MODES := [["view", "Übersicht"], ["serve", "Aufschlag"], ["attack", "Angriff"], ["block", "Block"], ["replay", "Wiederholung"]]
const CAM_PARAMS := [
	["dist", "Entfernung", 50, 160, 5, "%", "Wie weit die Kamera vom Geschehen weg ist (100 = Standard)"],
	["height", "Höhe", 40, 180, 5, "%", "Wie hoch die Kamera steht (100 = Standard)"],
	["tilt", "Neigung", -20, 20, 1, "°", "Blick nach oben (+) oder unten (−), 0 = Standard"],
	["fov", "Sichtfeld", -15, 20, 1, "°", "Weiter Blickwinkel (+) oder näher heranzoomen (−), 0 = Standard"],
]
const CAM_GLOBAL := [
	["cam_follow", "Ball folgen", 0, 200, 10, "%", "Wie stark die Übersichtskamera mit dem Ball mitgeht (0 = steht fest)"],
	["cam_smooth", "Reaktion", 40, 200, 10, "%", "Wie schnell die Kamera Bewegungen nachzieht (niedrig = weich und träge, hoch = direkt)"],
	["cam_shake", "Kamerawackeln", 0, 200, 10, "%", "Wie stark die Kamera bei harten Schlägen wackelt (0 = aus)"],
	["cam_punch", "Heranrücken beim Wuchtschlag", 0, 200, 10, "%", "Wie stark die Kamera bei einem Wuchtschlag kurz heranzoomt (0 = aus)"],
]
static var CAM_DEFAULTS := _cam_defaults()


static func _cam_defaults() -> Dictionary:
	var d := {}
	for m in CAM_MODES:
		for p in CAM_PARAMS:
			d["cam_%s_%s" % [m[0], p[0]]] = 0.0 if p[5] == "°" else 100.0
	for g in CAM_GLOBAL:
		d[g[0]] = 100.0
	return d


## Alle Regler fuer das Menue, auch die der Kamera (je Ablauf: cam_<ablauf>_<art>).
static func all_sliders() -> Array:
	var list: Array = SLIDERS.duplicate()
	for m in CAM_MODES:
		for p in CAM_PARAMS:
			list.append(["cam_%s_%s" % [m[0], p[0]], p[1], p[2], p[3], p[4], p[5], "%s: %s" % [m[1], p[6]]])
	list.append_array(CAM_GLOBAL)
	return list


## Kamera einer Gruppe auf Standard.
func reset_camera(prefix: String) -> void:
	for k in CAM_DEFAULTS:
		if k.begins_with(prefix):
			values[k] = CAM_DEFAULTS[k]


func _init() -> void:
	apply_preset("normal")


func apply_preset(name: String) -> void:
	preset = name
	var keep := {}
	for k in AUDIO:
		keep[k] = float(values.get(k, AUDIO[k]))
	for k in CAM_DEFAULTS:
		keep[k] = float(values.get(k, CAM_DEFAULTS[k]))
	values = (PRESETS[name] as Dictionary).duplicate()
	values.merge(keep)


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
	return float(values.get(key, PRESETS["normal"].get(key, AUDIO.get(key, CAM_DEFAULTS.get(key, 35)))))


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
	cf.set_value("spiel", "wiederholungen", replays)
	for k in values:
		cf.set_value("kamera" if CAM_DEFAULTS.has(k) else "werte", k, values[k])
	cf.save(PATH)


func load_file() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	sets_to_win = clampi(int(cf.get_value("spiel", "gewinnsaetze", 2)), 1, 3)
	libero_auto = bool(cf.get_value("spiel", "libero_auto", false))
	replays = bool(cf.get_value("spiel", "wiederholungen", true))
	var p: String = cf.get_value("spiel", "stufe", "normal")
	apply_preset(p if PRESETS.has(p) else "normal")
	for k in AUDIO:
		values[k] = float(cf.get_value("werte", k, AUDIO[k]))
	for k in CAM_DEFAULTS:
		values[k] = float(cf.get_value("kamera", k, CAM_DEFAULTS[k]))
	if p == "eigene":
		for s in SLIDERS:
			values[s[0]] = cf.get_value("werte", s[0], values[s[0]])
		_detect_preset()
