extends Node3D
## Ein Satz Hallenvolleyball, 6 gegen 6. Steuert Ball, Spielablauf, KI und Eingaben.
##
## Koordinaten: Netz bei x = 0, Team 0 (Heim, Mensch) spielt auf x < 0, Team 1 auf x > 0.
## "Lokal" heisst aus Sicht eines Teams: x = Abstand zum Netz, y = seitlich (+ = rechts).

signal big_hit(strength: float)

const G := 9.81
const R := Ballistics.BALL_R
const NET_H := 2.43  # Maenner
const NET_BOTTOM := 1.43
const HALF_L := 9.0
const HALF_W := 4.5
const H_PASS := 0.85
const H_SET := 2.35
const H_ATTACK := 3.25
const JUMP_RISE := 0.404
const SERVE_IDEAL := 0.62
const SET_POINTS := 25

const TEAM_NAMES := ["SV Nordhafen", "TSV Eichenberg"]
const TEAM_COLORS := [Color(0.16, 0.38, 0.86), Color(0.85, 0.2, 0.18)]
const LIBERO_COLORS := [Color(0.98, 0.82, 0.15), Color(0.95, 0.95, 0.95)]
const ROLES := ["S", "OH1", "MB", "OP", "OH2", "L"]
const ROLE_TAG := {"S": "Z", "OH1": "A", "MB": "M", "OP": "D", "OH2": "A", "L": "L"}
const NUMBERS := [[7, 10, 14, 3, 5, 1], [9, 4, 12, 18, 11, 2]]
const FRONT_ROW := ["OH1", "MB", "OP"]

## Grundpositionen je Spielsituation (lokal: Abstand zum Netz, seitlich).
const LAYOUT := {
	"serve": {"S": Vector2(10.0, 2.5), "OH1": Vector2(2.0, -3.0), "MB": Vector2(2.0, 0.0), "OP": Vector2(2.0, 3.0), "OH2": Vector2(6.5, -3.0), "L": Vector2(7.0, 0.0)},
	"receive": {"S": Vector2(2.5, 2.2), "OH1": Vector2(5.0, -2.8), "MB": Vector2(1.5, -0.6), "OP": Vector2(1.5, 3.4), "OH2": Vector2(5.0, 2.8), "L": Vector2(5.8, 0.0)},
	"defense": {"S": Vector2(6.5, 3.2), "OH1": Vector2(0.6, -3.0), "MB": Vector2(0.6, 0.0), "OP": Vector2(0.6, 3.0), "OH2": Vector2(6.5, -3.2), "L": Vector2(7.8, 0.0)},
	"build": {"S": Vector2(0.9, 1.0), "OH1": Vector2(3.5, -3.8), "MB": Vector2(2.6, 0.2), "OP": Vector2(3.5, 3.8), "OH2": Vector2(5.5, -2.0), "L": Vector2(5.5, 1.5)},
	"cover": {"S": Vector2(1.6, 1.0), "OH1": Vector2(2.5, -3.0), "MB": Vector2(2.2, 0.0), "OP": Vector2(2.5, 3.0), "OH2": Vector2(4.2, -1.5), "L": Vector2(4.2, 1.5)},
}
const SETTER_TARGET := Vector2(1.2, 1.0)

enum Phase { INTRO, PRE_SERVE, TOSS, RALLY, POINT_PAUSE, SET_OVER }
enum Q { PERFECT, GOOD, WEAK, MISS }
const Q_TEXT := ["PERFEKT!", "Gut", "Schwach", "Daneben"]
const Q_COLOR := [Color(1.0, 0.85, 0.1), Color(0.55, 1.0, 0.55), Color(1.0, 0.6, 0.3), Color(1.0, 0.3, 0.3)]


## Die naechste Ballberuehrung, die ansteht.
class Opp:
	var team := 0
	var player: VPlayer = null
	var kind := ""  # pass, dig, set, attack, free
	var t := 0.0  # idealer Zeitpunkt der Beruehrung
	var point := Vector3.ZERO  # Ballposition in diesem Moment
	var done := false
	var human := false
	var ai_e := 0.0
	var pending := false  # frueh gedrueckt: Beruehrung passiert im idealen Moment
	var press_e := 0.0
	var press_choice := ""


var phase := Phase.INTRO
var clock := 0.0
var players: Array = [[], []]
var ball: MeshInstance3D
var ball_shadow: MeshInstance3D
var ball_vel := Vector3.ZERO
var score := [0, 0]
var serving_team := 0
var possession := 0
var touches := 0
var last_toucher: VPlayer = null
var last_touch_team := -1
var last_action := ""
var net_touched := false
var opp: Opp = null
var blocker: Array = [null, null]
var block_jump_t := [0.0, 0.0]
var pass_quality := Q.GOOD
var pause_until := 0.0
var toss_time := -1.0
var serve_done := false
var ai_serve_e := 0.0
var serve_aim := Vector2(5.5, 0.0)
var attack_aim := Vector2(6.5, 0.0)
var assist := true
var human_team := 0
var autoplay := false
var autoplay_rallies := 200
var trace := false
var autopress := false  # Test: drueckt fuer den Menschen automatisch
var hud = null
var rng := RandomNumberGenerator.new()

var _ring_target: MeshInstance3D
var _ring_timer: MeshInstance3D
var _ring_timer_mat: StandardMaterial3D
var _aim_marker: MeshInstance3D

# Statistik fuer den automatischen Test
var stats := {}
var rally_count := 0
var touch_total := 0


