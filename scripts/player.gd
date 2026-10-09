class_name VPlayer
extends Node3D
## Ein Spieler: laeuft zu einem Ziel, springt, hechtet. Gesteuert wird er vom Match
## (KI-Laufwege) oder ueber manual_dir vom Menschen. Aussehen: Low-Poly-Figur (figure.gd)
## mit Posen fuer Bereitschaft, Laufen, Baggern, Pritschen, Angriff, Block, Hechten, Jubel.

const G := 9.81
const JUMP_V := 3.96  # ergibt ca. 0,80 m Sprunghoehe
const SPIKE_REACH := 2.45  # Handhoehe im Stand beim Angriff
const BLOCK_REACH := 2.45  # Handhoehe im Stand beim Block
const SKINS := [Color(0.96, 0.8, 0.66), Color(0.9, 0.7, 0.54), Color(0.78, 0.57, 0.4), Color(0.6, 0.42, 0.3), Color(0.42, 0.29, 0.2)]
const HAIRS := [Color(0.15, 0.1, 0.07), Color(0.3, 0.2, 0.12), Color(0.55, 0.38, 0.2), Color(0.85, 0.7, 0.4), Color(0.08, 0.08, 0.08), Color(0.6, 0.3, 0.15)]

var team := 0
var role := ""
var number := 0
var member_id := -1  # Spieler im Kader (TeamRoster)
var slot := 1  # Position 1 bis 6 in der Rotation
var lane := ""  # Angriffsbahn: left, mid, right, back (vom Match gesetzt)
var takeoff_x := 0.0  # Abstand zum Netz beim Absprung
var side := -1.0
var target := Vector3.ZERO
var run_speed := 6.0
var manual_dir := Vector3.ZERO
var jump_h := 0.0
var jump_v := 0.0
var airborne := false
var has_jumped := false
var dive_timer := 0.0
## Block: seitliche Verschiebung der Haende (m, Welt-z) und wie weit sie ueber das Netz greifen.
var hand_shift := 0.0
var hand_reach := 0.0
var block_jump_at := -1.0
var block_pose := false
## Blickrichtung beim Angriff (Welt-z der Schulter), damit der Gegner lesen kann.
var lean := 0.0

## Fuer die Posen, vom Match jedes Bild gesetzt.
var now := 0.0
var look_target := Vector3.ZERO
var alert := false  # Ballwechsel laeuft: Bereitschaftshaltung
var anim_kind := ""  # pass, dig, set, attack, free, serve, serve_hold
var anim_tech := "bump"
var anim_t := -10.0  # Zeitpunkt der Ballberuehrung
var celebrate_until := -10.0

var fig: HumanFigure
var _ring: MeshInstance3D
var _yaw := 0.0
var _run_phase := 0.0
var _run_amt := 0.0
var _last_pos := Vector3.ZERO
var _jersey := Color.WHITE


func setup(p_team: int, p_role: String, _tag_letter: String, p_number: int, color: Color) -> void:
	team = p_team
	role = p_role
	number = p_number
	side = -1.0 if team == 0 else 1.0
	_yaw = -side * PI / 2.0
	fig = HumanFigure.new()
	add_child(fig)
	fig.build(_colors(color), true, number % 3)
	fig.set_number(number, _number_color(color))
	fig.pose(_p_idle())

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.52
	torus.rings = 24
	torus.ring_segments = 6
	_ring.mesh = torus
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(1.0, 0.9, 0.1)
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = rm
	_ring.scale = Vector3(1, 0.12, 1)
	_ring.position.y = 0.02
	_ring.visible = false
	add_child(_ring)
	_last_pos = position


