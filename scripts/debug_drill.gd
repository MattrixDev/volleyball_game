class_name DebugDrill
extends Node
## Debug-Modus: eine Uebung laeuft im echten Spiel (gleiche Physik, KI und Animationen) und
## wiederholt sich ohne Punkte. Du spielst nur, was die Uebung vorgibt (z.B. die Annahme),
## den Rest macht die KI fuer dein Team. Oben rechts steht, wie gut es lief.
## Das Match fragt ueber match_node.drill an ein paar Stellen nach (human_does, step, ...).

signal menu_wanted

var match_node
var id := "annahme"
var _def: Dictionary
var _reps := 0
var _q_count := [0, 0, 0, 0]  # Perfekt, Gut, Schwach, Daneben
var _last := ""
var _last_reason := ""
var _reset_at := -1.0
var _inject_at := -1.0
var _inject_team := 0
var _inject_from := Vector3.ZERO
var _rot_done := false
var _serve_flip := 0
var _blocks := [0, 0]  # Angriffe des Gegners, davon Blockpunkte
var _block_touch := 0
# Freies Laufen
var _free := false
var _cur := 0
var _contact_off_at := -1.0
var _slow := false
var _was_air := false
# Anzeige
var _layer: CanvasLayer
var _title: Label
var _stats: Label
var _help: Label


func _ready() -> void:
	_def = DebugMode.drill(id)
	_free = _def.start == "free"
	_setup_input()
	_build_panel()
	var m = match_node
	m.drill = self
	m.touch_result.connect(_on_touch)
	m.contact.connect(_on_contact)
	if _free:
		_start_free()
	else:
		m.start_game()


func _exit_tree() -> void:
	if _stats and OS.get_cmdline_user_args().has("--botplay"):
		print("UEBUNG %s: %s" % [id, _stats.text.replace("\n", " | ")])  # Test
	var m = match_node
	if m == null or not is_instance_valid(m):
		return
	if m.drill == self:
		m.drill = null
		Engine.time_scale = 1.0
		m.ball.visible = true
		m.ball_shadow.visible = true


func human_does(kind: String) -> bool:
	return (_def.does as Array).has(kind)


## Kein Block fuer dein Team beim Abwehren (wenn so eingestellt).
func no_block(def_team: int) -> bool:
	return id == "abwehr" and def_team == match_node.human_team and not DebugMode.opts.block


## Zuspiel der KI: Richtung und Tempo aus den Einstellungen.
func ai_choice(o) -> String:
	if o.kind != "set" or id in ["ballwechsel"]:
		return "auto"
	var tempo: String = DebugMode.opts.tempo
	if tempo == "fast" and DebugMode.opts.lane == "mid":
		tempo = "quick"
	return "%s|%s" % [DebugMode.opts.lane, tempo]


# ------------------------------------------------------------------ Ablauf

## Vor jeder Wiederholung (aus start_rally): wer aufschlaegt, Rotation.
func before_rally() -> void:
	var m = match_node
	var h: int = m.human_team
	if not _rot_done:
		_rot_done = true
		for _i in int(DebugMode.opts.rot):
			m.rosters[h].rotate()
		m._sync_slots(h)
	match _def.start:
		"serve_opp", "pass_own":
			m.serving_team = 1 - h
		"serve_own", "pass_opp":
			m.serving_team = h
		"serve_alt":
			m.serving_team = h if _serve_flip % 2 == 0 else 1 - h
			_serve_flip += 1


## Nach dem Aufbau (aus start_rally): alle stehen sofort auf ihren Plaetzen, die KI schlaegt so auf
## wie eingestellt, bei "Zuwurf" fliegt gleich der Ball zum Zuspieler.
func after_rally_setup() -> void:
	var m = match_node
	for t in 2:
		for pl in m.players[t]:
			pl.position = pl.target
			pl.reset_state()
	m.reset_physics_interpolation()
	m.pause_until = m.clock + 0.5
	if not m.human_serves():
		_ai_serve_style()
	if _def.start in ["pass_own", "pass_opp"] and DebugMode.opts.start == "toss":
		_inject_team = m.human_team if _def.start == "pass_own" else 1 - m.human_team
		_prepare_inject()


