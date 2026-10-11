class_name VPlayer
extends Node3D
## Ein Spieler: laeuft zu einem Ziel, springt, hechtet. Gesteuert wird er vom Match
## (KI-Laufwege) oder ueber manual_dir vom Menschen. Aussehen: Low-Poly-Figur (figure.gd)
## mit Posen fuer Bereitschaft, Laufen, Baggern, Pritschen, Angriff, Block, Hechten, Jubel.

const G := 9.81
const JUMP_V := 3.96  # ergibt ca. 0,80 m Sprunghoehe
const SPIKE_REACH := 2.45  # Handhoehe im Stand beim Angriff
const BLOCK_REACH := 2.45  # Handhoehe im Stand beim Block
const SKINS := [Color(0.9, 0.74, 0.62), Color(0.86, 0.66, 0.52), Color(0.74, 0.55, 0.41), Color(0.58, 0.42, 0.31), Color(0.42, 0.3, 0.22)]
const HAIRS := [Color(0.17, 0.12, 0.09), Color(0.3, 0.2, 0.13), Color(0.46, 0.33, 0.2), Color(0.72, 0.6, 0.4), Color(0.1, 0.1, 0.1), Color(0.5, 0.29, 0.17)]

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
var prep := ""  # gehaltene Taste: bump oder over (Vorbereitungshaltung)
var celebrate_until := -10.0
## Ballkontakt (vom Match gesetzt): Ballmitte beim Kontakt und der Punkt, wohin gespielt wird.
## Beim Kontakt zielen Haende und Unterarme genau auf contact_pt (siehe _contact_ik).
var contact_pt := Vector3.ZERO
var contact_aim := Vector3.ZERO
var contact_on := false
var net_x := 0.0  # Lage des Netzes (x), nur zum Testen anders

var fig: HumanFigure
var _ring: MeshInstance3D
var _yaw := 0.0
var _run_phase := 0.0
var _run_amt := 0.0
var _last_pos := Vector3.ZERO
var _jersey := Color.WHITE
var _move_fwd := 1.0
var _move_side := 0.0
var _was_air := false
var _takeoff_t := -10.0
var _land_t := -10.0
var _stiff := 20.0
var _root_y := 0.0


func setup(p_team: int, p_role: String, _tag_letter: String, p_number: int, color: Color) -> void:
	team = p_team
	role = p_role
	number = p_number
	side = -1.0 if team == 0 else 1.0
	_yaw = -side * PI / 2.0
	fig = HumanFigure.new()
	add_child(fig)
	var h := hash(team * 1000 + number)
	fig.build(_colors(color), true, (h / 13) % HumanFigure.HAIR_STYLES, false, 1.04 + 0.07 * float((h / 31) % 10) / 9.0)
	fig.set_number(number, _number_color(color), (Teams.playing()[team] as TeamStyle).number)
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


## Farben aus dem Trikot des Teams (teams/*.tres), Haut und Haare je Spieler verschieden.
func _colors(jersey: Color) -> Dictionary:
	_jersey = jersey
	var h := hash(team * 1000 + number)
	var c: Dictionary = (Teams.playing()[team] as TeamStyle).colors(role == "L")
	c["skin"] = SKINS[h % SKINS.size()]
	c["hair"] = HAIRS[(h / 7) % HAIRS.size()]
	return c


func _number_color(_jersey_color: Color) -> Color:
	return (Teams.playing()[team] as TeamStyle).number_color(role == "L")