func _colors(jersey: Color) -> Dictionary:
	_jersey = jersey
	var h := hash(team * 1000 + number)
	var shorts := Color(0.08, 0.12, 0.3) if team == 0 else Color(0.95, 0.95, 0.95)
	return {
		"jersey": jersey,
		"shorts": shorts,
		"skin": SKINS[h % SKINS.size()],
		"hair": HAIRS[(h / 7) % HAIRS.size()],
		"shoes": Color(0.97, 0.97, 0.97) if team == 0 else Color(0.15, 0.15, 0.17),
		"socks": Color(0.95, 0.95, 0.95) if team == 0 else jersey.darkened(0.2),
		"trim": Color(1, 1, 1) if team == 0 else Color(0.98, 0.85, 0.2),
	}


func _number_color(jersey: Color) -> Color:
	return Color(0.1, 0.1, 0.12) if jersey.get_luminance() > 0.6 else Color(1, 1, 1)


## Neue Identitaet (Wechsel, Libero): Rolle, Nummer und Trikotfarbe tauschen.
func change_identity(p_role: String, _tag_letter: String, p_number: int, color: Color) -> void:
	role = p_role
	number = p_number
	var c := _colors(color)
	for k in c:
		fig.set_color(k, c[k])
	fig.set_number(number, _number_color(color))


func set_side(s: float) -> void:
	side = s


func reset_state() -> void:
	jump_h = 0.0
	jump_v = 0.0
	airborne = false
	has_jumped = false
	dive_timer = 0.0
	manual_dir = Vector3.ZERO
	hand_shift = 0.0
	hand_reach = 0.0
	block_jump_at = -1.0
	block_pose = false
	lean = 0.0
	anim_kind = ""
	anim_t = -10.0
	_last_pos = position


func jump() -> void:
	if airborne:
		return
	airborne = true
	has_jumped = true
	jump_v = JUMP_V
	takeoff_x = absf(position.x)


func dive() -> void:
	dive_timer = 0.7


func spike_hand() -> float:
	return jump_h + SPIKE_REACH


func block_top() -> float:
	return jump_h + BLOCK_REACH + hand_reach


## Mitte der Blockhaende (Welt-z).
func hands_z() -> float:
	return position.z + hand_shift


func set_controlled(on: bool) -> void:
	_ring.visible = on


func tick(delta: float) -> void:
	if airborne:
		jump_h += jump_v * delta
		jump_v -= G * delta
		if jump_h <= 0.0:
			jump_h = 0.0
			airborne = false
	elif dive_timer <= 0.3:
		if manual_dir.length() > 0.15:
			position += manual_dir.limit_length(1.0) * run_speed * delta
			target = position
		else:
			var to := Vector3(target.x - position.x, 0.0, target.z - position.z)
			var dist := to.length()
			if dist > 0.02:
				position += to / dist * minf(dist, run_speed * delta)
	position.x = clampf(position.x, -13.0, 13.0)
	position.z = clampf(position.z, -8.0, 8.0)
	# Niemand laeuft ueber die Mittellinie.
	if side < 0.0:
		position.x = minf(position.x, -0.15)
	else:
		position.x = maxf(position.x, 0.15)
	if dive_timer > 0.0:
		dive_timer -= delta
	_animate(delta)


# ---------------------------------------------------------------- Posen