func _ai_serve_style() -> void:
	var m = match_node
	var s: String = DebugMode.opts.serve
	if s == "auto":
		return
	m.serve_kind = 1 if s.begins_with("jump") else 0
	match s:
		"float", "jump_float":
			m.serve_contact = Vector2(m.rng.randf_range(-0.2, 0.2), 0.0)
		"topspin", "jump_topspin":
			m.serve_contact = Vector2(m.rng.randf_range(-0.2, 0.2), 0.7)
		"short":
			m.serve_contact = Vector2(0.0, -0.7)


## Zuwurf: ein Spieler steht mit dem Ball an der Annahmestelle, kurz danach fliegt der Ball
## wie eine gute Annahme zum Zuspieler.
func _prepare_inject() -> void:
	var m = match_node
	var t := _inject_team
	_inject_from = m.court_pos(t, Vector2(m.rng.randf_range(5.5, 7.0), m.rng.randf_range(-2.2, 2.2)))
	_inject_from.y = m.H_PASS
	m.phase = m.Phase.TIMEOUT  # Wartezeit: niemand laeuft los, kein Anpfiff
	m.pause_until = m.clock + 99.0
	_inject_at = m.clock + 0.7
	var recv = _receiver(t)
	if recv:
		recv.position = Vector3(_inject_from.x, 0.0, _inject_from.z) + Vector3(m.side_of(t) * 0.45, 0.0, 0.0)
		recv.target = recv.position
		recv.prep = "bump"
	m.ball.position = _inject_from
	m.ball_vel = Vector3.ZERO


func _receiver(t: int):
	var m = match_node
	var best = null
	var bd := INF
	for pl in m.players[t]:
		if pl.role == "S":
			continue
		var d: float = Vector2(pl.position.x - _inject_from.x, pl.position.z - _inject_from.z).length()
		if d < bd:
			bd = d
			best = pl
	return best


func _inject() -> void:
	var m = match_node
	var t := _inject_team
	var recv = _receiver(t)
	var target: Vector3 = m.court_pos(t, m.SETTER_TARGET)
	target.y = m.H_SET
	m.ball.position = _inject_from
	m.ball_g = m.G
	m.ball_vel = Ballistics.launch_with_time(_inject_from, target, 1.35)
	m.flutter = 0.0
	m.possession = t
	m.touches = 1
	m.last_touch_team = t
	m.last_toucher = recv
	m.last_action = "pass"
	m.pass_quality = m.Q.PERFECT
	m.serve_done = true
	m.whistle_done = true
	m.phase = m.Phase.RALLY
	if recv:
		recv.prep = ""
	m._fx("bump", _inject_from, 0.5)
	m.plan_next()


## Aus dem Match (statt Punkt): Ballwechsel vorbei, gleich die naechste Wiederholung.
func rally_ended(winner: int, reason: String) -> void:
	var m = match_node
	m.opp = null
	m.blockers = [[], []]
	m._hitter = [null, null]
	m.charging = false
	m.flutter = 0.0
	m.replay_pending = false
	m.side_change_pending = false
	_reset_at = -1.0
	_inject_at = -1.0
	if reason != "":
		_last_reason = reason
		if id == "block" and reason == "Block-Punkt!" and winner == m.human_team:
			_blocks[1] += 1
		if m.hud:
			m.hud.whistle(false)
	m._rally_end = m.clock
	m.phase = m.Phase.POINT_PAUSE
	m.pause_until = m.clock + (1.1 if reason != "" else 0.4)
	_reps += 1
	_update_panel()