## Neue Identitaet (Wechsel, Libero): Rolle, Nummer und Trikotfarbe tauschen.
func change_identity(p_role: String, _tag_letter: String, p_number: int, color: Color) -> void:
	role = p_role
	number = p_number
	var c := _colors(color)
	for k in c:
		fig.set_color(k, c[k])
	fig.set_number(number, _number_color(color), (Teams.playing()[team] as TeamStyle).number)


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
	contact_on = false
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
	var k := clampf(delta * 8.0, 0.0, 1.0)
	_run_amt = lerpf(_run_amt, clampf(speed / 4.5, 0.0, 1.0) if not airborne else 0.0, k)
	# Laufrichtung relativ zur Blickrichtung: vorwaerts, rueckwaerts oder seitlich (Nachstellschritt).
	if speed > 0.3:
		var loc := moved.rotated(Vector3.UP, -_yaw) / moved.length()
		_move_fwd = lerpf(_move_fwd, -loc.z, k)
		_move_side = lerpf(_move_side, loc.x, k)
	# Schrittlaenge ca. 1,8 m pro Doppelschritt, damit die Fuesse nicht rutschen.
	_run_phase += speed * delta * 3.5
	if airborne and not _was_air:
		_takeoff_t = now
	if _was_air and not airborne:
		_land_t = now
	_was_air = airborne

	# Blickrichtung: zum Ball, beim Block, Angriff und Aufschlag zum Netz (der Aufschlaeger
	# laeuft unter dem Ball durch und darf sich dabei nicht zum Ball umdrehen).
	var face := look_target - position
	var serving := anim_kind == "serve_hold" or (anim_kind == "serve" and now - anim_t < 0.6)
	if block_pose or serving or (anim_kind == "attack" and (airborne or anim_t - now < 0.8)) or face.length() < 0.3:
		face = Vector3(-side, 0.0, 0.0)
	if not alert and celebrate_until < now:
		face = Vector3(-side, 0.0, 0.0)
	face.y = 0.0
	# Beim Zuspiel dreht sich der Koerper zum Ziel (Schultern quer zur Spielrichtung).
	var turn := 7.0
	var crel := now - anim_t
	if contact_on and anim_kind in ["pass", "dig", "set", "free"] and crel > -0.45 and crel < 0.25 and dive_timer <= 0.0:
		var av := contact_aim - position
		av.y = 0.0
		if av.length() > 0.3:
			var cur := face.normalized() if face.length() > 0.01 else av.normalized()
			face = cur.lerp(av.normalized(), smoothstep(-0.45, -0.1, crel))
			turn = 14.0
	var want := atan2(-face.x, -face.z)
	_yaw = lerp_angle(_yaw, want, clampf(delta * turn, 0.0, 1.0))
	fig.rotation.y = _yaw

	_stiff = 20.0
	var p := _target_pose()
	fig.pose_spring(p, delta, _stiff)
	# Hechten: ganzer Koerper kippt nach vorn.
	var tilt := 0.0
	if dive_timer > 0.0:
		# Ablauf: nach vorn abdruecken, flach auf den Bauch rutschen, wieder aufstehen.
		var kd := 1.0 - clampf(dive_timer / 0.7, 0.0, 1.0)
		tilt = -1.45 * smoothstep(0.0, 0.35, kd) * (1.0 - smoothstep(0.7, 1.0, kd))
	fig.root_node.rotation.x = lerpf(fig.root_node.rotation.x, tilt, clampf(delta * 12.0, 0.0, 1.0))
	# Hoehe: am Boden setzt der tiefste Koerperpunkt genau auf, in der Luft traegt die Sprunghoehe.
	# So sinkt niemand in den Boden ein, egal wie Knie und Huefte gebeugt sind.
	fig.root_node.position.y = 0.0
	var low := fig.lowest_point(dive_timer > 0.0)
	var y := -low
	if airborne:
		y = maxf(jump_h, -fig.lowest_point(false))
	_root_y = maxf(lerpf(_root_y, y, clampf(delta * 25.0, 0.0, 1.0)), -low)
	fig.root_node.position.y = _root_y
	_contact_ik()