func _animate(delta: float) -> void:
	var moved := Vector3(position.x - _last_pos.x, 0.0, position.z - _last_pos.z)
	_last_pos = position
	var speed := moved.length() / maxf(delta, 0.0001)
	_run_amt = lerpf(_run_amt, clampf(speed / 4.5, 0.0, 1.0) if not airborne else 0.0, clampf(delta * 10.0, 0.0, 1.0))
	_run_phase += speed * delta * 2.6

	# Blickrichtung: zum Ball, beim Block und Angriff zum Netz.
	var face := look_target - position
	if block_pose or (anim_kind == "attack" and (airborne or anim_t - now < 0.8)) or face.length() < 0.3:
		face = Vector3(-side, 0.0, 0.0)
	if not alert and celebrate_until < now:
		face = Vector3(-side, 0.0, 0.0)
	face.y = 0.0
	var want := atan2(-face.x, -face.z)
	_yaw = lerp_angle(_yaw, want, clampf(delta * 8.0, 0.0, 1.0))
	fig.rotation.y = _yaw

	var p := _target_pose()
	fig.pose(p, clampf(delta * 16.0, 0.0, 1.0))
	# Huefthoehe so, dass die Fuesse am Boden bleiben (Knie gebeugt = tiefer).
	var legs := 0.0
	for sd in ["l", "r"]:
		var a: float = fig.j["hip_" + sd].rotation.x
		var b: float = fig.j["kn_" + sd].rotation.x
		legs = maxf(legs, 0.46 * cos(a) + 0.44 * cos(a + b))
	var drop := 0.9 - legs
	fig.root_node.position.y = jump_h - drop
	# Hechten: ganzer Koerper kippt nach vorn.
	var tilt := 0.0
	if dive_timer > 0.0:
		var k := clampf(dive_timer / 0.7, 0.0, 1.0)
		tilt = -1.15 * sin(k * PI)
	fig.root_node.rotation.x = lerpf(fig.root_node.rotation.x, tilt, clampf(delta * 14.0, 0.0, 1.0))
	fig.root_node.position.y -= absf(fig.root_node.rotation.x) * 0.2


func _arm(p: Dictionary, sd: String, fwd: float, out: float, elbow: float, wrist := 0.0, twist := 0.0) -> void:
	var s := -1.0 if sd == "l" else 1.0
	p["sh_" + sd] = Vector3(fwd, twist * s, out * s)
	p["el_" + sd] = Vector3(elbow, 0.0, 0.0)
	p["wr_" + sd] = Vector3(wrist, 0.0, 0.0)


func _leg(p: Dictionary, sd: String, thigh: float, knee: float, spread := 0.0) -> void:
	var s := -1.0 if sd == "l" else 1.0
	p["hip_" + sd] = Vector3(thigh, 0.0, spread * s)
	p["kn_" + sd] = Vector3(-knee, 0.0, 0.0)
	p["an_" + sd] = Vector3(-(thigh - knee), 0.0, 0.0)


func _p_idle() -> Dictionary:
	var p := {"chest": Vector3(-0.04, 0, 0), "head": Vector3(0.05, 0, 0)}
	_arm(p, "l", 0.1, 0.1, 0.25)
	_arm(p, "r", 0.1, 0.1, 0.25)
	_leg(p, "l", 0.1, 0.15, 0.05)
	_leg(p, "r", 0.1, 0.15, 0.05)
	return p


func _p_ready() -> Dictionary:
	var p := {"hips": Vector3(-0.15, 0, 0), "chest": Vector3(-0.3, 0, 0), "head": Vector3(0.35, 0, 0)}
	_arm(p, "l", 0.65, 0.2, 0.9)
	_arm(p, "r", 0.65, 0.2, 0.9)
	_leg(p, "l", 0.6, 1.0, 0.12)
	_leg(p, "r", 0.6, 1.0, 0.12)
	return p


func _p_run(a: float) -> Dictionary:
	var ph := _run_phase
	var p := {"hips": Vector3(-0.1 * a, 0, 0), "chest": Vector3(-0.25 * a, 0, 0), "head": Vector3(0.2 * a, 0, 0)}
	var sl := sin(ph)
	_leg(p, "l", 0.25 + sl * 0.7, 0.35 + maxf(0.0, -sl) * 1.1)
	_leg(p, "r", 0.25 - sl * 0.7, 0.35 + maxf(0.0, sl) * 1.1)
	_arm(p, "l", -sl * 0.7 + 0.2, 0.12, 1.4)
	_arm(p, "r", sl * 0.7 + 0.2, 0.12, 1.4)
	return p


