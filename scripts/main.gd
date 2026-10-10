extends Node3D
## Baut Halle, Licht, Kamera und Steuerung auf und startet das Match.

const MatchScript := preload("res://scripts/match.gd")
const HudScript := preload("res://scripts/hud.gd")

var camera: Camera3D
var match_node
var _shake := 0.0
var _cam_base := Vector3(-18.5, 9.5, 0.0)
var _cam_pos := Vector3(-18.5, 9.5, 0.0)
var _cam_look := Vector3(1.5, 1.0, 0.0)
var arena: Arena
var fx: HitFx
var _air := {}  # Spieler -> war in der Luft (fuer Schuhquietschen)
var sfx: SoundBank
var crowd: CrowdView
var hud
var menu
var start_menu
var _shot_phase := ""
var _shot_phase_t := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--teams="):  # Test: --teams=seewald,nordhafen
			Teams.home = a.get_slice("=", 1).get_slice(",", 0)
			Teams.away = a.get_slice("=", 1).get_slice(",", 1)
	_setup_input()
	arena = Arena.new()
	# Spieler und Ball laufen mit 120 Hz Physik und werden fuer jeden Bildschirm-Frame
	# weich dazwischen gerechnet (Physik-Interpolation). Was in _process bewegt wird
	# (Kamera, Halle, Publikum, Effekte), braucht das nicht.
	arena.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(arena)
	camera = Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.fov = 52.0
	add_child(camera)
	camera.position = _cam_base
	camera.look_at(Vector3(1.5, 1.0, 0.0))

	fx = HitFx.new()
	fx.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(fx)
	sfx = SoundBank.new()
	add_child(sfx)
	crowd = CrowdView.new()
	crowd.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(crowd)
	hud = HudScript.new()
	add_child(hud)
	match_node = MatchScript.new()
	match_node.hud = hud
	hud.whistled.connect(func(): arena.referee_whistle())
	match_node.big_hit.connect(_on_big_hit)
	match_node.contact.connect(_on_contact)
	match_node.point_won.connect(_on_point)
	add_child(match_node)
	var trainer := preload("res://scripts/trainer.gd").new()
	trainer.match_node = match_node
	hud.add_child(trainer)
	hud.trainer = trainer
	start_menu = preload("res://scripts/start_menu.gd").new()
	start_menu.cfg = match_node.cfg
	start_menu.play.connect(_on_play)
	start_menu.settings.connect(func(): menu.open(true))
	hud.add_child(start_menu)
	start_menu.visible = false
	menu = preload("res://scripts/menu.gd").new()
	menu.cfg = match_node.cfg
	menu.match_node = match_node
	menu.closed.connect(_on_menu_closed)
	menu.to_title.connect(_on_to_title)
	hud.add_child(menu)
	if match_node.attract:
		hud.set_attract(true)
		start_menu.call_deferred("open")
	if OS.get_cmdline_user_args().has("--play") or Teams.autostart:
		Teams.autostart = false
		call_deferred("_on_play")  # Test: Startmenue ueberspringen; nach Teamwechsel direkt spielen
	if OS.get_cmdline_user_args().has("--menu"):
		menu.call_deferred("open")
	if OS.get_cmdline_user_args().has("--trainer"):
		get_tree().create_timer(0.4).timeout.connect(trainer.open)  # Test: Trainerbank oeffnen

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_screenshot_later(a.get_slice("=", 1))
		elif a.begins_with("--shot-phase="):
			# Test: --shot-phase=REPLAY:bild.png speichert ein Bild kurz nach Beginn dieser Phase.
			_shot_phase = a.get_slice("=", 1)
		elif a.begins_with("--quit-after="):
			# Test: nach N Sekunden Spielzeit Statistik ausgeben und beenden.
			get_tree().create_timer(float(a.get_slice("=", 1)), true, true).timeout.connect(func():
				match_node._print_stats()
				get_tree().quit())