## Jeden Physik-Takt vor dem Match. true = das Match macht in diesem Takt nichts selbst.
func step(delta: float) -> bool:
	var m = match_node
	if _free:
		_free_step(delta)
		return true
	if _inject_at >= 0.0:
		if m.clock >= _inject_at:
			_inject_at = -1.0
			_inject()
			return false
		m.ball.position = _inject_from
		m._update_players(delta)
		m._update_time_and_camera(delta / maxf(Engine.time_scale, 0.01))
		m._update_visuals()
		if m.hud:
			m.hud.update_view(m)
		return true
	if _reset_at >= 0.0 and m.clock >= _reset_at:
		_reset_at = -1.0
		if m.phase == m.Phase.RALLY or m.phase == m.Phase.TOSS or m.phase == m.Phase.PRE_SERVE:
			rally_ended(-1, "")
	return false


## Ergebnis jeder Ballberuehrung: zaehlen und (je nach Einstellung) bald neu starten.
func _on_touch(kind: String, team: int, human: bool, q: int, e: float, speed: float, speed_in: float) -> void:
	var m = match_node
	if human:
		_q_count[q] += 1
		var names := {"pass": "Annahme", "dig": "Abwehr", "set": "Zuspiel", "attack": "Angriff", "serve": "Aufschlag", "free": "Freier Ball"}
		var timing := ""
		if q != m.Q.MISS or absf(e) < 0.9:
			timing = "  ·  %d ms %s" % [roundi(absf(e) * 1000.0), "zu früh" if e < 0.0 else "zu spät"] if absf(e) >= 0.005 else "  ·  genau im Moment"
		# Annahme, Abwehr, Zuspiel: wie schnell der Ball kam. Angriff, Aufschlag: wie schnell er geht.
		var v := speed if kind in ["attack", "serve"] else speed_in
		var spd := "  ·  Ball %d km/h" % roundi(v * 3.6) if v > 0.5 else ""
		_last = "%s: %s%s%s" % [names.get(kind, kind), m.Q_TEXT[q], timing, spd]
		if DebugMode.opts.after == "reset" and id != "ballwechsel":
			var wait := 1.6
			match kind:
				"serve":
					wait = 2.4
				"attack":
					wait = 1.8
				"set":
					wait = 1.9
			_reset_at = m.clock + wait
	elif id == "block" and kind == "attack" and team != m.human_team:
		_blocks[0] += 1
		if DebugMode.opts.after == "reset":
			_reset_at = m.clock + 1.8
	_update_panel()


func _on_contact(kind: String, _pos: Vector3, _strength: float) -> void:
	if id == "block" and kind == "block":
		_block_touch += 1
		_update_panel()


# ------------------------------------------------------------------ Freies Laufen

func _start_free() -> void:
	var m = match_node
	m._abort_replay()
	m.attract = false
	m.human_team = 0
	m.opp = null
	m.blockers = [[], []]
	m.phase = m.Phase.INTRO
	m.ball.visible = false
	m.ball_shadow.visible = false
	if m.hud:
		m.hud.clear_message()
	for t in 2:
		for pl in m.players[t]:
			pl.reset_state()
			pl.target = pl.position
	_cur = 0
	_update_panel()


func _all_players() -> Array:
	return match_node.players[0] + match_node.players[1]