func _ready() -> void:
	rng.randomize()
	for t in 2:
		_spawn_team(t)
	_make_ball()
	_make_markers()
	for a in OS.get_cmdline_user_args():
		if a == "--autoplay":
			autoplay = true
		elif a.begins_with("--rallies="):
			autoplay_rallies = int(a.get_slice("=", 1))
		elif a == "--demo":
			human_team = -1
		elif a == "--autopress":
			autopress = true
			autoplay = true
		elif a == "--trace":
			trace = true
		elif a.begins_with("--seed="):
			rng.seed = int(a.get_slice("=", 1))
	if autoplay:
		human_team = 0 if autopress else -1
		new_match()
	elif human_team < 0:
		new_match()
	elif hud:
		hud.show_intro()


# ---------------------------------------------------------------- Aufbau

func _spawn_team(team: int) -> void:
	for i in ROLES.size():
		var role: String = ROLES[i]
		var pl := VPlayer.new()
		var col: Color = LIBERO_COLORS[team] if role == "L" else TEAM_COLORS[team]
		pl.setup(team, role, ROLE_TAG[role], NUMBERS[team][i], col)
		add_child(pl)
		players[team].append(pl)
		var p := court_pos(team, LAYOUT["receive"][role])
		pl.position = p
		pl.target = p


func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _make_ball() -> void:
	ball = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.14  # etwas groesser gezeichnet, damit man ihn gut sieht
	s.height = 0.28
	ball.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.92, 0.35)
	m.emission_enabled = true
	m.emission = Color(0.35, 0.3, 0.05)
	ball.material_override = m
	add_child(ball)

	ball_shadow = MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.16
	c.bottom_radius = 0.16
	c.height = 0.004
	ball_shadow.mesh = c
	ball_shadow.material_override = _unshaded(Color(0, 0, 0, 0.45))
	add_child(ball_shadow)


