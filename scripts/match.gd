extends Node3D
## Ein Satz Hallenvolleyball, 6 gegen 6. Steuert Ball, Spielablauf, KI und Eingaben.
##
## Koordinaten: Netz bei x = 0, Team 0 (Heim, Mensch) spielt auf x < 0, Team 1 auf x > 0.
## "Lokal" heisst aus Sicht eines Teams: x = Abstand zum Netz, y = seitlich (+ = rechts).
##
## Steuerung 2.0: Baggern und Pritschen auf zwei Tasten, Schlagen durch Aufladen und
## Loslassen, Trefferpunkt am Ball mit dem rechten Stick, Block mit dem linken Stick.

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
const SET_POINTS := 25

const SLOW := 0.35  # Tempo in der Zeitlupe
const CHARGE_FULL := 0.6  # Sekunden (Echtzeit) bis zur vollen Kraft
const OVERCHARGE := 1.25  # ab hier ist der Schlag ueberzogen
const OVER_OK := 12.0  # bis zu dieser Ballgeschwindigkeit (m/s) ist Pritschen sicher
const OVER_RISKY := 17.0  # darueber droht "Ball gehalten"

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
const SERVE_KIND_TEXT := ["Stand", "Sprung"]


## Die naechste Ballberuehrung, die ansteht.
class Opp:
	var team := 0
	var player: VPlayer = null
	var kind := ""  # pass, dig, set, attack, free
	var t := 0.0  # idealer Zeitpunkt der Beruehrung
	var point := Vector3.ZERO  # Ballposition in diesem Moment
	var speed := 0.0  # Ballgeschwindigkeit in diesem Moment
	var done := false
	var human := false
	var ai_e := 0.0
	var pending := false  # frueh gedrueckt: Beruehrung passiert im idealen Moment
	var press_e := 0.0
	var press_choice := ""
	var tech := "bump"  # bump = Baggern, over = Pritschen
	var rs := Vector2.ZERO  # Trefferpunkt am Ball (y + = oben)
	var power := 0.8
	var over := 0.0  # Aufladung beim Loslassen (> 1 = ueberzogen)
	var win_scale := 1.0  # Timing-Fenster groesser (> 1) oder kleiner (< 1)
	var no_reach := false  # KI-Abwehr kommt nicht mehr rechtzeitig hin
	var start_pos := Vector3.ZERO
	var max_run := 0.0


var phase := Phase.INTRO
var clock := 0.0
var players: Array = [[], []]
var ball: Node3D
var ball_mesh: MeshInstance3D
var ball_shadow: MeshInstance3D
var ball_vel := Vector3.ZERO
var ball_g := G
var flutter := 0.0
var last_shot_style := ""
var score := [0, 0]
var serving_team := 0
var possession := 0
var touches := 0
var last_toucher: VPlayer = null
var last_touch_team := -1
var last_action := ""
var net_touched := false
var opp: Opp = null
var blockers: Array = [[], []]
var block_dirs: Array = [[], []]
var block_err := [0.0, 0.0]  # wie genau der Hauptblocker zum Angreifer steht
var pass_quality := Q.GOOD
var pause_until := 0.0
var toss_time := -1.0
var serve_done := false
var serve_time := -1.0
var serve_ideal := 0.0
var serve_kind := 1  # 0 Stand, 1 Sprung
var serve_contact := Vector2.ZERO
var ai_serve_e := 0.0
var serve_aim := Vector2(5.5, 0.0)
var assist := true
var slowmo_on := true
var zoom_on := true
var human_team := 0
var autoplay := false
var autoplay_rallies := 200
var trace := false
var autopress := false  # Test: drueckt fuer den Menschen automatisch
var hud = null
var cfg := GameSettings.new()
var rng := RandomNumberGenerator.new()

# Eingabe-Zustand des Menschen
var rs := Vector2.ZERO
var mouse_rs := Vector2.ZERO
var charging := false
var charge := 0.0
var preview_target := Vector3.ZERO
var preview_valid := false

# Kamera (wird von main.gd gelesen)
var cam_mode := ""
var cam_subject: VPlayer = null
var _slow_tail_until := 0.0
var _hitstop_left := 0.0

var _ring_target: MeshInstance3D
var _ring_target_mat: StandardMaterial3D
var _ring_timer: MeshInstance3D
var _ring_timer_mat: StandardMaterial3D
var _aim_marker: MeshInstance3D
var _shadow_mesh: ImmediateMesh
var _shadow_node: MeshInstance3D

# Statistik fuer den automatischen Test
var stats := {}
var rally_count := 0
var touch_total := 0


func _ready() -> void:
	rng.randomize()
	if not OS.get_cmdline_user_args().has("--autoplay"):
		cfg.load_file()
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
		elif a == "--botplay":
			autopress = true  # wie --autopress, aber mit Kamera, Zeitlupe und Anzeigen
		elif a == "--trace":
			trace = true
		elif a.begins_with("--seed="):
			rng.seed = int(a.get_slice("=", 1))
		elif a.begins_with("--stufe="):
			cfg.apply_preset(a.get_slice("=", 1))
	if autoplay:
		human_team = 0 if autopress else -1
		new_match()
	elif human_team < 0 or autopress:
		new_match()
	elif hud:
		hud.show_intro()


func _input(event: InputEvent) -> void:
	# Maus als rechter Stick: Bewegung verschiebt den Trefferpunkt.
	if event is InputEventMouseMotion:
		mouse_rs += Vector2(event.relative.x, -event.relative.y) * 0.008
		mouse_rs = mouse_rs.limit_length(1.0)


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
	ball = Node3D.new()
	add_child(ball)
	ball_mesh = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.14  # etwas groesser gezeichnet, damit man ihn gut sieht
	s.height = 0.28
	ball_mesh.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.92, 0.35)
	m.emission_enabled = true
	m.emission = Color(0.35, 0.3, 0.05)
	ball_mesh.material_override = m
	ball.add_child(ball_mesh)

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
	_ring_target_mat = _ring_target.material_override
	_ring_timer = _torus(0.44, 0.52, Color(1.0, 0.85, 0.1))
	_ring_timer_mat = _ring_timer.material_override
	_aim_marker = _torus(0.25, 0.4, Color(1.0, 0.3, 0.25, 0.9))
	_shadow_mesh = ImmediateMesh.new()
	_shadow_node = MeshInstance3D.new()
	_shadow_node.mesh = _shadow_mesh
	var sm := _unshaded(Color(0.05, 0.1, 0.35, 0.42))
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shadow_node.material_override = sm
	add_child(_shadow_node)


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
func excess(e: float, kind: String, scale := 1.0) -> float:
	var w0: float = windows(kind)[0] * scale
	return signf(e) * maxf(0.0, absf(e) - w0)


func classify(e: float, kind: String, scale := 1.0) -> int:
	var w := windows(kind)
	var a := absf(e) / scale
	if a <= w[0]:
		return Q.PERFECT
	if a <= w[1]:
		return Q.GOOD
	if a <= w[2]:
		return Q.WEAK
	return Q.MISS


