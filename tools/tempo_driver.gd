extends Node
## Timing-Test mit echten Eingaben (Input.action_press) statt Testmodus: spielt als Mensch
## schnelle Zuspiele mit gehaltenem R2 und schlaegt danach genau im idealen Moment.
## Zaehlt die Bewertungen (PERFEKT, Gut, Zu spaet ...).
##   godot --headless -s res://tools/tempo_test.gd -- --play --quit-after=120
var m
var seen := {}
var counts := {}
var frame := 0
var dpad_held := false
var hit_held := false
var _main
var last_kind := "-"


func _physics_process(_delta: float) -> void:
	_drive()


func _press(a: String, on: bool) -> void:
	if Input.is_action_pressed(a) == on:
		return
	var ev := InputEventAction.new()
	ev.action = a
	ev.pressed = on
	ev.strength = 1.0 if on else 0.0
	Input.parse_input_event(ev)


func _drive() -> void:
	frame += 1
	if m == null:
		m = _main.match_node
		if m == null:
			return
		m.cfg.set_value("input_lag", 0.0)
	if m.phase == m.Phase.INTRO or m.phase == m.Phase.SET_OVER or m.phase == m.Phase.MATCH_OVER:
		_press("bump", frame % 20 < 10)
	# Bewertungen einsammeln
	for c in m.get_children():
		if c is Label3D and not seen.has(c):
			seen[c] = true
			var key: String = last_kind + ": " + c.text
			counts[key] = counts.get(key, 0) + 1
	var o = m.opp
	last_kind = o.kind if (o != null and not o.done and o.team == m.human_team) else ("serve" if m.phase == m.Phase.TOSS else "-")
	if m.phase == m.Phase.PRE_SERVE and m.serving_team == m.human_team and m.whistle_done:
		_press("hit", true)
		hit_held = true
		return
	if m.phase == m.Phase.TOSS and m.serving_team == m.human_team and hit_held and m.clock >= m.serve_ideal:
		_press("hit", false)
		hit_held = false
	if m.phase != m.Phase.RALLY or o == null or o.done or o.team != m.human_team:
		if hit_held and (o == null or o.kind != "attack"):
			pass
		return
	match o.kind:
		"set":
			if not dpad_held and m.clock >= o.t - 0.3:
				dpad_held = true
				_press("set_dir_left", true)
				_press("hit", true)  # R2 dazu = schneller Ball
				hit_held = true
			elif dpad_held and m.clock >= o.t:
				dpad_held = false
				_press("set_dir_left", false)  # Zuspiel, R2 bleibt gedrueckt
		"attack":
			if not hit_held and m.clock >= o.t - 0.4 and m.clock < o.t - 0.1:
				hit_held = true
				_press("hit", true)
			elif hit_held and m.clock >= o.t:
				hit_held = false
				_press("hit", false)
		_:
			if not o.pending and m.clock >= o.t - 0.2 and m.clock < o.t:
				_press("bump", true)
			elif m.clock >= o.t:
				_press("bump", false)


func _exit_tree() -> void:
	print("BEWERTUNGEN ", counts)