func _torus(inner: float, outer: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	mi.mesh = t
	mi.material_override = _unshaded(c)
	mi.visible = false
	add_child(mi)
	return mi


func _make_markers() -> void:
	_ring_target = _torus(0.42, 0.5, Color(1, 1, 1, 0.9))
	_ring_timer = _torus(0.44, 0.52, Color(1.0, 0.85, 0.1))
	_ring_timer_mat = _ring_timer.material_override
	_aim_marker = _torus(0.25, 0.4, Color(1.0, 0.3, 0.25, 0.9))


# ---------------------------------------------------------------- Hilfen

func side_of(team: int) -> float:
	return -1.0 if team == 0 else 1.0


func court_pos(team: int, v: Vector2) -> Vector3:
	var s := side_of(team)
	return Vector3(s * v.x, 0.0, -s * v.y)


func team_local(team: int, p: Vector3) -> Vector2:
	var s := side_of(team)
	return Vector2(s * p.x, -s * p.z)


func player_by_role(team: int, role: String) -> VPlayer:
	for pl in players[team]:
		if pl.role == role:
			return pl
	return null


func server() -> VPlayer:
	return player_by_role(serving_team, "S")


func flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func windows(kind: String) -> Array:
	if kind == "dig":
		return [0.06, 0.12, 0.2]
	if kind == "serve":
		return [0.05, 0.1, 0.17]
	return [0.045, 0.09, 0.15]


## Timing-Fehler ausserhalb des Perfekt-Fensters; nur der verschiebt den Ball.
func excess(e: float, kind: String) -> float:
	var w0: float = windows(kind)[0]
	return signf(e) * maxf(0.0, absf(e) - w0)


func classify(e: float, kind: String) -> int:
	var w := windows(kind)
	var a := absf(e)
	if a <= w[0]:
		return Q.PERFECT
	if a <= w[1]:
		return Q.GOOD
	if a <= w[2]:
		return Q.WEAK
	return Q.MISS


## Zufaelliger Timing-Fehler fuer die KI.
func ai_e(kind: String) -> float:
	var p := [0.4, 0.85, 0.98]
	match kind:
		"serve":
			p = [0.3, 0.78, 0.96]
		"dig":
			p = [0.25, 0.6, 0.85]
		"attack":
			p = [0.4, 0.85, 0.97]
		"set":
			p = [0.45, 0.9, 0.99]
	var w := windows(kind)
	var r := rng.randf()
	var lo := 0.0
	var hi: float = w[0]
	if r >= p[2]:
		lo = w[2] + 0.01
		hi = w[2] + 0.1
	elif r >= p[1]:
		lo = w[1]
		hi = w[2]
	elif r >= p[0]:
		lo = w[0]
		hi = w[1]
	var mag := rng.randf_range(lo, hi)
	return mag if rng.randf() < 0.5 else -mag


func popup(pl: VPlayer, text: String, color: Color) -> void:
	if autoplay:
		return
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 72
	l.outline_size = 16
	l.pixel_size = 0.006
	l.modulate = color
	add_child(l)
	l.position = pl.position + Vector3(0, 2.8, 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 0.8, 0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


# ---------------------------------------------------------------- Ablauf

func new_match() -> void:
	score = [0, 0]
	serving_team = 0
	start_rally()


func start_rally() -> void:
	phase = Phase.PRE_SERVE
	opp = null
	blocker = [null, null]
	touches = 0
	possession = serving_team
	last_toucher = null
	last_touch_team = serving_team
	last_action = ""
	net_touched = false
	serve_done = false
	toss_time = -1.0
	for t in 2:
		var form := "serve" if t == serving_team else "receive"
		for pl in players[t]:
			var p := court_pos(t, LAYOUT[form][pl.role])
			pl.position = p
			pl.target = p
			pl.reset_state()
	ball_vel = Vector3.ZERO
	_hold_ball_at_server()
	pause_until = clock + (0.15 if autoplay else 1.0)
	if serving_team == human_team:
		serve_aim = Vector2(5.5, 0.0)
	else:
		serve_aim = Vector2(rng.randf_range(4.0, 7.5), rng.randf_range(-3.2, 3.2))
	if hud:
		hud.clear_message()


func _hold_ball_at_server() -> void:
	var s := server()
	ball.position = s.position + Vector3(-side_of(serving_team) * 0.4, 1.3, 0.0)


func _physics_process(delta: float) -> void:
	clock += delta
	var mv := Vector2.ZERO
	var act := false
	if human_team >= 0:
		mv = Input.get_vector("move_left", "move_right", "move_down", "move_up")
		act = Input.is_action_just_pressed("action")
		if Input.is_action_just_pressed("toggle_assist"):
			assist = not assist
		if autopress:
			act = _autopress_due()

	match phase:
		Phase.INTRO:
			if act:
				new_match()
		Phase.PRE_SERVE:
			_hold_ball_at_server()
			if serving_team == human_team:
				serve_aim = _nudge_aim(serve_aim, mv, delta)
				if act and clock >= pause_until:
					_do_toss()
			elif clock >= pause_until:
				_do_toss()
		Phase.TOSS:
			if serving_team == human_team:
				serve_aim = _nudge_aim(serve_aim, mv, delta)
				if act and not serve_done:
					_serve_hit(clock - (toss_time + SERVE_IDEAL))
			elif not serve_done and clock >= toss_time + SERVE_IDEAL + ai_serve_e:
				_serve_hit(ai_serve_e)
			_step_ball(delta)
		Phase.RALLY:
			_rally_input(mv, act)
			_ai_actions()
			_step_ball(delta)
		Phase.POINT_PAUSE:
			if clock >= pause_until:
				start_rally()
		Phase.SET_OVER:
			if autoplay:
				if rally_count >= autoplay_rallies:
					_print_stats()
					get_tree().quit()
				else:
					new_match()
			elif act or (human_team < 0 and clock >= pause_until + 3.0):
				new_match()

	_update_players(delta)
	_update_visuals()
	if hud:
		hud.update_view(self)


## Nur fuer Tests: drueckt mit etwas Zufall nahe am idealen Moment.
var _auto_t := -1.0


func _autopress_due() -> bool:
	var ideal := -1.0
	match phase:
		Phase.PRE_SERVE:
			ideal = pause_until
		Phase.TOSS:
			ideal = toss_time + SERVE_IDEAL if not serve_done else -1.0
		Phase.RALLY:
			if opp != null and not opp.done and not opp.pending and opp.team == human_team:
				ideal = opp.t
			elif human_player() != null and opp != null:
				ideal = opp.t - JUMP_RISE
		Phase.SET_OVER, Phase.INTRO:
			return true
	if ideal < 0.0:
		_auto_t = -1.0
		return false
	if _auto_t < 0.0:
		_auto_t = ideal + rng.randf_range(-0.08, 0.08)
	if clock >= _auto_t:
		_auto_t = -1.0
		return true
	return false


func _nudge_aim(aim: Vector2, mv: Vector2, delta: float) -> Vector2:
	aim += Vector2(mv.y, mv.x) * 5.0 * delta
	return Vector2(clampf(aim.x, 1.0, 8.8), clampf(aim.y, -4.3, 4.3))


func _do_toss() -> void:
	toss_time = clock
	phase = Phase.TOSS
	ball_vel = Vector3(0.0, 5.0, 0.0)
	last_action = "toss"
	last_touch_team = serving_team
	ai_serve_e = ai_e("serve")


func _serve_hit(e: float) -> void:
	serve_done = true
	var srv := server()
	var q := classify(e, "serve")
	if q == Q.MISS:
		popup(srv, "Zu früh" if e < 0.0 else "Zu spät", Q_COLOR[Q.MISS])
		return
	var d := serve_aim.x
	var l := serve_aim.y
	var clear := NET_H + 0.45
	var umax := 22.0
	if q == Q.GOOD:
		clear += 0.3
		umax = 18.0
		d += rng.randf_range(-0.6, 0.6)
		l += rng.randf_range(-0.6, 0.6)
	elif q == Q.WEAK:
		clear += 1.1
		umax = 13.0
		d += rng.randf_range(-1.2, 1.2)
		l += rng.randf_range(-1.2, 1.2)
	# Zu frueh getroffen: Ball fliegt zu lang. Zu spaet: Ball fliegt zu flach (Netz).
	var x := excess(e, "serve")
	if x < 0.0:
		d += -x * 30.0
	else:
		clear -= x * 9.0
	var target := court_pos(serving_team, Vector2(-d, l))
	target.y = R
	ball_vel = Ballistics.launch_over_net(ball.position, target, clear, 8.0, umax)
	if trace:
		print("AUFSCHLAG T%d q=%s e=%.3f from=%s target=%s vel=%s" % [serving_team, Q_TEXT[q], e, ball.position, target, ball_vel])
	last_action = "serve"
	last_toucher = srv
	last_touch_team = serving_team
	possession = serving_team
	touches = 1
	phase = Phase.RALLY
	popup(srv, Q_TEXT[q], Q_COLOR[q])
	plan_next()


## Bestimmt, wer den Ball als Naechstes spielt und wann. Zuerst darf das Team ran,
## auf dessen Seite der Ball gerade ist; fliegt er hinueber, das andere.
func plan_next() -> void:
	opp = null
	var cur := 0 if ball.position.x < 0.0 else 1
	# Den eigenen Aufschlag darf das aufschlagende Team nicht mehr spielen.
	var serve_ball := last_action == "serve" and cur == last_touch_team
	if not serve_ball and _try_team(cur):
		return
	_try_team(1 - cur)


func _try_team(team: int) -> bool:
	var idx := touches if team == possession else 0
	if idx >= 3:
		return false
	var apex := Ballistics.apex_height(ball.position, ball_vel)
	var kind := "pass"
	var h := H_PASS
	if idx == 0:
		if (last_action == "attack" or last_action == "block_touch") and ball_vel.length() > 12.0:
			kind = "dig"
	elif idx == 1:
		kind = "set"
		h = H_SET if apex >= H_SET + 0.3 else H_PASS + 0.1
	elif apex >= H_ATTACK + 0.05:
		kind = "attack"
		h = H_ATTACK
	else:
		kind = "free"

	var tc := Ballistics.time_to_height(ball.position, ball_vel, h)
	if tc < 0.0:
		return false
	var p := Ballistics.pos_at(ball.position, ball_vel, tc)
	if kind == "attack" and (signf(p.x) != side_of(team) or absf(p.x) > 6.0 or absf(p.x) < 0.2):
		kind = "free"
		h = H_PASS
		tc = Ballistics.time_to_height(ball.position, ball_vel, h)
		p = Ballistics.pos_at(ball.position, ball_vel, tc)
	if signf(p.x) != side_of(team) or absf(p.x) < 0.2:
		return false
	if absf(p.x) > HALF_L + 4.0 or absf(p.z) > HALF_W + 3.5:
		return false

	if team != last_touch_team and team != human_team:
		# Die KI laesst Aus-Baelle fallen, verschaetzt sich aber manchmal knapp an der Linie.
		var land_t := Ballistics.time_to_height(ball.position, ball_vel, R)
		var land := Ballistics.pos_at(ball.position, ball_vel, land_t)
		var margin := maxf(absf(land.x) - HALF_L, absf(land.z) - HALF_W)
		if margin > R and (margin > 0.35 or rng.randf() < 0.75):
			return false

	var excluded: VPlayer = last_toucher if last_touch_team == team else null
	var pl: VPlayer = null
	if kind == "attack":
		pl = _chosen_hitter(team)
		if pl == excluded:
			pl = null
	elif kind == "set":
		var s := player_by_role(team, "S")
		if s != excluded and flat_dist(s.position, p) <= s.run_speed * tc + 0.8:
			pl = s
	if pl == null:
		pl = _nearest(team, p, excluded, kind == "attack")
	if pl == null:
		return false

	var o := Opp.new()
	o.team = team
	o.player = pl
	o.kind = kind
	o.t = clock + tc
	o.point = p
	o.human = team == human_team
	if not o.human:
		o.ai_e = ai_e(kind)
	if kind == "attack":
		pl.has_jumped = false
		_assign_block(1 - team, p, o.t)
	else:
		blocker[1 - team] = null
	opp = o
	return true


var _hitter := [null, null]


func _chosen_hitter(team: int) -> VPlayer:
	return _hitter[team]


func _nearest(team: int, p: Vector3, excluded: VPlayer, no_libero: bool) -> VPlayer:
	var best: VPlayer = null
	var bd := 1e9
	for pl in players[team]:
		if pl == excluded:
			continue
		if no_libero and pl.role == "L":
			continue
		var d := flat_dist(pl.position, p)
		if d < bd:
			bd = d
			best = pl
	return best


func _assign_block(def: int, p: Vector3, t_contact: float) -> void:
	var best: VPlayer = null
	var bd := 1e9
	for pl in players[def]:
		if not (pl.role in FRONT_ROW):
			continue
		var dz := absf(pl.position.z - p.z)
		if dz < bd:
			bd = dz
			best = pl
	blocker[def] = best
	if best:
		best.has_jumped = false
	block_jump_t[def] = t_contact - JUMP_RISE + rng.randf_range(-0.06, 0.1) + bd * 0.03


func human_player() -> VPlayer:
	if human_team < 0:
		return null
	if opp != null and not opp.done and opp.team == human_team:
		return opp.player
	if opp != null and opp.team != human_team and opp.kind == "attack":
		return blocker[human_team]
	return null


# ---------------------------------------------------------------- Eingaben und KI

func _stick_dir(mv: Vector2) -> Vector3:
	var s := side_of(human_team)
	return Vector3(-s, 0, 0) * mv.y + Vector3(0, 0, -s) * mv.x


func _rally_input(mv: Vector2, act: bool) -> void:
	if human_team < 0:
		return
	for pl in players[human_team]:
		pl.manual_dir = Vector3.ZERO
	var hp := human_player()
	if opp != null and not opp.done and opp.team == human_team:
		match opp.kind:
			"attack":
				attack_aim = _stick_aim(mv, opp.player)
				if act:
					_human_touch("spike")
				elif Input.is_action_just_pressed("tip"):
					_human_touch("tip")
			"set":
				hp.manual_dir = _stick_dir(mv)
				if Input.is_action_just_pressed("set_left"):
					_human_touch("left")
				elif Input.is_action_just_pressed("set_mid"):
					_human_touch("mid")
				elif Input.is_action_just_pressed("set_right"):
					_human_touch("right")
				elif act:
					_human_touch("auto")
			_:
				hp.manual_dir = _stick_dir(mv)
				if act:
					_human_touch("")
	elif hp != null and hp == blocker[human_team]:
		var d := _stick_dir(mv)
		hp.manual_dir = Vector3(0, 0, d.z)
		if act and not hp.airborne and not hp.has_jumped:
			hp.jump()


func _stick_aim(mv: Vector2, hitter: VPlayer) -> Vector2:
	if mv.length() < 0.2:
		var hl := team_local(hitter.team, hitter.position).y
		var cross := -2.8 if hl > 0.5 else (2.8 if hl < -0.5 else 2.0)
		return Vector2(6.5, cross)
	return Vector2(clampf(5.0 + mv.y * 3.0, 1.5, 8.5), clampf(mv.x * 3.8, -4.2, 4.2))


func _human_touch(choice: String) -> void:
	if opp.pending:
		return
	var e := clock - opp.t
	if e < -0.35:
		return  # viel zu frueh gedrueckt: ignorieren
	_press(opp, e, choice)


## Frueher Druck wird gemerkt und im idealen Moment ausgefuehrt, spaeter sofort.
func _press(o: Opp, e: float, choice: String) -> void:
	if e < 0.0:
		o.pending = true
		o.press_e = e
		o.press_choice = choice
	else:
		execute_touch(o, e, choice)


func _ai_actions() -> void:
	if opp != null and not opp.done:
		if opp.pending:
			if clock >= opp.t:
				execute_touch(opp, opp.press_e, opp.press_choice)
		elif not opp.human and clock >= opp.t + opp.ai_e:
			_press(opp, opp.ai_e, _ai_choice(opp))
		elif opp.human and clock > opp.t + windows(opp.kind)[2] + 0.01:
			opp.done = true
			popup(opp.player, "Zu spät", Q_COLOR[Q.MISS])
	for t in 2:
		if t == human_team:
			continue
		var b: VPlayer = blocker[t]
		if b != null and opp != null and opp.kind == "attack" and opp.team != t and not b.has_jumped and clock >= block_jump_t[t]:
			b.jump()


func _ai_choice(o: Opp) -> String:
	if o.kind == "attack":
		return "tip" if rng.randf() < 0.12 else "spike"
	return "auto"


# ---------------------------------------------------------------- Ballberuehrungen

func execute_touch(o: Opp, e: float, choice: String) -> void:
	o.done = true
	var pl := o.player
	var q := classify(e, o.kind)
	var reach := 1.25
	match o.kind:
		"dig":
			reach = 1.7
		"set":
			reach = 1.1
		"attack":
			reach = 1.0
	var horiz := flat_dist(pl.position, o.point)
	if q == Q.MISS or horiz > reach:
		if trace:
			print("  T%d %s %s VERFEHLT q=%s e=%.3f horiz=%.2f" % [o.team, pl.role, o.kind, Q_TEXT[q], e, horiz])
		var txt := "Zu früh" if e < 0.0 else "Zu spät"
		if q != Q.MISS:
			txt = "Nicht erreicht"
		popup(pl, txt, Q_COLOR[Q.MISS])
		return
	if (o.kind == "pass" or o.kind == "dig" or o.kind == "free") and horiz > 0.8:
		pl.dive()
	if possession != o.team:
		possession = o.team
		touches = 0
	touches += 1
	touch_total += 1
	last_toucher = pl
	last_touch_team = o.team
	net_touched = false
	popup(pl, Q_TEXT[q], Q_COLOR[q])
	var before := ball.position
	match o.kind:
		"pass", "dig":
			_do_pass(o, q, e)
		"set":
			_do_set(o, q, e, choice)
		"attack":
			_do_attack(o, q, e, choice)
		"free":
			_do_free(o, q)
	if trace:
		print("  T%d %s %s q=%s e=%.3f pos=%s vel=%s" % [o.team, pl.role, o.kind, Q_TEXT[q], e, before, ball_vel])
	plan_next()


func _do_pass(o: Opp, q: int, e: float) -> void:
	pass_quality = q
	# Zu frueh: Ball geht Richtung Netz (oder sogar rueber). Zu spaet: zu weit nach hinten.
	var d := SETTER_TARGET.x + excess(e, o.kind) * 8.0
	var l := SETTER_TARGET.y
	var spread := 0.0
	if q == Q.GOOD:
		spread = 0.7
	elif q == Q.WEAK:
		spread = 1.8
	if o.kind == "dig":
		spread += 0.8
		d += 1.2
	var off := Vector2.from_angle(rng.randf() * TAU) * rng.randf() * spread
	var target := court_pos(o.team, Vector2(d + off.x, l + off.y))
	target.y = H_SET
	var dist := flat_dist(target, ball.position)
	var T := clampf(0.9 + dist / 7.0, 1.0, 1.8)
	if q == Q.WEAK:
		T *= 0.85
	ball_vel = Ballistics.launch_with_time(ball.position, target, T)
	last_action = "pass"


func _do_set(o: Opp, q: int, e: float, choice: String) -> void:
	var setter := o.player
	var sl := team_local(o.team, setter.position)
	var hitter := _pick_hitter(o.team, setter, choice, sl)
	var d := 0.7
	var l := -3.6
	var T := 1.15
	match hitter.role:
		"MB":
			l = sl.y - 1.0
			T = 0.6 if sl.x < 2.0 else 0.85
		"OP":
			l = 3.6
			T = 0.95
		"OH1":
			l = -3.6
		_:
			d = 3.8  # Hinterfeldangriff hinter der 3-m-Linie
			l = -0.5
			T = 1.1
	l += excess(e, "set") * 10.0
	var spread: float = [0.15, 0.45, 1.2][q]
	l += rng.randf_range(-spread, spread)
	d += rng.randf_range(-spread * 0.5, spread)
	if q != Q.WEAK:
		l = clampf(l, -4.1, 4.1)
	var target := court_pos(o.team, Vector2(maxf(d, 0.3), l))
	target.y = H_ATTACK + 0.1
	ball_vel = Ballistics.launch_with_time(ball.position, target, T)
	_hitter[o.team] = hitter
	last_action = "set"


func _pick_hitter(team: int, setter: VPlayer, choice: String, sl: Vector2) -> VPlayer:
	var role := ""
	match choice:
		"left":
			role = "OH1"
		"mid":
			role = "MB"
		"right":
			role = "OP"
		_:
			var r := rng.randf()
			if pass_quality <= Q.GOOD and sl.x < 2.5:
				role = "OH1" if r < 0.4 else ("OP" if r < 0.7 else "MB")
			else:
				role = "OH1" if r < 0.6 else "OP"
	var h := player_by_role(team, role)
	if h == null or h == setter:
		h = player_by_role(team, "OH1") if setter.role != "OH1" else player_by_role(team, "OP")
	return h


func _do_attack(o: Opp, q: int, e: float, choice: String) -> void:
	var aim := attack_aim if o.human else _ai_attack_aim()
	var bp := ball.position
	_hitter[o.team] = null
	if choice == "tip":
		var td := clampf(aim.x, 1.0, 3.5)
		var tt := court_pos(o.team, Vector2(-td, aim.y))
		tt.y = R
		ball_vel = Ballistics.launch_over_net(bp, tt, 3.6, 4.0, 10.0)
		last_action = "tip"
		return
	var d := aim.x
	var l := aim.y
	# Zu frueh: Ball fliegt zu lang (Aus). Zu spaet: Ball geht zu steil (Netz).
	var x := excess(e, "attack")
	if x < 0.0:
		d += -x * 45.0
	else:
		d -= x * 25.0
	var u := 24.0
	if q == Q.GOOD:
		u = 21.0
		l += rng.randf_range(-0.8, 0.8)
	elif q == Q.WEAK:
		u = 15.0
		l += rng.randf_range(-1.5, 1.5)
		d += rng.randf_range(-1.0, 1.0)
	var target := court_pos(o.team, Vector2(-d, l))
	target.y = R
	var vel := Ballistics.launch_with_speed(bp, target, u)
	if q != Q.WEAK or rng.randf() < 0.6:
		# Gute Angreifer passen die Flugbahn an, damit der Ball ueber das Netz geht.
		while _net_cross_y(bp, vel) < NET_H + 0.15 and d < 8.6:
			d += 0.5
			target = court_pos(o.team, Vector2(-d, l))
			target.y = R
			vel = Ballistics.launch_with_speed(bp, target, u)
		if _net_cross_y(bp, vel) < NET_H + 0.15:
			vel = Ballistics.launch_over_net(bp, target, NET_H + 0.25, 6.0, u)
		# ... und schlagen von aussen schraeg ins Feld, damit der Ball zwischen den Antennen kreuzt.
		var tries := 0
		while absf(_net_cross_z(bp, vel)) > HALF_W - 0.25 and tries < 12:
			tries += 1
			l *= 0.8
			l -= signf(bp.z) * 0.4 * (1.0 if o.team == 0 else -1.0)
			target = court_pos(o.team, Vector2(-d, l))
			target.y = R
			vel = Ballistics.launch_with_speed(bp, target, u)
	ball_vel = vel
	last_action = "attack"
	if o.human:
		big_hit.emit(1.0 if q == Q.PERFECT else 0.4)


## Hoehe, in der der Ball die Netzebene kreuzt (99, wenn er nicht hinkommt).
func _net_cross_y(from: Vector3, vel: Vector3) -> float:
	if absf(vel.x) < 0.01 or signf(vel.x) == signf(from.x):
		return 99.0
	var t := -from.x / vel.x
	return from.y + vel.y * t - 0.5 * G * t * t


func _net_cross_z(from: Vector3, vel: Vector3) -> float:
	if absf(vel.x) < 0.01:
		return from.z
	return from.z + vel.z * (-from.x / vel.x)


func _ai_attack_aim() -> Vector2:
	var spots := [Vector2(6.8, -3.3), Vector2(6.8, 3.3), Vector2(7.6, 0.0), Vector2(4.5, -3.6), Vector2(4.5, 3.6), Vector2(3.0, 0.5)]
	var s: Vector2 = spots[rng.randi() % spots.size()]
	return s + Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))