## Mehr Kraft und ein Trefferpunkt weit weg von der Mitte machen das Timing-Fenster enger.
func hit_window_scale(power: float, contact: Vector2, jump: bool) -> float:
	var s := lerpf(1.35, 0.85, clampf(power, 0.0, 1.0))
	s *= 1.0 - 0.2 * minf(contact.length(), 1.0)
	if jump:
		s *= 0.9
	return s


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
	blockers = [[], []]
	block_dirs = [[], []]
	touches = 0
	possession = serving_team
	last_toucher = null
	last_touch_team = serving_team
	last_action = ""
	net_touched = false
	serve_done = false
	serve_time = -1.0
	toss_time = -1.0
	charging = false
	charge = 0.0
	mouse_rs = Vector2.ZERO
	ball_g = G
	flutter = 0.0
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
		serve_kind = 1 if rng.randf() < 0.55 else 0
		var r := rng.randf()
		if serve_kind == 1:
			serve_contact = Vector2(rng.randf_range(-0.3, 0.3), 0.7) if r < 0.6 else Vector2(rng.randf_range(-0.2, 0.2), 0.0)
		else:
			serve_contact = Vector2(rng.randf_range(-0.2, 0.2), 0.0) if r < 0.85 else Vector2(0.0, -0.7)
	if hud:
		hud.clear_message()


func _hold_ball_at_server() -> void:
	var s := server()
	ball.position = s.position + Vector3(-side_of(serving_team) * 0.4, 1.3, 0.0)


func _empty_input() -> Dictionary:
	return {"mv": Vector2.ZERO, "rs": Vector2.ZERO, "bump": false, "over": false,
		"hit_down": false, "hit_up": false, "hit_held": false, "kind_prev": false, "kind_next": false}


func _read_input() -> Dictionary:
	var d := _empty_input()
	d.mv = Input.get_vector("move_left", "move_right", "move_down", "move_up")
	var stick := _held_stick(Input.get_vector("aim_left", "aim_right", "aim_down", "aim_up"))
	d.rs = stick if stick.length() > 0.15 else mouse_rs
	d.bump = Input.is_action_just_pressed("bump")
	d.over = Input.is_action_just_pressed("overhand")
	d.hit_down = Input.is_action_just_pressed("hit")
	d.hit_up = Input.is_action_just_released("hit")
	d.hit_held = Input.is_action_pressed("hit")
	d.kind_prev = Input.is_action_just_pressed("serve_prev")
	d.kind_next = Input.is_action_just_pressed("serve_next")
	if Input.is_action_just_pressed("toggle_assist"):
		assist = not assist
	if Input.is_action_just_pressed("toggle_slowmo"):
		slowmo_on = not slowmo_on
	if Input.is_action_just_pressed("toggle_zoom"):
		zoom_on = not zoom_on
	return d


## Der rechte Stick federt beim Loslassen zur Mitte zurueck. Damit die gewaehlte
## Schlagrichtung dabei nicht verloren geht, gilt der letzte deutliche Ausschlag
## noch eine einstellbare Zeit lang weiter ("Stick nachhalten").
var _rs_hold := Vector2.ZERO
var _rs_hold_ms := 0


func _held_stick(stick: Vector2) -> Vector2:
	var now := Time.get_ticks_msec()
	var l := stick.length()
	if l >= 0.35:
		var turned := _rs_hold == Vector2.ZERO or stick.normalized().dot(_rs_hold.normalized()) < 0.8
		if turned or l >= _rs_hold.length() * 0.85:
			_rs_hold = stick
			_rs_hold_ms = now
			return stick
	if _rs_hold != Vector2.ZERO and now - _rs_hold_ms <= int(cfg.get_v("stick_hold")):
		return _rs_hold
	_rs_hold = Vector2.ZERO
	return stick


func _physics_process(delta: float) -> void:
	clock += delta
	var real_delta := delta / maxf(Engine.time_scale, 0.01)
	var inp := _empty_input()
	if human_team >= 0:
		inp = _auto_input() if autopress else _read_input()
		rs = inp.rs
	if charging:
		charge += real_delta / CHARGE_FULL
	var start: bool = inp.bump or inp.hit_down or inp.over

	match phase:
		Phase.INTRO:
			if start:
				new_match()
		Phase.PRE_SERVE:
			_hold_ball_at_server()
			if serving_team == human_team:
				serve_aim = _nudge_aim(serve_aim, inp.mv, delta)
				serve_contact = rs
				if inp.kind_prev or inp.kind_next:
					serve_kind = 1 - serve_kind
				if clock >= pause_until:
					if inp.hit_down:
						_do_toss()
						_start_charge()
					elif inp.bump:
						_do_toss()
			elif clock >= pause_until:
				_do_toss()
		Phase.TOSS:
			if serving_team == human_team:
				serve_aim = _nudge_aim(serve_aim, inp.mv, delta)
				serve_contact = rs
				if not serve_done:
					if inp.hit_down and not charging:
						_start_charge()
					elif inp.hit_up and charging:
						var c := _release_charge()
						_serve_hit(clock - serve_ideal, minf(c, 1.0), serve_contact, c)
					elif clock > serve_ideal + windows("serve")[2] * 1.4 + 0.03:
						serve_done = true
						charging = false
						popup(server(), "Zu spät", Q_COLOR[Q.MISS])
			elif not serve_done and clock >= serve_ideal + ai_serve_e:
				_serve_hit(ai_serve_e, rng.randf_range(0.7, 0.95), serve_contact, 0.9)
			_step_ball(delta)
		Phase.RALLY:
			_rally_input(inp)
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
			elif start or (human_team < 0 and clock >= pause_until + 3.0):
				new_match()

	_update_players(delta)
	_update_time_and_camera(real_delta)
	_update_visuals()
	if hud:
		hud.update_view(self)


func _start_charge() -> void:
	charging = true
	charge = 0.0


func _release_charge() -> float:
	charging = false
	return minf(charge, 1.5)


## Nur fuer Tests: drueckt mit etwas Zufall nahe am idealen Moment.
var _auto_t := -1.0
var _auto_rs := Vector2.ZERO


func _auto_input() -> Dictionary:
	var d := _empty_input()
	d.rs = _auto_rs
	match phase:
		Phase.SET_OVER, Phase.INTRO:
			d.bump = true
		Phase.PRE_SERVE:
			if clock >= pause_until:
				_auto_rs = Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.2, 0.8))
				serve_kind = rng.randi() % 2
				d.rs = _auto_rs
				d.hit_down = true
		Phase.TOSS:
			if charging and _due(serve_ideal):
				d.hit_up = true
		Phase.RALLY:
			if opp != null and not opp.done and not opp.pending and opp.team == human_team:
				if opp.kind == "attack":
					if not charging and clock >= opp.t - 0.7:
						_auto_rs = Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.5, 0.8))
						d.rs = _auto_rs
						d.hit_down = true
					elif charging and _due(opp.t):
						d.hit_up = true
				elif _due(opp.t):
					if opp.speed <= OVER_OK:
						d.over = true
					else:
						d.bump = true
			elif human_player() != null and opp != null and opp.kind == "attack":
				if _due(opp.t - JUMP_RISE):
					d.hit_down = true
			else:
				_auto_t = -1.0
	return d