## Ballkontakt wie im echten Spiel: im Kontaktmoment sitzen Haende oder Unterarme genau am Ball.
## Pro Technik gibt es ein Ziel fuer jedes Handgelenk (Weltkoordinaten) und eine Zeitkurve
## (Hinfuehren, Kontakt, Loslassen). Neue Techniken (z. B. weitere Zuspielarten) bekommen hier
## einen eigenen Zweig.
func _contact_ik() -> void:
	var rel := now - anim_t
	var f := Vector3(-sin(_yaw), 0.0, -cos(_yaw))  # blickt nach vorn
	var r := Vector3(cos(_yaw), 0.0, -sin(_yaw))   # rechte Seite
	var up := Vector3.UP
	var tg := {}
	var w := 0.0
	var b := contact_pt
	if block_pose and airborne:
		# Haende ueber das Netz gedrueckt, Handflaechen zeigen zum Gegner.
		var net_side := -side
		var base := Vector3(net_x + net_side * (0.06 + hand_reach * 0.9), block_top() - 0.1, hands_z())
		tg = {"l": base - r * 0.11, "r": base + r * 0.11}
		w = smoothstep(0.05, 0.3, jump_h)
	elif not contact_on and anim_kind != "serve":
		return
	elif anim_kind in ["pass", "dig", "free"] and anim_tech != "over":
		# Baggern: gestreckte Arme, Plattform aus beiden Unterarmen unter dem Ball.
		w = smoothstep(-0.32, -0.06, rel) * (1.0 - smoothstep(0.1, 0.3, rel))
		var plat := b - up * 0.17 + f * 0.07
		tg = {"l": plat - r * 0.05, "r": plat + r * 0.05}
	elif anim_kind in ["set", "pass", "dig", "free"] and anim_tech == "over":
		# Pritschen: beide Haende ueber der Stirn, Finger umfassen den Ball von hinten und den Seiten.
		w = smoothstep(-0.3, -0.05, rel) * (1.0 - smoothstep(0.1, 0.32, rel))
		var ad := contact_aim - position
		ad.y = 0.0
		var follow := (ad.normalized() + up) * 0.5 * (0.2 * smoothstep(0.0, 0.2, rel)) if ad.length() > 0.1 else Vector3.ZERO
		var hb := b + follow
		tg = {"l": hb - r * 0.1 - up * 0.1 - f * 0.04, "r": hb + r * 0.1 - up * 0.1 - f * 0.04}
	elif anim_kind == "attack" and airborne:
		# Angriff: Schlaghand (rechts) trifft die Rueckseite des Balls mit gestrecktem Arm.
		w = smoothstep(-0.12, -0.015, rel) * (1.0 - smoothstep(0.05, 0.2, rel))
		# Handballen trifft, danach schnappen Handflaeche und Finger ueber den Ball (Nachschwung).
		var snap := smoothstep(0.0, 0.1, rel)
		tg = {"r": b - up * 0.07 - f * 0.17 + (f * 0.28 - up * 0.12) * snap}
	elif anim_kind == "serve":
		w = smoothstep(-0.12, -0.015, rel) * (1.0 - smoothstep(0.03, 0.16, rel))
		if airborne:
			tg = {"r": b - up * 0.07 - f * 0.17}
		else:
			tg = {"r": b - up * 0.02 - f * 0.14}
	if w <= 0.001 or tg.is_empty():
		return
	# Im Kontaktmoment streckt sich der Schlagende (Schultergürtel, Fussspitzen): ca. 14 cm mehr Reichweite.
	if airborne and (anim_kind == "attack" or anim_kind == "serve"):
		fig.root_node.position.y += 0.14 * w
	# Beim Pritschen bleiben die Ellbogen aussen (staerkere Daempfung haelt die Haltung).
	var over_set := anim_kind in ["set", "pass", "dig", "free"] and anim_tech == "over"
	for sd in tg:
		if over_set:
			fig.ik_arm(sd, tg[sd], w, 8, 0.12)
		else:
			fig.ik_arm(sd, tg[sd], w)
	fig._sync()


func _arm(p: Dictionary, sd: String, fwd: float, out: float, elbow: float, wrist := 0.0, twist := 0.0) -> void:
	var s := -1.0 if sd == "l" else 1.0
	p["sh_" + sd] = Vector3(fwd, twist * s, out * s)
	p["el_" + sd] = Vector3(elbow, 0.0, 0.0)
	p["wr_" + sd] = Vector3(wrist, 0.0, 0.0)


func _leg(p: Dictionary, sd: String, thigh: float, knee: float, spread := 0.0, point := 0.0) -> void:
	var s := -1.0 if sd == "l" else 1.0
	p["hip_" + sd] = Vector3(thigh, 0.0, spread * s)
	p["kn_" + sd] = Vector3(-knee, 0.0, 0.0)
	# point = Fuss strecken (Zehen nach unten), z. B. in der Luft
	p["an_" + sd] = Vector3(-(thigh - knee) - point, 0.0, 0.0)


func _p_idle() -> Dictionary:
	var br := sin(now * 1.6 + number) * 0.03
	var p := {"chest": Vector3(-0.04 + br, 0, 0), "head": Vector3(0.05 - br, 0, 0)}
	_arm(p, "l", 0.1, 0.1, 0.25)
	_arm(p, "r", 0.1, 0.1, 0.25)
	_leg(p, "l", 0.1, 0.15, 0.05)
	_leg(p, "r", 0.1, 0.15, 0.05)
	return p