func _do_free(o: Opp, q: int) -> void:
	var target := court_pos(o.team, Vector2(-rng.randf_range(4.5, 7.0), rng.randf_range(-2.5, 2.5)))
	target.y = R
	var clear := NET_H + (1.5 if q != Q.WEAK else 0.5)
	ball_vel = Ballistics.launch_over_net(ball.position, target, clear, 5.0, 11.0)
	last_action = "free"


# ---------------------------------------------------------------- Ballflug

func _step_ball(delta: float) -> void:
	var prev := ball.position
	var res := Ballistics.advance(prev, ball_vel, delta)
	var nxt: Vector3 = res[0]
	ball_vel = res[1]
	if prev.x != 0.0 and signf(prev.x) != signf(nxt.x):
		var f := prev.x / (prev.x - nxt.x)
		var c := prev.lerp(nxt, f)
		if absf(c.z) > HALF_W:
			_end_rally(1 - last_touch_team, "Ball außerhalb der Antenne")
			return
		if c.y < NET_H + R and c.y > NET_BOTTOM - R:
			ball.position = Vector3(signf(prev.x) * (R + 0.02), c.y, c.z)
			ball_vel = Vector3(-ball_vel.x * 0.15, minf(ball_vel.y, 0.0) * 0.3 - 0.5, ball_vel.z * 0.3)
			net_touched = true
			if possession != last_touch_team:
				possession = last_touch_team
			plan_next()
			return
		if c.y <= NET_BOTTOM - R:
			_end_rally(1 - last_touch_team, "Unter dem Netz durch")
			return
		if _try_block(c, prev):
			return
		var t_new := 0 if nxt.x < 0.0 else 1
		if t_new != possession:
			possession = t_new
			touches = 0
	ball.position = nxt
	if nxt.y <= R:
		ball.position.y = R
		_on_ball_landed()