func _process(delta: float) -> void:
	# Kamera in Echtzeit bewegen, auch waehrend der Zeitlupe.
	var rd := delta / maxf(Engine.time_scale, 0.01)
	var bz: float = match_node.ball.position.z if match_node and match_node.ball else 0.0
	# Die Kamera steht immer hinter dem eigenen Team, auch nach dem Seitenwechsel.
	var cs: float = match_node.camera_side() if match_node else -1.0
	var want_pos := Vector3(cs * absf(_cam_base.x), _cam_base.y, bz * 0.25)
	var want_look := Vector3(-cs * 1.5, 1.0, bz * 0.2)
	var want_fov := 52.0
	var subj = match_node.cam_subject if match_node else null
	if match_node and match_node.cam_mode == "replay":
		# Fernsehkamera von der Seitenlinie, folgt dem Ball.
		var b: Vector3 = match_node.ball.position
		want_pos = Vector3(b.x * 0.6, 5.2, -12.2)
		want_look = Vector3(b.x * 0.9, maxf(b.y * 0.6, 0.8), b.z * 0.3)
		want_fov = 44.0
	elif subj != null:
		var s: float = subj.side
		var p: Vector3 = subj.position
		match match_node.cam_mode:
			"serve":
				# Hinter der Schulter des Aufschlaegers.
				want_pos = p + Vector3(s * 4.4, 3.3, 2.4)
				want_look = Vector3(-s * 4.0, 2.6, p.z * 0.4)
				want_fov = 55.0
			"attack":
				want_pos = Vector3(s * 5.2, 3.3, p.z * 0.75 + 0.6)
				want_look = Vector3(-s * 2.0, 2.4, p.z * 0.6)
				want_fov = 56.0
			"block":
				want_pos = Vector3(s * 5.6, 3.6, p.z * 0.7)
				want_look = Vector3(-s * 3.0, 2.2, p.z * 0.6)
				want_fov = 56.0
	var k := clampf(rd * 4.0, 0.0, 1.0)
	_cam_pos = _cam_pos.lerp(want_pos, k)
	_cam_look = _cam_look.lerp(want_look, k)
	camera.fov = lerpf(camera.fov, want_fov, k)
	var off := Vector3.ZERO
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - rd * 2.5)
		off = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.25
	camera.position = _cam_pos + off
	camera.look_at(_cam_look + off * 0.5)
	if _shot_phase != "" and match_node:
		var want: int = match_node.Phase[_shot_phase.get_slice(":", 0)]
		_shot_phase_t = _shot_phase_t + rd if match_node.phase == want else 0.0
		if _shot_phase_t > 1.6:
			var out := _shot_phase.get_slice(":", 1)
			_shot_phase = ""
			get_viewport().get_texture().get_image().save_png(out)
			print("Screenshot gespeichert: ", out)
			if OS.get_cmdline_user_args().has("--quit-after-shot"):
				get_tree().quit()
	if match_node:
		_update_hall()
		sfx.sfx_volume = match_node.cfg.get_v("sfx")
		sfx.crowd_volume = match_node.cfg.get_v("crowd") * (0.6 if match_node.attract else 1.0)


func _on_big_hit(strength: float) -> void:
	_shake = maxf(_shake, strength)


func _on_play() -> void:
	start_menu.visible = false
	hud.set_attract(false)
	sfx.stop_crowd()
	match_node.start_game()


func _on_to_title() -> void:
	match_node.back_to_title()
	hud.set_attract(true)
	start_menu.open()


func _on_menu_closed() -> void:
	if start_menu.visible:
		start_menu.focus()


## Ballkontakte: Geraeusch, Lichtblitz bei harten Schlaegen, Staub am Boden.
func _on_contact(kind: String, pos: Vector3, strength: float) -> void:
	sfx.play(kind, strength)
	sfx.excitement = minf(1.0, match_node.rally_touches / 10.0)
	match kind:
		"spike":
			fx.flash(pos, strength)
			if strength > 0.75:
				_shake = maxf(_shake, 0.25)
		"serve":
			if strength > 0.7:
				fx.flash(pos, strength * 0.8)
		"block":
			fx.flash(pos, strength, Color(0.85, 0.92, 1.0))
		"floor":
			fx.dust(pos, strength)
			if strength > 0.8:
				_shake = maxf(_shake, 0.3)