func _p_ready() -> Dictionary:
	# Leichtes Wippen und Gewicht verlagern, damit niemand wie eingefroren dasteht.
	var t := now * 3.2 + number * 1.7
	var bob := sin(t) * 0.05
	var shift := sin(t * 0.37) * 0.04
	var p := {"hips": Vector3(-0.2, 0, shift), "chest": Vector3(-0.34, 0, -shift * 0.6), "head": Vector3(0.4, 0, 0)}
	_arm(p, "l", 0.55 + bob, 0.28, 0.75 + bob)
	_arm(p, "r", 0.55 + bob, 0.28, 0.75 + bob)
	_leg(p, "l", 0.7 + bob, 1.1 + bob * 1.8, 0.2)
	_leg(p, "r", 0.7 + bob, 1.1 + bob * 1.8, 0.2)
	return p


func _p_run(a: float) -> Dictionary:
	var ph := _run_phase * (1.0 if _move_fwd >= -0.3 else -1.0)
	var sl := sin(ph)
	var side_w := clampf(absf(_move_side) * 1.4 - 0.3, 0.0, 1.0)
	# Vorwaerts: Oberkoerper nach vorn, Arme gegengleich, Knie hoch beim Durchschwingen.
	var p := {"hips": Vector3(-0.12 * a, sl * 0.12 * a, 0), "chest": Vector3(-0.22 * a, -sl * 0.18 * a, 0), "head": Vector3(0.22 * a, 0, 0)}
	_leg(p, "l", 0.2 + sl * 0.75 * a, 0.3 + maxf(0.0, -cos(ph)) * 1.3 * a)
	_leg(p, "r", 0.2 - sl * 0.75 * a, 0.3 + maxf(0.0, cos(ph)) * 1.3 * a)
	_arm(p, "l", -sl * 0.8 * a + 0.25, 0.14, 1.45)
	_arm(p, "r", sl * 0.8 * a + 0.25, 0.14, 1.45)
	# Mattis' Meshy-Animationen: langsam gehen, schnell laufen (im selben Schritt-Takt).
	var u := fposmod(ph / TAU, 1.0)
	var run := HumanFigure.clip_pose("Running", u)
	if not run.is_empty():
		var walk := HumanFigure.clip_pose("Walking", u)
		p = run if walk.is_empty() else _mix(walk, run, smoothstep(0.3, 0.75, a))
	if side_w > 0.0:
		# Seitlich: tiefer Nachstellschritt, Beine gehen auseinander und wieder zusammen.
		var q := {"hips": Vector3(-0.2, 0, 0), "chest": Vector3(-0.3, 0, 0), "head": Vector3(0.35, 0, 0)}
		var open := absf(sl)
		_leg(q, "l", 0.55, 0.95, 0.1 + open * 0.3)
		_leg(q, "r", 0.55, 0.95, 0.1 + open * 0.3)
		_arm(q, "l", 0.7, 0.2, 0.95)
		_arm(q, "r", 0.7, 0.2, 0.95)
		p = _mix(p, q, side_w)
	return p


## Baggern: tief in die Knie, Arme gestreckt und zusammen, Schwung kommt aus den Beinen.
## rel = Zeit relativ zum Ballkontakt: davor abtauchen, danach Beine strecken und Plattform heben.
func _p_bump(rel := 0.0) -> Dictionary:
	var dip := 1.0 - smoothstep(-0.3, 0.0, rel)
	var drive := smoothstep(0.0, 0.25, rel)
	var p := {"hips": Vector3(-0.38 + 0.14 * drive, 0, 0), "chest": Vector3(-0.55 + 0.25 * drive, 0, 0), "head": Vector3(0.6 - 0.25 * drive, 0, 0)}
	var arm_fwd := lerpf(0.85, 1.2, 1.0 - dip) + 0.45 * drive
	_arm(p, "l", arm_fwd, -0.3, 0.0, 0.0)
	_arm(p, "r", arm_fwd, -0.3, 0.0, 0.0)
	var th := lerpf(1.1, 0.8, drive) + 0.15 * dip
	var kn := lerpf(1.7, 0.8, drive) + 0.15 * dip - 0.15
	_leg(p, "l", th, kn, 0.2)
	_leg(p, "r", th - 0.1, kn - 0.1, 0.2)
	return p


const SET_TWIST := -0.8