func _try_block(c: Vector3, prev: Vector3) -> bool:
	if last_action == "serve" or last_action == "toss":
		return false  # Aufschlag blocken ist verboten
	var def := 0 if prev.x > 0.0 else 1
	for pl in players[def]:
		if not pl.airborne or not (pl.role in FRONT_ROW):
			continue
		var top: float = pl.block_top()
		if c.y > top + R or c.y < top - 0.75:
			continue
		var dz: float = c.z - pl.position.z
		if absf(dz) > 0.5 + R:
			continue
		var s_att := signf(prev.x)
		if absf(dz) > 0.32:
			# Ball streift die Aussenhand: springt seitlich weg, oft ins Aus (Block-Aus).
			ball.position = Vector3(-s_att * (R + 0.05), c.y, c.z)
			ball_vel = Vector3(ball_vel.x * 0.5, rng.randf_range(1.5, 4.0), signf(dz) * rng.randf_range(3.0, 7.0))
			possession = def
			touches = 0
			last_action = "block_touch"
			popup(pl, "Blockberührung", Q_COLOR[Q.GOOD])
		elif c.y < top - 0.25 and last_action == "attack":
			# Kompletter Block: Ball faellt auf der Seite des Angreifers runter.
			ball.position = Vector3(s_att * (R + 0.05), c.y, c.z)
			ball_vel = Vector3(-ball_vel.x * 0.3, -1.0, ball_vel.z * 0.3 + rng.randf_range(-1.0, 1.0))
			possession = 1 - def
			touches = 0
			last_action = "block"
			popup(pl, "BLOCK!", Q_COLOR[Q.PERFECT])
			if def == human_team:
				big_hit.emit(0.7)
		else:
			# Blockberuehrung: Ball geht weich weiter, zaehlt nicht als Beruehrung.
			ball.position = Vector3(-s_att * (R + 0.05), c.y, c.z)
			ball_vel = Vector3(ball_vel.x * 0.3, rng.randf_range(2.5, 4.5), ball_vel.z * 0.4)
			possession = def
			touches = 0
			last_action = "block_touch"
			popup(pl, "Blockberührung", Q_COLOR[Q.GOOD])
		last_touch_team = def
		last_toucher = null
		plan_next()
		return true
	return false


