class_name SoundBank
extends Node
## Alle Geraeusche ausser dem Pfiff: Ballkontakte, Aufprall, Netz und das Publikum.
## Die Klaenge werden beim Start selbst erzeugt (keine Sounddateien noetig).

const RATE := 22050
const CROWD_RATE := 11025  # Publikum klingt gedaempft, das reicht und spart Rechenzeit

var sfx_volume := 70.0  # 0 bis 100, aus den Einstellungen
var crowd_volume := 60.0
var excitement := 0.0  # 0..1, laesst das Gemurmel in langen Ballwechseln anschwellen

var _sounds := {}
var _pool: Array = []
var _next := 0
var _ambience: AudioStreamPlayer
var _crowd: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 7
	_sounds["bump"] = _hit(0.16, 150.0, 85.0, 0.55, 0.35, 1800.0)
	_sounds["set"] = _hit(0.09, 260.0, 200.0, 0.35, 0.45, 3200.0)
	_sounds["spike"] = _hit(0.2, 170.0, 70.0, 0.75, 0.9, 6000.0)
	_sounds["serve"] = _hit(0.16, 190.0, 95.0, 0.6, 0.7, 5000.0)
	_sounds["tip"] = _hit(0.07, 320.0, 260.0, 0.25, 0.3, 2600.0)
	_sounds["block"] = _block()
	_sounds["floor"] = _hit(0.14, 120.0, 60.0, 0.5, 0.85, 4200.0)
	_sounds["net"] = _net()
	_sounds["cheer"] = _crowd_burst(3.2, true)
	_sounds["groan"] = _groan()
	_sounds["applause"] = _crowd_burst(2.4, false)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_ambience = AudioStreamPlayer.new()
	_ambience.stream = _murmur_loop()
	add_child(_ambience)
	_crowd = AudioStreamPlayer.new()
	add_child(_crowd)
	_ambience.volume_db = _db(crowd_volume, 0.35)
	_ambience.play()


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	excitement = maxf(0.0, excitement - real * 0.05)
	var want := _db(crowd_volume, 0.3 + excitement * 0.45)
	_ambience.volume_db = lerpf(_ambience.volume_db, want, clampf(real * 2.0, 0.0, 1.0))


func _db(vol: float, gain: float) -> float:
	var lin := vol / 100.0 * gain
	return -80.0 if lin <= 0.001 else linear_to_db(lin)


## Kurzer Ballkontakt; strength 0..1 macht ihn lauter und etwas tiefer.
func play(name: String, strength := 0.6) -> void:
	if not _sounds.has(name) or sfx_volume <= 0.0:
		return
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _sounds[name]
	p.volume_db = _db(sfx_volume, lerpf(0.35, 1.0, clampf(strength, 0.0, 1.0)))
	p.pitch_scale = _rng.randf_range(0.93, 1.07) * lerpf(1.08, 0.94, clampf(strength, 0.0, 1.0))
	p.play()


## Publikum: "cheer" (Jubel), "groan" (Raunen), "applause" (hoeflicher Applaus).
func crowd(name: String, strength := 1.0) -> void:
	if crowd_volume <= 0.0:
		return
	_crowd.stream = _sounds[name]
	_crowd.volume_db = _db(crowd_volume, clampf(strength, 0.2, 1.0))
	_crowd.pitch_scale = _rng.randf_range(0.96, 1.04)
	_crowd.play()


func stop_crowd() -> void:
	_crowd.stop()


# ---------------------------------------------------------------- Klangerzeugung

func _wav(samples: PackedFloat32Array, loop := false, rate := RATE) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	var peak := 0.0001
	for v in samples:
		peak = maxf(peak, absf(v))
	var g := 0.9 / peak
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] * g, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