func _due(ideal: float) -> bool:
	if _auto_t < 0.0:
		_auto_t = ideal + rng.randf_range(-0.07, 0.07)
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
	ball_g = G
	if serve_kind == 1:
		# Sprungaufschlag: hoher Wurf nach vorn, der Aufschlaeger laeuft an und springt.
		ball_vel = Vector3(-side_of(serving_team) * 0.6, 7.4, 0.0)
		serve_ideal = clock + Ballistics.time_to_height(ball.position, ball_vel, 3.2)
	else:
		ball_vel = Vector3(0.0, 5.0, 0.0)
		serve_ideal = clock + Ballistics.time_to_height(ball.position, ball_vel, 2.5)
	last_action = "toss"
	last_touch_team = serving_team
	ai_serve_e = ai_e("serve")


## Art des Aufschlags aus dem Trefferpunkt: oben Topspin, Mitte Flatter, unten kurz.
func serve_style(contact: Vector2) -> String:
	if contact.y > 0.35:
		return "topspin"
	if contact.y < -0.35:
		return "short"
	return "float"


func serve_style_text(kind: int, contact: Vector2) -> String:
	match serve_style(contact):
		"topspin":
			return "Sprung-Topspin" if kind == 1 else "Topspin"
		"short":
			return "Kurz"
	return "Sprungflatter" if kind == 1 else "Flatter"


func _serve_hit(e: float, power: float, contact: Vector2, c: float) -> void:
	serve_done = true
	charging = false
	var srv := server()
	var jump := serve_kind == 1
	var q := classify(e, "serve", hit_window_scale(power, contact, jump))
	if q == Q.MISS:
		popup(srv, "Zu früh" if e < 0.0 else "Zu spät", Q_COLOR[Q.MISS])
		return
	if c > OVERCHARGE + 0.25 and q < Q.WEAK:
		q += 1
	var style := serve_style(contact)
	var d := serve_aim.x
	var l := serve_aim.y - contact.x * 1.5
	var g := G
	var umax := 16.0
	var clear := NET_H + 0.45
	match style:
		"topspin":
			g = G * (1.45 if jump else 1.25)
			umax = 22.0 if jump else 17.0
		"float":
			umax = 20.0 if jump else 16.0
		"short":
			d = minf(d, 3.2)
			umax = 9.0
			clear = NET_H + 0.8
	var u := lerpf(9.0, umax, power)
	if q == Q.GOOD:
		clear += 0.3
		u = minf(u, umax * 0.85)
		d += rng.randf_range(-0.6, 0.6)
		l += rng.randf_range(-0.6, 0.6)
	elif q == Q.WEAK:
		clear += 1.1
		u = minf(u, umax * 0.6)
		d += rng.randf_range(-1.2, 1.2)
		l += rng.randf_range(-1.2, 1.2)
	# Ueberzogen: Ball wird zu lang.
	if c > OVERCHARGE:
		d += rng.randf_range(0.0, (c - OVERCHARGE) * 6.0)
	# Zu frueh getroffen: Ball fliegt zu lang. Zu spaet: Ball fliegt zu flach (Netz).
	var x := excess(e, "serve")
	if x < 0.0:
		d += -x * 30.0
	else:
		clear -= x * lerpf(4.0, 9.0, cfg.unit("faults"))
	var target := court_pos(serving_team, Vector2(-d, l))
	target.y = R
	ball_g = g
	ball_vel = Ballistics.launch_over_net(ball.position, target, clear, 8.0, u, g)
	flutter = 0.0
	if style == "float" and q <= Q.GOOD:
		flutter = 0.32 if jump else 0.26
	if trace:
		print("AUFSCHLAG T%d %s q=%s e=%.3f p=%.2f target=%s vel=%s" % [serving_team, style, Q_TEXT[q], e, power, target, ball_vel])
	last_action = "serve"
	last_toucher = srv
	last_touch_team = serving_team
	possession = serving_team
	touches = 1
	serve_time = clock
	phase = Phase.RALLY
	popup(srv, Q_TEXT[q], Q_COLOR[q])
	if serving_team == human_team and q == Q.PERFECT and power > 0.8:
		big_hit.emit(0.6)
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
	var apex := Ballistics.apex_height(ball.position, ball_vel, ball_g)
	var kind := "pass"
	var h := H_PASS
	if idx == 0:
		if (last_action == "attack" and ball_vel.length() > 12.0) or (last_action == "block_touch" and ball_vel.length() > 9.0):
			kind = "dig"
		elif last_action == "block":
			kind = "dig"
	elif idx == 1:
		kind = "set"
		h = H_SET if apex >= H_SET + 0.3 else H_PASS + 0.1
	elif apex >= H_ATTACK + 0.05:
		kind = "attack"
		h = H_ATTACK
	else:
		kind = "free"

	var tc := Ballistics.time_to_height(ball.position, ball_vel, h, ball_g)
	if tc < 0.0:
		return false
	var p := Ballistics.pos_at(ball.position, ball_vel, tc, ball_g)
	if kind == "attack" and (signf(p.x) != side_of(team) or absf(p.x) > 6.0 or absf(p.x) < 0.2):
		kind = "free"
		h = H_PASS
		tc = Ballistics.time_to_height(ball.position, ball_vel, h, ball_g)
		p = Ballistics.pos_at(ball.position, ball_vel, tc, ball_g)
	if signf(p.x) != side_of(team) or absf(p.x) < 0.2:
		return false
	if absf(p.x) > HALF_L + 4.0 or absf(p.z) > HALF_W + 3.5:
		return false

	if team != last_touch_team and team != human_team:
		# Die KI laesst Aus-Baelle fallen, verschaetzt sich aber manchmal knapp an der Linie.
		var land_t := Ballistics.time_to_height(ball.position, ball_vel, R, ball_g)
		var land := Ballistics.pos_at(ball.position, ball_vel, land_t, ball_g)
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
	o.speed = Vector3(ball_vel.x, ball_vel.y - ball_g * tc, ball_vel.z).length()
	o.human = team == human_team
	# Ein Flatterball ist schwer zu lesen: kleineres Timing-Fenster bei der Annahme.
	if flutter > 0.0 and last_action == "serve":
		o.win_scale = 0.88
	if o.human and (kind == "pass" or kind == "dig" or kind == "free"):
		o.win_scale *= cfg.get_v("receive_help") / 100.0
	if not o.human:
		o.ai_e = ai_e(kind)
		if kind == "dig":
			_ai_dig_limits(o, tc)
	if kind == "attack":
		pl.has_jumped = false
		pl.lean = 0.0
		_assign_block(1 - team, p, o.t)
	else:
		blockers[1 - team] = []
	opp = o
	return true