## Pritschen wie im echten Spiel: Ellbogen weit aussen und gebeugt, Haende als Dreieck
## ueber der Stirn, Kopf im Nacken. Im Ballkontakt streckt der ganze Koerper (Beine, Arme).
func _p_set(rel := 0.0) -> Dictionary:
	var load := 1.0 - smoothstep(-0.3, -0.1, rel)
	var ext := smoothstep(-0.08, 0.1, rel)
	var p := {"hips": Vector3(-0.08 * load, 0, 0), "chest": Vector3(-0.1 + 0.1 * ext, 0, 0), "head": Vector3(0.65 - 0.2 * ext, 0, 0)}
	var up := lerpf(2.0, 2.7, ext)
	var out := lerpf(1.15, 0.5, ext)
	var elbow := lerpf(1.75, 0.35, ext)
	_arm(p, "l", up, out, elbow, -0.5 + 0.3 * ext, SET_TWIST)
	_arm(p, "r", up, out, elbow, -0.5 + 0.3 * ext, SET_TWIST)
	var th := lerpf(0.6, 0.05, ext)
	var kn := lerpf(0.95, 0.1, ext)
	_leg(p, "l", th, kn, 0.14, 0.5 * ext)
	_leg(p, "r", th - 0.05, kn, 0.14, 0.5 * ext)
	return p


## Angriff in der Luft: rel = Zeit relativ zum Treffpunkt (negativ = davor).
## Ablauf: beide Arme hoch, Schlagarm hinter den Kopf ziehen (Bogenspannung), dann durchschlagen.
func _p_spike(rel: float) -> Dictionary:
	var p := {}
	var cock := smoothstep(-0.45, -0.12, rel)
	var swing := smoothstep(-0.07, 0.1, rel)
	var follow := smoothstep(0.1, 0.4, rel)
	var arch := cock * (1.0 - swing)
	p["hips"] = Vector3(lerpf(0.0, 0.12, arch) - swing * 0.15, 0, 0)
	p["chest"] = Vector3(0.3 * arch - 0.45 * swing + 0.2 * follow, lean * 0.35 - 0.35 * arch + 0.3 * swing, 0)
	p["head"] = Vector3(0.5 - 0.15 * swing, 0, 0)
	# Schlagarm (rechts): hoch -> hinter den Kopf, Ellbogen hoch -> gestreckt durch -> nach unten aus
	var sh_up := lerpf(2.4, 2.95, cock)
	_arm(p, "r", lerpf(sh_up, 0.55, swing) + follow * 0.1, lerpf(0.25, 0.55, arch), lerpf(lerpf(0.3, 2.1, cock), 0.15, swing), 0.3 * swing)
	# Gegenarm zeigt zum Ball, zieht beim Schlag nach unten zum Koerper
	_arm(p, "l", lerpf(2.6, 0.7, swing), 0.12, lerpf(0.25, 1.0, swing))
	# Beine: beim Ausholen Fersen nach hinten zum Gesaess, beim Schlag nach vorn klappen (Hohlkreuz-Schnapp)
	_leg(p, "l", lerpf(0.25, 0.75, swing), lerpf(1.55, 0.8, swing), 0.14, 0.9)
	_leg(p, "r", lerpf(-0.05, 0.6, swing), lerpf(1.7, 0.7, swing), 0.14, 0.9)
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
	var p := {"hips": Vector3(-0.1 if airborne else 0.0, 0, 0), "chest": Vector3(-0.25 if airborne else -0.05, 0, local_shift * 0.25), "head": Vector3(0.45 if airborne else 0.25, 0, 0)}
	_arm(p, "l", fwd, 0.1 - local_shift * 0.5, 0.05, -0.35)
	_arm(p, "r", fwd, 0.1 + local_shift * 0.5, 0.05, -0.35)
	if airborne:
		_leg(p, "l", 0.2, 0.35, 0.08, 0.9)
		_leg(p, "r", 0.1, 0.3, 0.08, 0.9)
	else:
		_arm(p, "l", 2.3, 0.25, 1.3, -0.3)
		_arm(p, "r", 2.3, 0.25, 1.3, -0.3)
		_leg(p, "l", 0.45, 0.8, 0.15)
		_leg(p, "r", 0.45, 0.8, 0.15)
	return p


func _p_dive() -> Dictionary:
	var kd := 1.0 - clampf(dive_timer / 0.7, 0.0, 1.0)
	var flat := smoothstep(0.1, 0.4, kd) * (1.0 - smoothstep(0.7, 0.95, kd))
	var p := {"chest": Vector3(0.1 * flat, 0, 0), "head": Vector3(0.7 + 0.3 * flat, 0, 0)}
	_arm(p, "l", 2.6, 0.2, 0.05)
	_arm(p, "r", 2.6, 0.2, 0.05)
	# Abdruck: ein Bein gebeugt vorn; flach: beide Beine gestreckt nach hinten
	_leg(p, "l", lerpf(0.9, -0.15, flat), lerpf(1.2, 0.25, flat))
	_leg(p, "r", lerpf(0.1, -0.05, flat), lerpf(0.4, 0.4, flat))
	return p