func _on_ball_landed() -> void:
	var side_team := 0 if ball.position.x < 0.0 else 1
	var inside := absf(ball.position.x) <= HALF_L + R and absf(ball.position.z) <= HALF_W + R
	var winner: int
	var reason: String
	if inside:
		winner = 1 - side_team
		if last_touch_team == side_team:
			if last_action == "toss" or last_action == "serve":
				reason = "Aufschlagfehler"
			elif last_action == "block_touch":
				reason = "Angriffspunkt!"
			elif net_touched:
				reason = "Netz!"
			else:
				reason = "Ball nicht rübergebracht"
		else:
			match last_action:
				"serve":
					reason = "Ass!"
				"attack":
					reason = "Angriffspunkt!"
				"tip":
					reason = "Gelegt!"
				"block":
					reason = "Block-Punkt!"
				_:
					reason = "Ball im Feld"
	elif last_action == "toss":
		winner = 1 - serving_team
		reason = "Aufschlagfehler"
	else:
		winner = 1 - last_touch_team
		if last_action == "block_touch":
			reason = "Block-Aus!"
		elif last_action == "serve":
			reason = "Aufschlag im Aus"
		else:
			reason = "Aus!"
	_end_rally(winner, reason)


func _end_rally(winner: int, reason: String) -> void:
	if phase != Phase.RALLY and phase != Phase.TOSS:
		return
	opp = null
	blocker = [null, null]
	_hitter = [null, null]
	score[winner] += 1
	serving_team = winner
	rally_count += 1
	if trace:
		print("ENDE: %s -> T%d   ball=%s" % [reason, winner, ball.position])
	stats[reason] = stats.get(reason, 0) + 1
	var key: String = "Punkte " + TEAM_NAMES[winner]
	stats[key] = stats.get(key, 0) + 1
	var over: bool = score[winner] >= SET_POINTS and score[winner] - score[1 - winner] >= 2
	if over:
		phase = Phase.SET_OVER
		if hud:
			hud.show_message("%s gewinnt den Satz %d:%d\n\nA / Leertaste: neues Spiel" % [TEAM_NAMES[winner], score[winner], score[1 - winner]])
	else:
		phase = Phase.POINT_PAUSE
		pause_until = clock + (0.2 if autoplay else 2.0)
		if hud:
			hud.show_message("%s\nPunkt für %s" % [reason, TEAM_NAMES[winner]])