## KI-Abwehr: braucht eine Reaktionszeit, laeuft nicht beliebig schnell und wehrt harte
## Baelle seltener sauber ab. Wie gut, stellt "Gegner-Abwehr" ein.
func _ai_dig_limits(o: Opp, tc: float) -> void:
	var skill := cfg.unit("ai_defense")
	var react := lerpf(0.42, 0.2, skill)
	var run := lerpf(3.2, 5.5, skill)
	var reach := lerpf(1.05, 1.6, skill)
	o.start_pos = o.player.position
	o.max_run = maxf(0.0, tc - react) * run
	if flat_dist(o.player.position, o.point) > o.max_run + reach:
		o.no_reach = true
	var hard := clampf((o.speed - 14.0) / 12.0, 0.0, 1.0) * (1.0 - 0.6 * skill)
	o.ai_e *= 1.0 + hard * 1.6


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


## Stellt den Block: der naechste Vorderspieler blockt, der Mittelblocker laeuft zum
## Doppelblock dazu. Bei Angriffen ueber die Mitte schliessen beide Aussenblocker (Dreierblock).
## Ob die Helfer rechtzeitig ankommen, haengt vom Tempo des Zuspiels ab.
func _assign_block(def: int, p: Vector3, t_contact: float) -> void:
	var front: Array = []
	for pl in players[def]:
		if pl.role in FRONT_ROW:
			front.append(pl)
	var mb := player_by_role(def, "MB")
	var list: Array = []
	var dirs: Array = []
	if absf(p.z) < 1.5:
		list = [mb]
		dirs = [0.0]
		var t_left := t_contact - clock
		for pl in front:
			if pl != mb and (t_left > 0.9 or rng.randf() < 0.5):
				list.append(pl)
				dirs.append(signf(pl.position.z - mb.position.z))
	else:
		var best: VPlayer = null
		var bd := 1e9
		for pl in front:
			var dz := absf(pl.position.z - p.z)
			if dz < bd:
				bd = dz
				best = pl
		list = [best]
		dirs = [0.0]
		var partner: VPlayer = mb
		if best == mb:
			partner = null
			for pl in front:
				if pl != mb and (partner == null or absf(pl.position.z - p.z) < absf(partner.position.z - p.z)):
					partner = pl
		list.append(partner)
		dirs.append(-signf(p.z))
	var base_jump := t_contact - JUMP_RISE
	for i in list.size():
		var pl: VPlayer = list[i]
		pl.has_jumped = false
		pl.hand_shift = 0.0
		pl.hand_reach = 0.0
		pl.block_pose = true
		pl.block_jump_at = base_jump + rng.randf_range(-0.05, 0.09) + (0.03 if i > 0 else 0.0)
	blockers[def] = list
	block_dirs[def] = dirs
	block_err[def] = rng.randf_range(-0.4, 0.4)


func human_player() -> VPlayer:
	if human_team < 0:
		return null
	if opp != null and not opp.done and opp.team == human_team:
		return opp.player
	if opp != null and opp.team != human_team and opp.kind == "attack" and not blockers[human_team].is_empty():
		return blockers[human_team][0]
	return null


# ---------------------------------------------------------------- Eingaben und KI

func _stick_dir(mv: Vector2) -> Vector3:
	var s := side_of(human_team)
	return Vector3(-s, 0, 0) * mv.y + Vector3(0, 0, -s) * mv.x


## Zuspielrichtung aus dem linken Stick: links Aussen, rechts Diagonal, vorn Mitte, hinten Hinterfeld.
func _set_choice(mv: Vector2) -> String:
	if mv.length() < 0.4:
		return "auto"
	if absf(mv.x) >= absf(mv.y):
		return "left" if mv.x < 0.0 else "right"
	return "mid" if mv.y > 0.0 else "back"


func _rally_input(inp: Dictionary) -> void:
	if human_team < 0:
		return
	for pl in players[human_team]:
		pl.manual_dir = Vector3.ZERO
	var mv: Vector2 = inp.mv
	var hp := human_player()
	if opp != null and not opp.done and opp.team == human_team:
		match opp.kind:
			"attack":
				_attack_input(inp)
			"set":
				if not assist:
					hp.manual_dir = _stick_dir(mv)
				if inp.bump:
					_human_touch("bump", _set_choice(mv))
				elif inp.over:
					_human_touch("over", _set_choice(mv))
			_:
				hp.manual_dir = _stick_dir(mv)
				if inp.bump:
					_human_touch("bump", "")
				elif inp.over:
					_human_touch("over", "")
	elif hp != null and not blockers[human_team].is_empty() and hp == blockers[human_team][0]:
		var d := _stick_dir(mv)
		if not hp.airborne:
			hp.manual_dir = Vector3(0, 0, d.z)
			if inp.hit_down and not hp.has_jumped:
				hp.jump()
		else:
			# In der Luft: Haende mit dem Stick verschieben, Stick nach vorn = ueber das Netz greifen.
			hp.hand_shift = move_toward(hp.hand_shift, d.z * 0.45, 3.0 * get_physics_process_delta_time())
			hp.hand_reach = 0.12 if mv.y > 0.5 else 0.0


func _attack_input(inp: Dictionary) -> void:
	opp.rs = rs
	if inp.hit_down and not charging:
		_start_charge()
	elif inp.hit_up and charging and not opp.pending:
		var e := clock - opp.t
		if e < -0.45:
			charging = false  # viel zu frueh losgelassen: neu aufladen
			return
		var c := _release_charge()
		opp.power = clampf(c, 0.15, 1.0)
		opp.over = c
		opp.win_scale = hit_window_scale(opp.power, rs, false)
		_press(opp, e, "spike")


func _human_touch(tech: String, choice: String) -> void:
	if opp.pending:
		return
	var e := clock - opp.t
	if e < -maxf(0.35, windows(opp.kind)[2] * opp.win_scale + 0.05):
		return  # viel zu frueh gedrueckt: ignorieren
	opp.tech = tech
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
			_ai_prepare(opp)
			_press(opp, opp.ai_e, "auto")
		elif opp.human and clock > opp.t + windows(opp.kind)[2] * opp.win_scale + 0.01:
			opp.done = true
			charging = false
			popup(opp.player, "Zu spät", Q_COLOR[Q.MISS])
	if opp == null or opp.kind != "attack":
		return
	for t in 2:
		for i in blockers[t].size():
			var b: VPlayer = blockers[t][i]
			if t == human_team and i == 0:
				continue
			if opp.team != t and not b.has_jumped and clock >= b.block_jump_at:
				b.jump()
				_ai_block_hands(t, b)


## KI-Blocker: liest mit etwas Glueck die Schlagrichtung und schiebt die Haende dorthin.
func _ai_block_hands(t: int, b: VPlayer) -> void:
	if opp == null:
		return
	var read_p := 0.3 if t == human_team else lerpf(0.1, 0.5, cfg.unit("ai_block"))
	var read := rng.randf() < read_p
	var shift := rng.randf_range(-0.3, 0.3)
	if read:
		var info := attack_shot(opp.team, opp.point, opp.rs, opp.power)
		var tgt: Vector3 = info.target
		# Wo kreuzt die Linie Ball -> Ziel das Netz?
		var f := absf(opp.point.x) / maxf(absf(opp.point.x - tgt.x), 0.01)
		var zc := lerpf(opp.point.z, tgt.z, f)
		shift = clampf(zc - b.position.z, -0.45, 0.45)
	b.hand_shift = shift
	if t != human_team:
		b.hand_reach = 0.12 if rng.randf() < 0.12 else 0.0