## Publikum: die Fans des Gewinners jubeln, bei Punkten gegen dich raunt die Halle.
func _on_point(winner: int, reason: String, highlight: bool) -> void:
	var fav: int = match_node.human_team
	var big: bool = highlight or match_node.rally_touches >= 8
	if fav < 0 or winner == fav:
		sfx.crowd("cheer", 1.0 if big else 0.65)
		crowd.cheer(winner, 1.0 if big else 0.6)
	elif reason in ["Ass!", "Block-Punkt!", "Angriffspunkt!"] or big:
		sfx.crowd("groan", 0.8)
		crowd.cheer(winner, 0.5)
	else:
		sfx.crowd("applause", 0.4)
		crowd.cheer(winner, 0.35)


## Testhilfe: --shot=bild.png@2,4.5 speichert Bilder nach 2 und 4,5 Sekunden.
func _screenshot_later(spec: String) -> void:
	var path := spec.get_slice("@", 0)
	var times := spec.get_slice("@", 1).split(",") if spec.contains("@") else PackedStringArray(["2"])
	var waited := 0.0
	for ts in times:
		var t := float(ts)
		await get_tree().create_timer(t - waited, true, false, true).timeout
		waited = t
		var img := get_viewport().get_texture().get_image()
		var out := path.get_basename() + "_" + ts + ".png"
		img.save_png(out)
		print("Screenshot gespeichert: ", out)
	if OS.get_cmdline_user_args().has("--quit-after-shot"):
		get_tree().quit()


# ---------------------------------------------------------------- Steuerung

func _setup_input() -> void:
	_action("move_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_action("move_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_action("move_up", [KEY_W, KEY_UP], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]])
	_action("move_down", [KEY_S, KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]])
	# Rechter Stick = Trefferpunkt am Ball (Tastatur: Maus oder I J K L)
	_action("aim_left", [KEY_J], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_action("aim_right", [KEY_L], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_action("aim_up", [KEY_I], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_action("aim_down", [KEY_K], [], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_action("bump", [KEY_SPACE, KEY_ENTER], [JOY_BUTTON_A])
	_action("overhand", [KEY_Q], [JOY_BUTTON_X])
	_action("hit", [KEY_E], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_action("serve_prev", [KEY_1], [JOY_BUTTON_LEFT_SHOULDER])
	_action("serve_next", [KEY_2], [JOY_BUTTON_RIGHT_SHOULDER])
	_action("toggle_assist", [KEY_F1], [JOY_BUTTON_BACK])
	_action("toggle_slowmo", [KEY_F2], [])
	_action("toggle_zoom", [KEY_F3], [])
	_action("menu", [KEY_ESCAPE], [JOY_BUTTON_START])
	_action("trainer", [KEY_T], [JOY_BUTTON_Y])


func _action(name: String, keys: Array, buttons: Array, axes: Array = []) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, 0.25)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(name, ev)
	for b in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		InputMap.action_add_event(name, jb)
	for a in axes:
		var jm := InputEventJoypadMotion.new()
		jm.axis = a[0]
		jm.axis_value = a[1]
		InputMap.action_add_event(name, jm)


## Anzeigetafel, 3D-Schiedsrichter und Schuhquietschen beim Absprung und Hechten.
func _update_hall() -> void:
	var m = match_node
	var tn: Array = Teams.playing()
	arena.ball_pos = m.ball.position
	arena.set_scoreboard("%s  %d : %d  %s\nSATZ %d   ·   SÄTZE %d : %d" % [tn[0].board_name(), m.score[0], m.score[1], tn[1].board_name(),
		maxi(m.set_no, 1), m.sets_won[0], m.sets_won[1]])
	var sig: String = hud.ref_pose_name()
	var team: int = m.serving_team
	if sig == "serve_0":
		team = 0
	elif sig == "serve_1":
		team = 1
	arena.referee_signal(sig, m.side_of(team))
	for t in 2:
		for pl in m.players[t]:
			var was: bool = _air.get(pl, false)
			var now_air: bool = pl.airborne or pl.dive_timer > 0.0
			if now_air != was and m.phase == m.Phase.RALLY and randf() < 0.55:
				sfx.play("squeak", randf_range(0.3, 0.8))
			_air[pl] = now_air
