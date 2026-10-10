class_name SoundBank
extends Node
## Alle Geraeusche ausser dem Pfiff: Ballkontakte, Aufprall, Netz, Schuhe und das Publikum.
## Die Klaenge liegen in assets/sounds (erzeugt mit tools/make_sounds.py), je Art mehrere
## Varianten, damit sich nichts genau wiederholt.

const DIR := "res://assets/sounds/"
const VARIANTS := {"bump": 3, "set": 3, "spike": 3, "serve": 3, "tip": 3, "block": 3, "floor": 3, "net": 2,
	"squeak": 4, "crowd_cheer": 2, "crowd_groan": 2, "crowd_applause": 2}

var sfx_volume := 70.0  # 0 bis 100, aus den Einstellungen
var crowd_volume := 60.0
var excitement := 0.0  # 0..1, laesst das Gemurmel in langen Ballwechseln anschwellen

var _sounds := {}  # Art -> Array von Streams
var _pool: Array = []
var _next := 0
var _ambience: AudioStreamPlayer
var _crowd: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	for kind in VARIANTS:
		var list := []
		for v in VARIANTS[kind]:
			var st = load(DIR + "%s_%d.wav" % [kind, v + 1])
			if st:
				list.append(st)
		_sounds[kind] = list
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_ambience = AudioStreamPlayer.new()
	_ambience.stream = load(DIR + "crowd_murmur.wav")
	_ambience.finished.connect(_ambience.play)  # Endlosschleife
	add_child(_ambience)
	_crowd = AudioStreamPlayer.new()
	add_child(_crowd)
	_ambience.volume_db = _db(crowd_volume, 0.5)
	_ambience.play()


func _pick(kind: String) -> AudioStream:
	var list: Array = _sounds.get(kind, [])
	return null if list.is_empty() else list[_rng.randi() % list.size()]


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	excitement = maxf(0.0, excitement - real * 0.05)
	var want := _db(crowd_volume, 0.45 + excitement * 0.5)
	_ambience.volume_db = lerpf(_ambience.volume_db, want, clampf(real * 2.0, 0.0, 1.0))


func _db(vol: float, gain: float) -> float:
	var lin := vol / 100.0 * gain
	return -80.0 if lin <= 0.001 else linear_to_db(lin)


## Kurzer Ballkontakt; strength 0..1 macht ihn lauter und etwas tiefer.
func play(name: String, strength := 0.6) -> void:
	var st := _pick(name)
	if st == null or sfx_volume <= 0.0:
		return
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = st
	p.volume_db = _db(sfx_volume, lerpf(0.45, 1.0, clampf(strength, 0.0, 1.0)))
	p.pitch_scale = _rng.randf_range(0.96, 1.04)
	p.play()


## Publikum: "cheer" (Jubel), "groan" (Raunen), "applause" (hoeflicher Applaus).
func crowd(name: String, strength := 1.0) -> void:
	if crowd_volume <= 0.0:
		return
	var st := _pick("crowd_" + name)
	if st == null:
		return
	_crowd.stream = st
	_crowd.volume_db = _db(crowd_volume, clampf(strength, 0.2, 1.0))
	_crowd.pitch_scale = _rng.randf_range(0.96, 1.04)
	_crowd.play()


func stop_crowd() -> void:
	_crowd.stop()