func _p_serve(rel: float, jump_serve: bool) -> Dictionary:
	if airborne:
		return _p_spike(rel)
	if jump_serve and rel < -0.25:
		var hold := _mix(_p_serve_hold(), _p_run(maxf(_run_amt, 0.4)), clampf(_run_amt * 2.0, 0.0, 1.0))
		return _mix(hold, _p_approach(), smoothstep(-0.85, -0.45, rel))
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
		_stiff = 30.0
		return _p_dive()
	if celebrate_until > now:
		_stiff = 16.0
		return _p_celebrate()
	var rel := now - anim_t
	if anim_kind == "serve_hold":
		return _mix(_p_serve_hold(), _p_run(_run_amt), clampf(_run_amt * 2.0, 0.0, 1.0))
	if anim_kind == "serve" and rel < 0.5:
		_stiff = 42.0
		return _p_serve(rel, anim_tech == "jump")
	if block_pose:
		_stiff = 30.0
		return _p_block()
	if anim_kind == "attack" and rel < 0.5:
		if airborne:
			_stiff = 45.0
			return _p_spike(rel)
		if rel > -1.0:
			# Anlauf weich einblenden statt hart umschalten.
			var wa := smoothstep(-1.0, -0.55, rel)
			var run := _mix(_p_ready(), _p_run(maxf(_run_amt, 0.3)), clampf(_run_amt * 1.6, 0.0, 1.0))
			_stiff = lerpf(22.0, 26.0, wa)
			return _mix(run, _p_approach(), wa)
	_stiff = 22.0 + _run_amt * 10.0
	var base := _p_ready() if alert else _p_idle()
	if _run_amt > 0.05:
		base = _mix(base, _p_run(_run_amt), clampf(_run_amt * 1.6, 0.0, 1.0))
	if airborne:
		base = _mix(base, _p_spike(-0.5), 0.6)
	# Landung: kurz in die Knie federn.
	var land := 1.0 - clampf((now - _land_t) / 0.35, 0.0, 1.0)
	if land > 0.0:
		base = _mix(base, _p_land(), sin(land * PI * 0.5) * 0.8)
		_stiff = 30.0
	# Taste gehalten: schon vorher in die Grundhaltung fuer Baggern oder Pritschen.
	if prep != "" and not airborne:
		base = _mix(base, _p_set(-0.45) if prep == "over" else _p_bump(-0.45), 0.8)
	if anim_kind in ["pass", "dig", "set", "free"] and rel > -0.9 and rel < 0.6:
		var tech := _p_set(rel) if anim_tech == "over" else _p_bump(rel)
		var w := smoothstep(-0.9, -0.35, rel) * (1.0 - smoothstep(0.25, 0.6, rel))
		base = _mix(base, tech, w)
		_stiff = 20.0
	return base


func _p_land() -> Dictionary:
	var p := {"hips": Vector3(-0.3, 0, 0), "chest": Vector3(-0.25, 0, 0), "head": Vector3(0.3, 0, 0)}
	_arm(p, "l", 0.5, 0.35, 0.6)
	_arm(p, "r", 0.5, 0.35, 0.6)
	_leg(p, "l", 0.95, 1.5, 0.15)
	_leg(p, "r", 0.95, 1.5, 0.15)
	return p


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
	_root_y = fig.root_node.position.y
	_last_pos = position


## Wie restore(), aber zwischen zwei Aufzeichnungen gemischt (w = 0..1), fuer weiche Zeitlupe.
func restore_mix(a: Array, b: Array, w: float) -> void:
	restore(a if w < 0.5 else b)
	position = (a[0] as Vector3).lerp(b[0], w)
	jump_h = lerpf(a[1], b[1], w)
	var ca: Array = a[8]
	var cb: Array = b[8]
	var c := []
	for i in ca.size():
		c.append((ca[i] as Vector3).lerp(cb[i], w))
	fig.apply(c)
	fig.rotation.y = lerp_angle(a[9], b[9], w)
	_yaw = fig.rotation.y
	_root_y = fig.root_node.position.y
	_last_pos = position