func _free_step(delta: float) -> void:
	var m = match_node
	m.phase = m.Phase.INTRO
	var all := _all_players()
	var inp: Dictionary = _demo_input() if m.autopress else m._read_input()
	if inp.kind_prev or Input.is_action_just_pressed("dbg_prev"):
		_cur = posmod(_cur - 1, all.size())
		_update_panel()
	if inp.kind_next or Input.is_action_just_pressed("dbg_next"):
		_cur = posmod(_cur + 1, all.size())
		_update_panel()
	if Input.is_action_just_pressed("dbg_slow"):
		_slow = not _slow
		_update_panel()
	var pl = all[_cur]
	var fwd := Vector3(-pl.side, 0.0, 0.0)
	for p in all:
		p.now = m.clock
		p.alert = true
		p.urgent = p == pl
		p.manual_dir = Vector3.ZERO
		p.run_speed = 6.0 * m._speed_k(p)
		p.look_target = p.position + Vector3(-p.side * 4.0, 1.0, 0.0)
		if p != pl:
			p.prep = ""
	pl.manual_dir = m._stick_dir(inp.mv)
	pl.prep = "bump" if inp.bump_held else ("over" if inp.over_held else "")
	if inp.bump_up or inp.over_up:
		# Ballkontakt ohne Ball: Annahme (Baggern) oder Zuspiel (Pritschen) vor dem Koerper.
		var over: bool = inp.over_up
		pl.anim_kind = "set" if over else "pass"
		pl.anim_tech = "over" if over else "bump"
		pl.anim_t = m.clock + 0.12
		pl.contact_pt = pl.position + fwd * (0.25 if over else 0.55) + Vector3(0.0, 2.15 if over else 0.8, 0.0)
		pl.contact_aim = pl.position + fwd * 3.0 + Vector3(0.0, 0.0, 1.5)
		pl.contact_on = true
		_contact_off_at = m.clock + 0.8
	if inp.hit_down and not pl.airborne:
		# Angriffssprung: Treffpunkt im hoechsten Punkt vor dem Schlagarm.
		pl.anim_kind = "attack"
		pl.anim_tech = "bump"
		pl.block_pose = false
		pl.jump()
		var apex: float = pl.jump_v0 * pl.jump_v0 / (2.0 * m.G)
		pl.anim_t = m.clock + pl.jump_v0 / m.G
		pl.contact_pt = pl.position + fwd * 0.45 + Vector3(0.0, apex + 2.55 + pl.reach_add, 0.25)
		pl.contact_aim = pl.position + fwd * 7.0
		pl.contact_on = true
		_contact_off_at = pl.anim_t + 0.7
	if inp.fast and not pl.airborne:
		# Blocksprung am Netz.
		pl.anim_kind = ""
		pl.block_pose = true
		pl.jump()
	if Input.is_action_just_pressed("dbg_dive") or all_dive:
		all_dive = false
		pl.dive()
	if Input.is_action_just_pressed("dbg_cheer"):
		pl.celebrate_until = m.clock + 1.6
	if _was_air and not pl.airborne:
		pl.block_pose = false
	_was_air = pl.airborne
	if _contact_off_at >= 0.0 and m.clock >= _contact_off_at:
		_contact_off_at = -1.0
		pl.contact_on = false
		pl.anim_kind = ""
	for p in all:
		p.tick(delta)
		p.set_controlled(p == pl)
	VPlayer.separate(all, delta)
	# Ball unsichtbar beim Spieler: die Kamera folgt ihm.
	m.ball.position = pl.position + Vector3(0.0, 1.0, 0.0)
	# Nahe Kamera am Spieler (F3 schaltet auf die Uebersicht).
	m.cam_mode = "free" if m.zoom_on else ""
	m.cam_subject = pl if m.zoom_on else null
	Engine.time_scale = 0.3 if _slow else 1.0
	if m.hud:
		m.hud.update_view(m)


## Testhilfe (--botplay): spielt im freien Laufen nacheinander alle Bewegungen vor.
var _demo_t := 0.0
func _demo_input() -> Dictionary:
	var m = match_node
	var d: Dictionary = m._empty_input()
	var t0 := _demo_t
	_demo_t += get_physics_process_delta_time()
	var at := func(t: float) -> bool: return t0 < t and _demo_t >= t
	var ph := fmod(_demo_t, 12.0)
	if ph < 1.5:
		d.mv = Vector2(1, 0)
	elif ph < 2.5:
		d.mv = Vector2(0, -1)
	d.bump_held = ph > 3.0 and ph < 3.8
	d.bump_up = at.call(3.8) or at.call(15.8)
	d.over_held = ph > 5.0 and ph < 5.6
	d.over_up = at.call(5.6) or at.call(17.6)
	d.hit_down = at.call(7.0) or at.call(19.0)
	d.fast = at.call(9.0) or at.call(21.0)
	if at.call(10.5) or at.call(22.5):
		all_dive = true
	return d