func _ai_prepare(o: Opp) -> void:
	match o.kind:
		"attack":
			_ai_attack_choice(o)
		"set":
			o.tech = "over" if o.speed <= OVER_OK else "bump"
		"pass", "free":
			o.tech = "over" if o.speed <= OVER_OK and rng.randf() < 0.5 else "bump"
		_:
			o.tech = "bump"


## KI-Angreifer: waehlt Trefferpunkt und Kraft. Steht ein Block im Weg, sucht er oft
## eine andere Richtung (er "liest" den Block).
func _ai_attack_choice(o: Opp) -> void:
	var hl := team_local(o.team, o.point).y
	# Wer links steht, trifft den Ball links, damit er diagonal nach rechts fliegt.
	var cross := -0.55 if hl < 0.0 else 0.55
	if absf(hl) < 1.5:
		cross = 0.45 if rng.randf() < 0.5 else -0.45
	var options := [Vector2(0.0, 0.3), Vector2(cross, 0.4), Vector2(cross * 0.6, 0.8), Vector2(cross * 0.25, 0.5)]
	var r := rng.randf()
	if r < 0.1:
		options.push_front(Vector2(rng.randf_range(-0.5, 0.5), -0.7))  # Leger
	elif r < 0.16:
		options.push_front(Vector2(signf(cross) * 0.95, 0.0))  # Cut Shot
	elif r < 0.2 and absf(hl) > 1.5:
		options.push_front(Vector2(-signf(cross) * 0.95, 0.5))  # Block-Out
	else:
		var first: Vector2 = options[rng.randi() % options.size()]
		options.push_front(first)
	o.power = rng.randf_range(0.6, 1.0)
	o.over = o.power
	o.rs = options[0]
	if rng.randf() < 0.65:
		for cand in options:
			if not _shot_blocked(o, cand):
				o.rs = cand
				break


func _shot_blocked(o: Opp, contact: Vector2) -> bool:
	var info := attack_shot(o.team, o.point, contact, o.power)
	var tgt: Vector3 = info.target
	var f := absf(o.point.x) / maxf(absf(o.point.x - tgt.x), 0.01)
	var zc := lerpf(o.point.z, tgt.z, f)
	for b in blockers[1 - o.team]:
		# Noch nicht abgesprungen: dort, wo der Blocker gerade hinlaeuft.
		var bz: float = b.hands_z() if b.airborne else b.target.z
		if absf(zc - bz) < 0.5:
			return true
	return false


# ---------------------------------------------------------------- Ballberuehrungen

func execute_touch(o: Opp, e: float, choice: String) -> void:
	o.done = true
	var pl := o.player
	var q := classify(e, o.kind, o.win_scale)
	var reach := 1.25
	match o.kind:
		"dig":
			reach = 1.7
		"set":
			reach = 1.1
		"attack":
			reach = 1.0
	var horiz := flat_dist(pl.position, o.point)
	if o.no_reach:
		pl.dive()
	if q == Q.MISS or horiz > reach or o.no_reach:
		if trace:
			print("  T%d %s %s VERFEHLT q=%s e=%.3f horiz=%.2f" % [o.team, pl.role, o.kind, Q_TEXT[q], e, horiz])
		var txt := "Zu früh" if e < 0.0 else "Zu spät"
		if q != Q.MISS:
			txt = "Nicht erreicht"
		popup(pl, txt, Q_COLOR[Q.MISS])
		return
	# Pritschen: genau, aber nur bei Baellen, die nicht zu hart kommen.
	if o.kind != "attack" and o.tech == "over":
		if o.speed > OVER_RISKY:
			if rng.randf() < 0.35 * cfg.unit("faults"):
				_fault(o, "Ball gehalten")
				return
			q = mini(q + 2, Q.WEAK)
		elif o.speed > OVER_OK:
			q = mini(q + 1, Q.WEAK)
		if o.kind == "set" and q == Q.WEAK and rng.randf() < 0.12 * cfg.unit("faults"):
			_fault(o, "Doppelberührung")
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
	var label: String = Q_TEXT[q]
	if o.human and o.kind != "attack":
		label = ("Pritschen · " if o.tech == "over" else "Baggern · ") + label
	popup(pl, label, Q_COLOR[q])
	var before := ball.position
	var was_flutter := flutter > 0.0 and last_action == "serve"
	flutter = 0.0
	ball_g = G
	match o.kind:
		"pass", "dig":
			_do_pass(o, q, e, was_flutter)
		"set":
			_do_set(o, q, e, choice)
		"attack":
			_do_attack(o, q, e)
		"free":
			_do_free(o, q)
	stats["Technik " + ("Pritschen" if o.tech == "over" else "Baggern")] = stats.get("Technik " + ("Pritschen" if o.tech == "over" else "Baggern"), 0) + (1 if o.kind != "attack" else 0)
	if trace:
		print("  T%d %s %s %s q=%s e=%.3f pos=%s vel=%s" % [o.team, pl.role, o.kind, o.tech, Q_TEXT[q], e, before, ball_vel])
	plan_next()


func _fault(o: Opp, reason: String) -> void:
	popup(o.player, reason, Q_COLOR[Q.MISS])
	last_touch_team = o.team
	_end_rally(1 - o.team, reason)


func _do_pass(o: Opp, q: int, e: float, was_flutter: bool) -> void:
	pass_quality = q
	# Zu frueh: Ball geht Richtung Netz (oder sogar rueber). Zu spaet: zu weit nach hinten.
	var d := SETTER_TARGET.x + excess(e, o.kind, o.win_scale) * 8.0
	var l := SETTER_TARGET.y
	var spread := 0.0
	if q == Q.GOOD:
		spread = 0.7
	elif q == Q.WEAK:
		spread = 1.8
	if o.kind == "dig":
		spread += 0.8
		d += 1.2
	if was_flutter:
		spread += 0.4
	if o.tech == "over" and o.speed <= OVER_OK:
		spread *= 0.6
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
	var d := 1.0
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
	var bump_set := o.tech != "over"
	if bump_set:
		T = maxf(T, 0.9)  # gebaggert gibt es keinen schnellen Ball
	l += excess(e, "set") * 10.0
	var spread: float = [0.15, 0.45, 1.2][q]
	if bump_set:
		spread = spread * 1.8 + 0.2
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
		"back":
			role = "OH2"
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