func _p_bump() -> Dictionary:
	var p := {"hips": Vector3(-0.25, 0, 0), "chest": Vector3(-0.35, 0, 0), "head": Vector3(0.45, 0, 0)}
	_arm(p, "l", 1.0, -0.22, 0.0, 0.0)
	_arm(p, "r", 1.0, -0.22, 0.0, 0.0)
	_leg(p, "l", 0.8, 1.25, 0.15)
	_leg(p, "r", 0.8, 1.25, 0.15)
	return p


func _p_set() -> Dictionary:
	var p := {"chest": Vector3(0.05, 0, 0), "head": Vector3(0.55, 0, 0)}
	_arm(p, "l", 2.5, 0.45, 1.5, -0.4)
	_arm(p, "r", 2.5, 0.45, 1.5, -0.4)
	_leg(p, "l", 0.35, 0.55, 0.1)
	_leg(p, "r", 0.35, 0.55, 0.1)
	return p


## Angriff in der Luft: rel = Zeit relativ zum Treffpunkt (negativ = davor).
func _p_spike(rel: float) -> Dictionary:
	var p := {}
	var swing := clampf((rel + 0.06) / 0.16, 0.0, 1.0)
	p["chest"] = Vector3(lerpf(0.25, -0.4, swing), lean * 0.35, 0)
	p["head"] = Vector3(0.45, 0, 0)
	_arm(p, "r", lerpf(2.95, 0.7, swing), lerpf(0.45, 0.15, swing), lerpf(2.0, 0.2, swing))
	_arm(p, "l", lerpf(2.6, 0.9, swing), 0.15, lerpf(0.2, 0.6, swing))
	_leg(p, "l", lerpf(0.5, 0.7, swing), lerpf(1.1, 0.8, swing), 0.1)
	_leg(p, "r", lerpf(0.15, 0.6, swing), lerpf(0.9, 0.7, swing), 0.1)
	return p


## Anlauf vor dem Absprung: Arme weit nach hinten, tief in die Knie.
func _p_approach() -> Dictionary:
	var p := {"hips": Vector3(-0.3, 0, 0), "chest": Vector3(-0.35, 0, 0), "head": Vector3(0.5, 0, 0)}
	_arm(p, "l", -1.0, 0.15, 0.2)
	_arm(p, "r", -1.0, 0.15, 0.2)
	_leg(p, "l", 0.8, 1.3, 0.1)
	_leg(p, "r", 0.8, 1.3, 0.1)
	return p


func _p_block() -> Dictionary:
	# Haende seitlich verschieben: Welt-z in die lokale Seitenrichtung umrechnen.
	var local_shift := -side * hand_shift
	var fwd := 3.05 - hand_reach * 1.2
	var p := {"chest": Vector3(-0.05, 0, local_shift * 0.25), "head": Vector3(0.25, 0, 0)}
	_arm(p, "l", fwd, 0.14 - local_shift * 0.5, 0.05, -0.3)
	_arm(p, "r", fwd, 0.14 + local_shift * 0.5, 0.05, -0.3)
	if airborne:
		_leg(p, "l", 0.15, 0.3, 0.1)
		_leg(p, "r", 0.15, 0.3, 0.1)
	else:
		_arm(p, "l", 2.3, 0.25, 1.3, -0.3)
		_arm(p, "r", 2.3, 0.25, 1.3, -0.3)
		_leg(p, "l", 0.45, 0.8, 0.15)
		_leg(p, "r", 0.45, 0.8, 0.15)
	return p


func _p_dive() -> Dictionary:
	var p := {"chest": Vector3(-0.1, 0, 0), "head": Vector3(0.7, 0, 0)}
	_arm(p, "l", 2.4, 0.15, 0.0)
	_arm(p, "r", 2.4, 0.15, 0.0)
	_leg(p, "l", -0.2, 0.3)
	_leg(p, "r", 0.3, 0.6)
	return p