func _print_stats() -> void:
	print("Ballwechsel: %d, Beruehrungen im Schnitt: %.2f" % [rally_count, float(touch_total) / maxf(rally_count, 1)])
	var keys := stats.keys()
	keys.sort()
	for k in keys:
		print("  %s: %d (%.0f %%)" % [k, stats[k], 100.0 * stats[k] / rally_count])


# ---------------------------------------------------------------- Laufwege und Anzeige

func _formation(t: int) -> String:
	match phase:
		Phase.PRE_SERVE, Phase.TOSS:
			return "serve" if t == serving_team else "receive"
		Phase.RALLY:
			if opp == null:
				return ""
			if opp.team == t:
				return "cover" if opp.kind == "attack" else "build"
			return "defense"
	return ""


func _update_players(delta: float) -> void:
	for t in 2:
		var form := _formation(t)
		if form != "":
			for pl in players[t]:
				if not (phase == Phase.PRE_SERVE and pl == server()):
					pl.target = court_pos(t, LAYOUT[form][pl.role])
		for pl in players[t]:
			pl.run_speed = 6.0
		var b: VPlayer = blocker[t]
		if b != null and opp != null and opp.team != t and opp.kind == "attack":
			b.run_speed = 4.5
			b.target = Vector3(side_of(t) * 0.45, 0.0, clampf(opp.point.z, -4.1, 4.1))
			for pl in players[t]:
				if pl != b and pl.role in FRONT_ROW:
					var lane: Vector2 = LAYOUT["defense"][pl.role]
					pl.target = court_pos(t, Vector2(3.0, lane.y))
	if opp != null and not opp.done:
		var pl := opp.player
		var p := Vector3(opp.point.x, 0.0, opp.point.z)
		if opp.kind == "attack":
			var t_jump := opp.t - JUMP_RISE
			var t_go := t_jump - flat_dist(pl.position, p) / pl.run_speed - 0.05
			pl.target = p if clock >= t_go else p + Vector3(side_of(opp.team) * 2.2, 0.0, 0.0)
			if clock >= t_jump and not pl.has_jumped:
				pl.jump()
		elif opp.human and not assist:
			pl.target = pl.position
		else:
			pl.target = p
	for t in 2:
		for pl in players[t]:
			pl.tick(delta)