## Was ein Schlag mit diesem Trefferpunkt machen wuerde (ohne Timing-Fehler und Zufall).
## Rechter Stick: oben Topspin, Mitte flach und hart, unten Leger. Wer den Ball rechts
## trifft, schlaegt ihn nach links. Ganz aussen: Cut Shot (kurz diagonal) oder Block-Out.
func attack_shot(team: int, bp: Vector3, contact: Vector2, power: float) -> Dictionary:
	var hl := team_local(team, bp).y
	var res := {"style": "spike", "g": G, "u": lerpf(14.0, 26.0, clampf(power, 0.0, 1.0)), "clear": 0.0}
	var d := 7.8
	var l := hl
	if contact.y < -0.35:
		res.style = "tip"
		d = lerpf(1.5, 3.2, clampf(contact.y + 1.0, 0.0, 1.0) / 0.65)
		l = _aim_lateral(hl, contact.x, 4.0)
		res.clear = 3.6
	elif absf(contact.x) > 0.85:
		var toward := -signf(contact.x)  # Richtung (lokal), in die der Ball fliegt
		if absf(hl) > 1.5 and toward == signf(hl) and contact.y > 0.2:
			res.style = "blockout"  # gegen die Aussenhand, knapp neben die Seitenlinie
			d = 4.0
			l = signf(hl) * 4.9
		else:
			res.style = "cut"
			d = 2.8
			l = toward * 4.0
			res.u = lerpf(11.0, 17.0, power)
	else:
		var top := clampf(contact.y, 0.0, 1.0)
		d = 7.3 - top * 2.2
		l = _aim_lateral(hl, contact.x, 4.8)
		res.g = G * (1.0 + 0.45 * top)
		if top > 0.3:
			res.style = "topspin"
	var target := court_pos(team, Vector2(-d, l))
	target.y = R
	res.target = target
	res.d = d
	res.l = l
	return res


## Seitliches Ziel: Stick in der Mitte = gerade (Linie), voll zur Seite = bis zur
## Seitenlinie. Nach aussen geht es bis knapp ins Aus (out_edge), nach innen bis 4 m.
func _aim_lateral(hl: float, x: float, out_edge: float) -> float:
	var base := clampf(hl, -3.9, 3.9)
	var dir := -signf(x)
	if dir == 0.0:
		return base
	var outward := absf(base) > 0.5 and dir == signf(base)
	var extreme := dir * (out_edge if outward else 4.0)
	return lerpf(base, extreme, clampf(absf(x) / 0.85, 0.0, 1.0))


func _do_attack(o: Opp, q: int, e: float) -> void:
	var bp := ball.position
	_hitter[o.team] = null
	var info := attack_shot(o.team, bp, o.rs, o.power)
	last_shot_style = info.style
	var g: float = info.g
	ball_g = g
	if info.style == "tip":
		ball_vel = Ballistics.launch_over_net(bp, info.target, info.clear, 4.0, 10.0, g)
		last_action = "tip"
		return
	var d: float = info.d
	var l: float = info.l
	var u: float = info.u
	# Zu frueh: Ball fliegt zu lang (Aus). Zu spaet: Ball geht zu steil (Netz).
	var x := excess(e, "attack", o.win_scale)
	if x < 0.0:
		d += -x * 45.0
	else:
		d -= x * 25.0
	if q == Q.GOOD:
		u *= 0.88
		l += rng.randf_range(-0.8, 0.8)
	elif q == Q.WEAK:
		u *= 0.62
		l += rng.randf_range(-1.5, 1.5)
		d += rng.randf_range(-1.0, 1.0)
	if o.over > OVERCHARGE:
		var k := (o.over - OVERCHARGE) * 4.0
		l += rng.randf_range(-k, k)
		d += rng.randf_range(0.0, k)
	l += rng.randf_range(-0.3, 0.3) * o.rs.length()
	var target := court_pos(o.team, Vector2(-d, l))
	target.y = R
	var vel := Ballistics.launch_with_speed(bp, target, u, g)
	if q != Q.WEAK or rng.randf() < 1.0 - 0.4 * cfg.unit("faults"):
		# Gute Angreifer passen die Flugbahn an, damit der Ball ueber das Netz geht.
		while _net_cross_y(bp, vel) < NET_H + 0.15 and d < 8.6:
			d += 0.5
			target = court_pos(o.team, Vector2(-d, l))
			target.y = R
			vel = Ballistics.launch_with_speed(bp, target, u, g)
		if _net_cross_y(bp, vel) < NET_H + 0.15:
			vel = Ballistics.launch_over_net(bp, target, NET_H + 0.25, 6.0, u, g)
		# ... und schlagen von aussen schraeg ins Feld, damit der Ball zwischen den Antennen kreuzt.
		var tries := 0
		while absf(_net_cross_z(bp, vel)) > HALF_W - 0.25 and tries < 12:
			tries += 1
			l *= 0.8
			l -= signf(bp.z) * 0.4 * (1.0 if o.team == 0 else -1.0)
			target = court_pos(o.team, Vector2(-d, l))
			target.y = R
			vel = Ballistics.launch_with_speed(bp, target, u, g)
	ball_vel = vel
	last_action = "attack"
	_slow_tail_until = clock + 0.12
	stats["Schlag " + info.style] = stats.get("Schlag " + info.style, 0) + 1
	if o.human:
		big_hit.emit(1.0 if q == Q.PERFECT and o.power > 0.75 else 0.4)


## Hoehe, in der der Ball die Netzebene kreuzt (99, wenn er nicht hinkommt).
func _net_cross_y(from: Vector3, vel: Vector3) -> float:
	if absf(vel.x) < 0.01 or signf(vel.x) == signf(from.x):
		return 99.0
	var t := -from.x / vel.x
	return from.y + vel.y * t - 0.5 * ball_g * t * t


func _net_cross_z(from: Vector3, vel: Vector3) -> float:
	if absf(vel.x) < 0.01:
		return from.z
	return from.z + vel.z * (-from.x / vel.x)


func _do_free(o: Opp, q: int) -> void:
	var target := court_pos(o.team, Vector2(-rng.randf_range(4.5, 7.0), rng.randf_range(-2.5, 2.5)))
	target.y = R
	var clear := NET_H + (1.5 if q != Q.WEAK else 0.5)
	ball_vel = Ballistics.launch_over_net(ball.position, target, clear, 5.0, 11.0)
	last_action = "free"


# ---------------------------------------------------------------- Ballflug