## Ballkontakt: tiefer Koerper (abfallender Ton) plus kurzes Rauschen fuer den "Klatsch".
func _hit(dur: float, f0: float, f1: float, body: float, snap: float, bright: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	var lp := 0.0
	var a := clampf(bright / RATE * TAU, 0.0, 1.0)
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(f0, f1, minf(t / dur, 1.0))
		ph += TAU * f / RATE
		var tone := sin(ph) * exp(-t * 28.0) * body
		var noise := _rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * a
		var crack := (noise - lp * 0.6) * exp(-t * 90.0) * snap
		s[i] = tone + crack * minf(t * 4000.0, 1.0)
	return _wav(s)


func _block() -> AudioStreamWAV:
	var a := _hit_samples(0.18, 160.0, 80.0, 0.7, 0.8)
	var b := _hit_samples(0.16, 140.0, 70.0, 0.5, 0.5)
	var off := int(0.035 * RATE)
	var s := PackedFloat32Array()
	s.resize(a.size() + off)
	for i in a.size():
		s[i] += a[i]
	for i in b.size():
		if i + off < s.size():
			s[i + off] += b[i] * 0.7
	return _wav(s)


func _hit_samples(dur: float, f0: float, f1: float, body: float, snap: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * lerpf(f0, f1, t / dur) / RATE
		s[i] = sin(ph) * exp(-t * 26.0) * body + _rng.randf_range(-1.0, 1.0) * exp(-t * 80.0) * snap
	return s


func _net() -> AudioStreamWAV:
	var n := int(0.35 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.25
		var rattle := 0.6 + 0.4 * sin(TAU * 38.0 * t)
		s[i] = lp * exp(-t * 9.0) * rattle
	return _wav(s)


## Gemurmel der Halle als Endlosschleife: gefiltertes Rauschen, das langsam schwankt.
func _murmur_loop() -> AudioStreamWAV:
	var secs := 6.0
	var n := int(secs * CROWD_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var l1 := 0.0
	var l2 := 0.0
	var voices := []
	for v in 10:
		voices.append([_rng.randf_range(110.0, 260.0), _rng.randf() * TAU, _rng.randf_range(0.2, 0.7), 0.0])
	for i in n:
		var t := float(i) / CROWD_RATE
		var w := _rng.randf_range(-1.0, 1.0)
		l1 += (w - l1) * 0.12
		l2 += (l1 - l2) * 0.12
		var band := l1 - l2
		var talk := 0.0
		for v in voices:
			v[3] += TAU * v[0] * (1.0 + 0.03 * sin(t * 5.0 + v[1])) / CROWD_RATE
			var syll: float = maxf(0.0, sin(TAU * v[2] * t * 4.0 + v[1]))
			talk += sin(v[3]) * syll * syll
		s[i] = band * 2.2 + talk * 0.018
	# Ende weich in den Anfang ueberblenden, damit die Schleife nicht knackt.
	var fade := int(0.5 * CROWD_RATE)
	for i in fade:
		var k := float(i) / fade
		s[i] = s[i] * k + s[n - fade + i] * (1.0 - k)
	s.resize(n - fade)
	return _wav(s, true, CROWD_RATE)


## Jubel (mit Stimmen) oder nur Applaus: viele Klatscher plus anschwellendes Rauschen.
func _crowd_burst(secs: float, voices: bool) -> AudioStreamWAV:
	var n := int(secs * CROWD_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	# Klatscher: kurze Rauschimpulse, erst dicht, dann weniger.
	var claps := int(secs * (110.0 if voices else 80.0))
	for c in claps:
		var t0: float = pow(_rng.randf(), 1.6) * secs * 0.92
		var start := int(t0 * CROWD_RATE)
		var amp := _rng.randf_range(0.3, 1.0) * (1.0 - t0 / secs)
		var clen := int(_rng.randf_range(0.008, 0.02) * CROWD_RATE)
		var lp := 0.0
		for i in clen:
			if start + i >= n:
				break
			lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.6
			s[start + i] += lp * amp * exp(-float(i) / clen * 4.0) * 0.5
	if voices:
		var l1 := 0.0
		var l2 := 0.0
		var vs := []
		for v in 14:
			vs.append([_rng.randf_range(170.0, 420.0), 0.0, _rng.randf() * TAU, _rng.randf_range(0.0, 0.25)])
		for i in n:
			var t := float(i) / CROWD_RATE
			var env := minf(t / 0.18, 1.0) * exp(-maxf(0.0, t - 0.5) * 1.3)
			var w := _rng.randf_range(-1.0, 1.0)
			l1 += (w - l1) * 0.3
			l2 += (l1 - l2) * 0.3
			var shout := 0.0
			for v in vs:
				if t < v[3]:
					continue
				v[1] += TAU * v[0] * (1.0 + 0.04 * sin(t * 6.0 + v[2]) - 0.05 * t) / CROWD_RATE
				shout += (fmod(v[1] / TAU, 1.0) - 0.5)  # Saegezahn
			s[i] += (l1 - l2) * env * 1.6 + shout * env * 0.02
	return _wav(s, false, CROWD_RATE)


## "Ohhh" des Publikums: tiefe Stimmen, die abfallen.
func _groan() -> AudioStreamWAV:
	var secs := 1.6
	var n := int(secs * CROWD_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var vs := []
	for v in 12:
		vs.append([_rng.randf_range(140.0, 260.0), 0.0, _rng.randf_range(0.0, 0.12)])
	var lp := 0.0
	for i in n:
		var t := float(i) / CROWD_RATE
		var env := minf(t / 0.12, 1.0) * exp(-maxf(0.0, t - 0.4) * 2.2)
		var sum := 0.0
		for v in vs:
			if t < v[2]:
				continue
			v[1] += TAU * v[0] * (1.0 - 0.18 * t / secs) / CROWD_RATE
			sum += sin(v[1]) + 0.3 * sin(v[1] * 2.0)
		lp += (sum - lp) * 0.2
		s[i] = lp * env + _rng.randf_range(-1.0, 1.0) * env * 0.4
	return _wav(s, false, CROWD_RATE)
