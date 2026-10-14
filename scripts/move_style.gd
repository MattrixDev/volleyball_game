class_name MoveStyle
extends RefCounted
## Bewegungscharakter eines Spielers: kleine, feste Unterschiede in Haltung, Tempo und Technik,
## damit sich nicht alle Spieler gleich bewegen. Nur Optik: Timing, Treffpunkte und Spielstaerke
## bleiben gleich. Ausgewuerfelt aus einem Schluessel (spaeter PlayerData.movement_style, bis dahin
## Team und Nummer), also in jedem Match derselbe Charakter.

var posture := 0.0  # rad: Oberkoerper weiter vorn (+) oder aufrechter (-)
var head := 0.0  # rad: Kopf etwas mehr im Nacken (+) oder gesenkt (-)
var stance_depth := 1.0  # Bereitschaft: wie tief in den Knien
var stance_width := 0.0  # rad: Beine weiter auseinander (+) oder enger (-)
var tempo := 1.0  # Federn der Muskeln: zackig (>1) oder geschmeidig (<1)
var sway := 0.75  # Daempfung der Physik: weniger = schwingt laenger nach
var bob_rate := 1.0  # Wippen in der Bereitschaft: schneller oder langsamer
var bob_phase := 0.0
var arm_swing := 1.0  # Armschwung beim Laufen
var approach_depth := 1.0  # Anlauf: wie tief und wie weit die Arme nach hinten
var set_elbows := 1.0  # Pritschen: Ellbogen weiter aussen (>1) oder enger
var bump_depth := 1.0  # Baggern: tiefer oder hoeher in den Knien
var idle := 0  # Eigenheit zwischen den Ballwechseln (siehe VPlayer._p_idle)
var cheer := 0  # Jubel (siehe VPlayer._p_celebrate)


static func from_key(key: String) -> MoveStyle:
	var s := MoveStyle.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("move_style:" + key)
	s.posture = rng.randf_range(-0.07, 0.1)
	s.head = rng.randf_range(-0.08, 0.08)
	s.stance_depth = rng.randf_range(0.82, 1.18)
	s.stance_width = rng.randf_range(-0.06, 0.1)
	s.tempo = rng.randf_range(0.86, 1.16)
	s.sway = rng.randf_range(0.62, 0.86)
	s.bob_rate = rng.randf_range(0.8, 1.25)
	s.bob_phase = rng.randf_range(0.0, TAU)
	s.arm_swing = rng.randf_range(0.78, 1.22)
	s.approach_depth = rng.randf_range(0.85, 1.15)
	s.set_elbows = rng.randf_range(0.85, 1.15)
	s.bump_depth = rng.randf_range(0.85, 1.15)
	s.idle = rng.randi_range(0, 3)
	s.cheer = rng.randi_range(0, 3)
	return s


## Kleine Streuung je Aktion (gleicher Spieler schlaegt nicht zweimal exakt gleich): -1..1,
## fest fuer einen Zeitpunkt t (etwa den Ballkontakt), damit das Replay gleich aussieht.
static func noise(t: float, salt: int) -> float:
	var x := sin(t * 12.9898 + float(salt) * 78.233) * 43758.5453
	return (x - floorf(x)) * 2.0 - 1.0


## Beine tiefer oder hoeher (Huefte, Knie und Sprunggelenk gemeinsam) und breiter stellen.
static func legs(p: Dictionary, depth: float, width: float) -> void:
	for sd in ["l", "r"]:
		var s := -1.0 if sd == "l" else 1.0
		for k in ["hip_", "kn_", "an_"]:
			if p.has(k + sd):
				var v: Vector3 = p[k + sd]
				p[k + sd] = Vector3(v.x * depth, v.y, v.z + (width * s if k == "hip_" else 0.0))