func _step_ball(delta: float) -> void:
	var prev := ball.position
	var res := Ballistics.advance(prev, ball_vel, delta, ball_g)
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
			ball_g = G
			flutter = 0.0
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
	var hit_pl: VPlayer = null
	var hit_dz := 0.0
	var in_block := 0
	for pl in players[def]:
		if not pl.airborne or not (pl.role in FRONT_ROW):
			continue
		var top: float = pl.block_top()
		if c.y > top + R or c.y < top - 0.75:
			continue
		var dz: float = c.z - pl.hands_z()
		if absf(dz) < 1.4:
			in_block += 1
		if absf(dz) > 0.5 + R:
			continue
		if hit_pl == null or absf(dz) < absf(hit_dz):
			hit_pl = pl
			hit_dz = dz
	if hit_pl == null:
		return false
	var pl := hit_pl
	var top2: float = pl.block_top()
	# Ueber das Netz greifen ist stark, aber riskant.
	if pl.hand_reach > 0.0 and rng.randf() < 0.1 * cfg.unit("faults"):
		popup(pl, "Netz!", Q_COLOR[Q.MISS])
		last_touch_team = def
		_end_rally(1 - def, "Netzberührung beim Block")
		return true
	var s_att := signf(prev.x)
	ball_g = G
	# Wie gut steht der Block? Haende ganz oben, ueber das Netz gegriffen, mehrere Blocker.
	# Der Mensch blockt immer gleich stark; die Staerke des KI-Blocks stellt "Gegner-Block" ein.
	var base := 0.33 if def == human_team else lerpf(0.08, 0.32, cfg.unit("ai_block"))
	var stuff_p := base + (0.2 if pl.hand_reach > 0.0 else 0.0) + (0.15 if in_block >= 2 else 0.0)
	if pl.jump_h < 0.6:
		stuff_p *= 0.4
	var out_p := 0.85 if last_shot_style == "blockout" else 0.4
	if absf(hit_dz) > 0.32 and rng.randf() < out_p:
		# Ball streift die Aussenhand: springt seitlich weg, oft ins Aus (Block-Aus).
		ball.position = Vector3(-s_att * (R + 0.05), c.y, c.z)
		ball_vel = Vector3(ball_vel.x * 0.5, rng.randf_range(1.5, 4.0), signf(hit_dz) * rng.randf_range(3.0, 7.0))
		possession = def
		touches = 0
		last_action = "block_touch"
		popup(pl, "Blockberührung", Q_COLOR[Q.GOOD])
	elif absf(hit_dz) < 0.3 and c.y < top2 - 0.25 + pl.hand_reach and last_action == "attack" and rng.randf() < stuff_p:
		# Kompletter Block: Ball wird hart nach unten auf die Seite des Angreifers gedrueckt.
		ball.position = Vector3(s_att * (R + 0.05), c.y, c.z)
		ball_vel = Vector3(s_att * rng.randf_range(1.2, 3.5), -rng.randf_range(3.5, 6.0), ball_vel.z * 0.2 + rng.randf_range(-1.0, 1.0))
		possession = 1 - def
		touches = 0
		last_action = "block"
		var txt := "BLOCK!"
		if in_block >= 3:
			txt = "DREIERBLOCK!"
		elif in_block == 2:
			txt = "DOPPELBLOCK!"
		popup(pl, txt, Q_COLOR[Q.PERFECT])
		stats[txt] = stats.get(txt, 0) + 1
		if def == human_team:
			big_hit.emit(1.0 if in_block >= 2 else 0.7)
			if in_block >= 2:
				_hitstop_left = 0.45
	elif last_action == "attack" and ball_vel.length() > 17.0 and rng.randf() < 0.55:
		# Harter Schlag: Ball geht durch den Block, wird etwas gebremst, bleibt aber schnell.
		ball.position = Vector3(-s_att * (R + 0.05), c.y, c.z)
		ball_vel = Vector3(ball_vel.x * rng.randf_range(0.55, 0.75), ball_vel.y * 0.5 + rng.randf_range(-1.0, 1.5), ball_vel.z * 0.6 + rng.randf_range(-2.0, 2.0))
		possession = def
		touches = 0
		last_action = "block_touch"
		popup(pl, "Durch den Block!", Q_COLOR[Q.WEAK])
		stats["Durch den Block"] = stats.get("Durch den Block", 0) + 1
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
	blockers = [[], []]
	_hitter = [null, null]
	charging = false
	flutter = 0.0
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
		if opp != null and opp.team != t and opp.kind == "attack" and not blockers[t].is_empty():
			var list: Array = blockers[t]
			var prim: VPlayer = list[0]
			for pl in list:
				pl.run_speed = 4.5
			prim.target = Vector3(side_of(t) * 0.45, 0.0, clampf(opp.point.z + (block_err[t] if t != human_team else 0.0), -4.1, 4.1))
			# Helfer schliessen neben dem Hauptblocker (der Mensch kann ihn verschieben).
			for i in range(1, list.size()):
				var dir: float = block_dirs[t][i]
				if dir == 0.0:
					dir = 1.0 if i == 1 else -1.0
				var z := clampf(prim.position.z + dir * 0.85, -4.3, 4.3)
				list[i].target = Vector3(side_of(t) * 0.45, 0.0, z)
			for pl in players[t]:
				if not (pl in list) and pl.role in FRONT_ROW:
					var lane: Vector2 = LAYOUT["defense"][pl.role]
					pl.target = court_pos(t, Vector2(3.0, lane.y))
	# Sprungaufschlag: Anlauf unter den Ball und Absprung hinter der Grundlinie.
	if phase == Phase.TOSS and serve_kind == 1 and not serve_done:
		var srv := server()
		var bx := ball.position.x - side_of(serving_team) * 0.2
		bx = side_of(serving_team) * maxf(absf(bx), HALF_L + 0.1)
		srv.target = Vector3(bx, 0.0, ball.position.z)
		srv.run_speed = 4.0
		if clock >= serve_ideal - JUMP_RISE and not srv.has_jumped:
			srv.jump()
	if opp != null and not opp.done:
		var pl := opp.player
		var p := Vector3(opp.point.x, 0.0, opp.point.z)
		if opp.kind == "attack":
			var t_jump := opp.t - JUMP_RISE
			var t_go := t_jump - flat_dist(pl.position, p) / pl.run_speed - 0.05
			pl.target = p if clock >= t_go else p + Vector3(side_of(opp.team) * 2.2, 0.0, 0.0)
			if clock >= t_jump and not pl.has_jumped:
				pl.jump()
				pl.block_pose = false
				if not opp.human:
					_ai_attack_choice(opp)  # Entscheidung faellt im Absprung
			# Schulter zeigt die Schlagrichtung an, damit der Blocker lesen kann.
			if pl.airborne:
				var info := attack_shot(opp.team, opp.point, opp.rs, opp.power)
				var tz: float = (info.target as Vector3).z
				pl.lean = clampf((tz - pl.position.z) / 4.0, -1.0, 1.0)
		elif opp.human and not assist:
			pl.target = pl.position
		elif opp.no_reach:
			pl.target = opp.start_pos + (p - opp.start_pos).limit_length(opp.max_run)
		else:
			pl.target = p
	for t in 2:
		for pl in players[t]:
			pl.tick(delta)