var all_dive := false


# ------------------------------------------------------------------ Anzeige

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("trainer") and not get_tree().paused:
		menu_wanted.emit()


func _setup_input() -> void:
	var defs := {
		"dbg_dive": [[KEY_C], [JOY_BUTTON_DPAD_DOWN]],
		"dbg_cheer": [[KEY_X], [JOY_BUTTON_DPAD_UP]],
		"dbg_slow": [[KEY_Z], [JOY_BUTTON_DPAD_LEFT]],
		"dbg_next": [[KEY_TAB], [JOY_BUTTON_DPAD_RIGHT]],
		"dbg_prev": [[], []],
	}
	for name in defs:
		if InputMap.has_action(name):
			continue
		InputMap.add_action(name, 0.5)
		for k in defs[name][0]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(name, ev)
		for b in defs[name][1]:
			var jb := InputEventJoypadButton.new()
			jb.button_index = b
			InputMap.action_add_event(name, jb)


func _build_panel() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)
	var p := PanelContainer.new()
	var sb := UiTheme.box(Color(1, 1, 1, 0.94), 16)
	sb.set_content_margin_all(16)
	p.add_theme_stylebox_override("panel", sb)
	p.anchor_left = 1.0
	p.anchor_right = 1.0
	p.offset_left = -470
	p.offset_right = -20
	p.offset_top = 96
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var cap := _lab("DEBUG · ÜBUNG", 12, UiTheme.INK_MUTED, UiTheme.font_semibold)
	v.add_child(cap)
	_title = _lab(_def.title, 22, UiTheme.INK, UiTheme.font_display)
	v.add_child(_title)
	_stats = _lab("", 15, UiTheme.INK, UiTheme.font_medium)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_stats)
	_help = _lab("", 13, UiTheme.INK_MUTED, UiTheme.font_medium)
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_help)
	_update_panel()


func _lab(t: String, size: int, color: Color, font: Font) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _update_panel() -> void:
	if _stats == null:
		return
	var lines := []
	if _free:
		var pl = _all_players()[_cur]
		var pd = match_node.pdata(pl)
		var who: String = pd.full_name() if pd != null else "Spieler"
		lines.append("Du steuerst: %s (%s, Nr. %d, %s)" % [who, TeamRoster.ROLE_TEXT.get(pl.role, pl.role), pl.number,
			Teams.playing()[pl.team].name])
		lines.append("Zeitlupe: " + ("an" if _slow else "aus"))
		_help.text = "Stick / WASD laufen · A / Leertaste halten = Baggern, loslassen = Ballkontakt · X / Q = Pritschen · R2 / E = Angriffssprung · B / R = Blocksprung · Steuerkreuz unten / C = Hechtsprung · oben / X = Jubel · links / Z = Zeitlupe · F3 = Kamera nah / weit · rechts / Tab oder LB / RB = anderer Spieler · Y / T = Debug-Menü"
	else:
		lines.append("Wiederholungen: %d" % _reps)
		if id == "block":
			lines.append("Angriffe: %d  ·  Blockpunkte: %d  ·  Block berührt: %d" % [_blocks[0], _blocks[1], _block_touch])
		var total: int = _q_count[0] + _q_count[1] + _q_count[2] + _q_count[3]
		if total > 0:
			lines.append("Perfekt %d  ·  Gut %d  ·  Schwach %d  ·  Daneben %d" % _q_count)
		if _last != "":
			lines.append("Zuletzt: " + _last)
		if _last_reason != "":
			lines.append("Ende: " + _last_reason)
		var o := DebugMode.opts
		var set_info := ""
		if id in ["zuspiel", "angriff", "block", "abwehr"]:
			set_info = "  ·  Zuspiel %s, %s" % [DebugMode.option_text("lane"), DebugMode.option_text("tempo")]
		_help.text = "Rotation %d%s  ·  Y / T: Debug-Menü  ·  Start / Esc: Pause" % [int(o.rot) + 1, set_info]
	_stats.text = "\n".join(lines)