func _p_serve(rel: float, jump_serve: bool) -> Dictionary:
	if airborne:
		return _p_spike(rel)
	if jump_serve and rel < -0.25:
		return _p_approach() if rel > -0.7 else _p_run(maxf(_run_amt, 0.4))
	var p := {"chest": Vector3(0.1, 0, 0), "head": Vector3(0.6, 0, 0)}
	var swing := clampf((rel + 0.06) / 0.16, 0.0, 1.0)
	_arm(p, "l", lerpf(2.8, 1.0, swing), 0.1, 0.1)
	_arm(p, "r", lerpf(2.9, 1.0, swing), lerpf(0.5, 0.1, swing), lerpf(1.9, 0.2, swing))
	_leg(p, "l", 0.35, 0.2)
	_leg(p, "r", -0.15, 0.25)
	return p


func _p_serve_hold() -> Dictionary:
	var p := {"chest": Vector3(-0.15, 0, 0), "head": Vector3(0.2, 0, 0)}
	_arm(p, "l", 1.0, 0.0, 0.7)
	_arm(p, "r", 0.3, 0.15, 0.5)
	_leg(p, "l", 0.25, 0.25)
	_leg(p, "r", -0.1, 0.2)
	return p


func _p_celebrate() -> Dictionary:
	var pump := sin(now * 9.0 + number) * 0.25
	var p := {"chest": Vector3(0.15, 0, 0), "head": Vector3(0.5, 0, 0)}
	_arm(p, "l", 2.7 + pump, 0.55, 0.7)
	_arm(p, "r", 2.7 - pump, 0.55, 0.7)
	_leg(p, "l", 0.1, 0.15, 0.1)
	_leg(p, "r", 0.1, 0.15, 0.1)
	return p


static func _mix(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	if w <= 0.0:
		return a
	if w >= 1.0:
		return b
	var out := {}
	for k in HumanFigure.JOINTS:
		out[k] = (a.get(k, Vector3.ZERO) as Vector3).lerp(b.get(k, Vector3.ZERO), w)
	return out


func _target_pose() -> Dictionary:
	if dive_timer > 0.0:
		return _p_dive()
	if celebrate_until > now:
		return _p_celebrate()
	var rel := now - anim_t
	if anim_kind == "serve_hold":
		return _p_serve_hold()
	if anim_kind == "serve" and rel < 0.5:
		return _p_serve(rel, anim_tech == "jump")
	if block_pose:
		return _p_block()
	if anim_kind == "attack" and rel < 0.5:
		if airborne:
			return _p_spike(rel)
		if rel > -0.9:
			return _p_approach()
	var base := _p_ready() if alert else _p_idle()
	if _run_amt > 0.05:
		base = _mix(base, _p_run(_run_amt), clampf(_run_amt * 1.6, 0.0, 1.0))
	if airborne:
		base = _mix(base, _p_spike(-0.5), 0.6)
	if anim_kind in ["pass", "dig", "set", "free"] and rel > -0.6 and rel < 0.45:
		var tech := _p_set() if anim_kind == "set" and anim_tech == "over" else (_p_set() if anim_tech == "over" else _p_bump())
		var w := clampf((rel + 0.6) / 0.35, 0.0, 1.0) * clampf((0.45 - rel) / 0.2, 0.0, 1.0)
		base = _mix(base, tech, w)
	return base


## Zustand fuer die Wiederholung aufzeichnen und wieder herstellen.
func snapshot() -> Array:
	return [position, jump_h, airborne, block_pose, hand_shift, hand_reach, lean, dive_timer, fig.capture(), fig.rotation.y]


func restore(s: Array) -> void:
	position = s[0]
	jump_h = s[1]
	airborne = s[2]
	block_pose = s[3]
	hand_shift = s[4]
	hand_reach = s[5]
	lean = s[6]
	dive_timer = s[7]
	fig.apply(s[8])
	fig.rotation.y = s[9]
	_yaw = s[9]
	_last_pos = position