## Zeitlupe und Kamera: In jeder Spielphase gilt das eingestellte Tempo (Menue), die
## Kamera rueckt beim eigenen Aufschlag, Angriff und Block naeher.
func _update_time_and_camera(real_delta: float) -> void:
	var want := 1.0
	cam_mode = ""
	cam_subject = null
	if human_team >= 0 and not autoplay:
		if (phase == Phase.PRE_SERVE or phase == Phase.TOSS) and serving_team == human_team and not serve_done:
			cam_mode = "serve"
			cam_subject = server()
			if phase == Phase.TOSS and ((serve_kind == 1 and cam_subject.airborne) or (serve_kind == 0 and ball_vel.y < 1.5)):
				want = minf(want, cfg.time_scale("slow_serve"))
		elif phase == Phase.RALLY and opp != null and opp.kind == "attack":
			if opp.team == human_team:
				cam_mode = "attack"
				cam_subject = opp.player
				if opp.player.airborne and (not opp.done or clock < _slow_tail_until):
					want = minf(want, cfg.time_scale("slow_attack"))
			elif not blockers[human_team].is_empty():
				cam_mode = "block"
				cam_subject = blockers[human_team][0]
				if (opp.player.airborne or cam_subject.airborne) and not opp.done:
					want = minf(want, cfg.time_scale("slow_block"))
		elif phase == Phase.RALLY and opp != null and not opp.done and opp.human:
			var remain := opp.t - clock
			if remain < 0.45 and remain > -0.15:
				want = minf(want, cfg.time_scale("slow_set" if opp.kind == "set" else "slow_receive"))
		if phase == Phase.RALLY and last_action == "attack" and clock < _slow_tail_until:
			if opp == null or opp.team != human_team:
				want = minf(want, cfg.time_scale("slow_block"))
	if not slowmo_on:
		want = 1.0
	if _hitstop_left > 0.0:
		_hitstop_left -= real_delta
		want = minf(want, SLOW)
	if not zoom_on:
		cam_mode = ""
	if phase != Phase.RALLY and phase != Phase.TOSS:
		want = 1.0
	Engine.time_scale = clampf(want, 0.1, 1.0)


func _update_visuals() -> void:
	# Flatterball: der Ball wackelt sichtbar, die echte Flugbahn bleibt berechenbar.
	var wob := Vector3.ZERO
	if flutter > 0.0 and last_action == "serve" and opp != null:
		var total := maxf(opp.t - serve_time, 0.1)
		var k := clampf((clock - serve_time) / total, 0.0, 1.0)
		var env := sin(k * PI)
		wob = Vector3(0.0, sin(clock * 11.0) * 0.06, sin(clock * 7.3 + 1.0)) * flutter * env
	ball_mesh.position = wob
	var vis := ball.position + wob
	ball_shadow.position = Vector3(vis.x, 0.008, vis.z)
	var k2 := clampf(1.0 - ball.position.y / 12.0, 0.4, 1.0)
	ball_shadow.scale = Vector3(k2, 1.0, k2)
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
		var near: bool = absf(opp.t - clock) <= windows(opp.kind)[0] * opp.win_scale
		_ring_timer_mat.albedo_color = Color(0.3, 1.0, 0.3) if near else Color(1.0, 0.85, 0.1)
		# Laufhilfe: gruen = Pritschen geht, orange = lieber baggern.
		var tint := Color(1, 1, 1, 0.9)
		if assist and opp.kind != "attack":
			tint = Color(0.4, 1.0, 0.5, 0.95) if opp.speed <= OVER_OK else Color(1.0, 0.55, 0.15, 0.95)
		_ring_target_mat.albedo_color = tint

	var aim_vis := false
	preview_valid = false
	if human_team >= 0:
		if (phase == Phase.PRE_SERVE or phase == Phase.TOSS) and serving_team == human_team and not serve_done:
			var sa := serve_aim
			if serve_style(serve_contact) == "short":
				sa.x = minf(sa.x, 3.2)
			sa.y -= serve_contact.x * 1.5
			_aim_marker.position = court_pos(human_team, Vector2(-sa.x, sa.y)) + Vector3(0, 0.03, 0)
			aim_vis = true
		elif show_ring and opp.kind == "attack":
			var info := attack_shot(opp.team, opp.point, rs, clampf(charge if charging else 0.8, 0.15, 1.0))
			preview_target = info.target
			preview_valid = true
			_aim_marker.position = Vector3(preview_target.x, 0.03, preview_target.z)
			aim_vis = true
	_aim_marker.visible = aim_vis
	_draw_block_shadow()


## Blockschatten: der Bereich hinter dem Block, den der Block vom Angreifer aus abdeckt.
func _draw_block_shadow() -> void:
	_shadow_mesh.clear_surfaces()
	if human_team < 0 or not assist or phase != Phase.RALLY or opp == null or opp.done or opp.kind != "attack":
		return
	var def := 1 - opp.team
	if blockers[def].is_empty():
		return
	var P := opp.point
	var s := side_of(def)
	_shadow_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in blockers[def]:
		var top: float = b.block_top() if b.airborne else VPlayer.BLOCK_REACH + 0.8
		var zc: float = b.hands_z()
		var pts: Array = []
		for dz in [-0.3, 0.3]:
			var E := Vector3(s * 0.25, top, zc + dz)
			var far: Vector3
			if top >= P.y - 0.05:
				far = P + (E - P) * 20.0
			else:
				far = P + (E - P) * (P.y / (P.y - top))
			# Auf das Feld des Verteidigers begrenzen.
			if absf(far.x) > HALF_L:
				var f := (HALF_L - absf(E.x)) / maxf(absf(far.x - E.x), 0.01)
				far = E + (far - E) * f
			pts.append(Vector3(E.x, 0.012, E.z))
			pts.append(Vector3(far.x, 0.012, far.z))
		var a: Vector3 = pts[0]
		var af: Vector3 = pts[1]
		var bq: Vector3 = pts[2]
		var bf: Vector3 = pts[3]
		for v in [a, af, bf, a, bf, bq]:
			_shadow_mesh.surface_add_vertex(v)
	_shadow_mesh.surface_end()


## Kurzer Hinweis, was der Mensch gerade tun kann.
func hint() -> String:
	match phase:
		Phase.INTRO:
			return ""
		Phase.PRE_SERVE:
			if serving_team == human_team:
				return "Aufschlag (%s): Ziel linker Stick/WASD · Trefferpunkt rechter Stick/Maus · LB/RB oder 1/2 Stand/Sprung · R2/E halten, loslassen = schlagen" % serve_style_text(serve_kind, serve_contact)
		Phase.TOSS:
			if serving_team == human_team and not serve_done:
				return "R2 / E halten zum Aufladen, loslassen, wenn der Ball oben ist"
		Phase.RALLY:
			if opp != null and not opp.done and opp.team == human_team:
				match opp.kind:
					"pass":
						return "Annahme: A/Leertaste baggern · X/Q pritschen (Ring grün = Pritschen geht)"
					"dig":
						return "Abwehr! A/Leertaste baggern, wenn sich der Ring schließt"
					"set":
						return "Zuspiel: Stick links Außen · rechts Diagonal · vor Mitte · zurück Hinterfeld, dann X/Q pritschen"
					"attack":
						return "Angriff: R2/E halten und beim Treffpunkt loslassen · Trefferpunkt rechter Stick/Maus (oben Topspin, unten Leger)"
					"free":
						return "Ball rüberspielen: X/Q pritschen oder A/Leertaste baggern"
			if human_player() != null:
				return "Block: Stick verschiebt den Block · R2/E springen · in der Luft Stick = Hände, nach vorn = übers Netz"
	return ""