func _update_visuals() -> void:
	ball_shadow.position = Vector3(ball.position.x, 0.008, ball.position.z)
	var k := clampf(1.0 - ball.position.y / 12.0, 0.4, 1.0)
	ball_shadow.scale = Vector3(k, 1.0, k)
	var hp := human_player()
	for t in 2:
		for pl in players[t]:
			pl.set_controlled(pl == hp)

	var show_ring := opp != null and not opp.done and opp.human
	_ring_target.visible = show_ring
	_ring_timer.visible = show_ring
	if show_ring:
		var p := Vector3(opp.point.x, 0.03, opp.point.z)
		_ring_target.position = p
		_ring_timer.position = p
		var remain := clampf((opp.t - clock) / 1.0, 0.0, 1.0)
		_ring_timer.scale = Vector3.ONE * (1.0 + remain * 2.5)
		var near: bool = absf(opp.t - clock) <= windows(opp.kind)[0]
		_ring_timer_mat.albedo_color = Color(0.3, 1.0, 0.3) if near else Color(1.0, 0.85, 0.1)

	var aim_vis := false
	if human_team >= 0:
		if (phase == Phase.PRE_SERVE or phase == Phase.TOSS) and serving_team == human_team and not serve_done:
			_aim_marker.position = court_pos(human_team, Vector2(-serve_aim.x, serve_aim.y)) + Vector3(0, 0.03, 0)
			aim_vis = true
		elif show_ring and opp.kind == "attack":
			_aim_marker.position = court_pos(human_team, Vector2(-attack_aim.x, attack_aim.y)) + Vector3(0, 0.03, 0)
			aim_vis = true
	_aim_marker.visible = aim_vis


## Kurzer Hinweis, was der Mensch gerade tun kann.
func hint() -> String:
	match phase:
		Phase.INTRO:
			return ""
		Phase.PRE_SERVE:
			if serving_team == human_team:
				return "Aufschlag: Ziel mit Stick / WASD verschieben, A / Leertaste zum Hochwerfen"
		Phase.TOSS:
			if serving_team == human_team and not serve_done:
				return "Jetzt schlagen: A / Leertaste, wenn der Ball oben ist"
		Phase.RALLY:
			if opp != null and not opp.done and opp.team == human_team:
				match opp.kind:
					"pass":
						return "Annahme: A / Leertaste, wenn sich der Ring schließt"
					"dig":
						return "Abwehr! A / Leertaste im richtigen Moment"
					"set":
						return "Zuspiel: X/J Außen · Y/K Mitte · B/L Diagonal · A/Leertaste automatisch"
					"attack":
						return "Angriff: Ziel mit Stick / WASD, A / Leertaste schlagen, RB / Umschalt legen"
					"free":
						return "Ball rüberspielen: A / Leertaste"
			if human_player() != null:
				return "Block: A / Leertaste springen, wenn der Angreifer abspringt"
	return ""
