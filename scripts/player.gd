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
static var ball_node: Node3D  # der Spielball (fuer die Finger), setzt das Match
const BALL_VIS_R := 0.14  # so gross wird der Ball gezeichnet (match.gd)
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
## Bewegungscharakter (move_style.gd). movement_style: Schluessel aus den Spielerdaten, leer =
## aus Team und Nummer ausgewuerfelt.
var movement_style := ""
## Aus den Spielerdaten (vom Match gesetzt): Reichweite ueber/unter dem 1,95-m-Spieler, Absprung.
var reach_add := 0.0
var jump_v0 := JUMP_V
## Koerpergroesse in m (1,80 bis 2,12; 0 = aus Team und Nummer gewuerfelt). Die Figur wird gleichmaessig
## skaliert (nicht breiter), Fuesse, IK und Kontakte rechnen in Weltkoordinaten und passen sich an.
var height_m := 0.0
## Linkshaender: Angriff, Sprung- und Standaufschlag mit links (Bewegung gespiegelt).
var left_handed := false
const MODEL_HEIGHT := 1.88  # m: Meshy-Spieler bei Massstab 1 (Sohle bis Scheitel ohne Haare)
var style := MoveStyle.new()
var _ring: MeshInstance3D
var _yaw := 0.0
var _run_phase := 0.0
var _run_amt := 0.0
var _last_pos := Vector3.ZERO
var _vel := Vector3.ZERO  # Laufgeschwindigkeit (weich beschleunigen und abbremsen)
const ACCEL := 40.0  # m/s^2: in ca. 0,15 s auf vollem Tempo
const ACCEL_URGENT := 110.0  # wer gerade zum Ball muss, sprintet fast sofort los
var urgent := false  # vom Match gesetzt: dieser Spieler spielt den naechsten Ball
var _jersey := Color.WHITE
var _move_fwd := 1.0
var _move_side := 0.0
var _was_air := false
var _takeoff_t := -10.0
var _land_t := -10.0
var _stiff := 20.0
var _root_y := 0.0
var _stride_amp := 1.0  # Schrittweite: bei hohem Tempo laengere Schritte statt nur schnellerer Beine
var _v_prev := Vector3.ZERO
var _acc := Vector3.ZERO  # geglaettete Beschleunigung (Welt), fuer Koerperneigung
var _vy_prev := 0.0
var _vy_last := 0.0
var _sec := 0.0  # weiche Federung: Auslenkung von Kopf, Oberkoerper und Armen
var _sec_v := 0.0
var _sec_applied := 0.0
var _lean_x := 0.0
var _lean_z := 0.0


func setup(p_team: int, p_role: String, _tag_letter: String, p_number: int, color: Color) -> void:
	team = p_team
	role = p_role
	number = p_number
	side = -1.0 if team == 0 else 1.0
	_yaw = -side * PI / 2.0
	fig = HumanFigure.new()
	add_child(fig)
	var h := hash(team * 1000 + number)
	if "--lab-body" in OS.get_cmdline_user_args():
		# Labor: Linkshaender (ungerade Nummern) und Groessen-Extreme 1,80 / 2,12 m testen
		left_handed = number % 2 == 1
		height_m = 1.8 if number % 4 < 2 else 2.12
	_pick_style()
	fig.build(_colors(color), true, (h / 13) % HumanFigure.HAIR_STYLES, false, _body_scale(h))
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
func _pick_style() -> void:
	style = MoveStyle.from_key(movement_style if movement_style != "" else "%d-%d" % [team, number])


## Massstab der Figur: aus height_m, sonst wie bisher leicht gewuerfelt (1,96 bis 2,09 m).
func _body_scale(h: int) -> float:
	if height_m > 0.0:
		return clampf(height_m, 1.7, 2.2) / MODEL_HEIGHT
	return 1.04 + 0.07 * float((h / 31) % 10) / 9.0


## Schlaghand: "r", bei Linkshaendern "l".
func hit_side() -> String:
	return "l" if left_handed else "r"


## Pose spiegeln (links und rechts tauschen, Drehung um Hoch- und Laengsachse umkehren):
## so schlaegt ein Linkshaender dieselbe Technik mit links.
func _mirror(p: Dictionary) -> Dictionary:
	if not left_handed:
		return p
	var out := {}
	for k in p:
		var v = p[k]
		var k2: String = k
		if k.ends_with("_l"):
			k2 = k.left(-2) + "_r"
		elif k.ends_with("_r"):
			k2 = k.left(-2) + "_l"
		out[k2] = Vector3(v.x, -v.y, -v.z) if v is Vector3 else v
	return out


func change_identity(p_role: String, _tag_letter: String, p_number: int, color: Color) -> void:
	role = p_role
	number = p_number
	_pick_style()
	fig.root_node.scale = Vector3.ONE * _body_scale(hash(team * 1000 + number))
	var c := _colors(color)
	for k in c:
		fig.set_color(k, c[k])
	fig.set_number(number, _number_color(color), (Teams.playing()[team] as TeamStyle).number)


func set_side(s: float) -> void:
	side = s


func reset_state() -> void:
	_getup = 0.0
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
	_reach_off = Vector3.ZERO
	_vel = Vector3.ZERO
	_last_pos = position


func jump() -> void:
	if airborne:
		return
	airborne = true
	has_jumped = true
	jump_v = jump_v0
	takeoff_x = absf(position.x)


func dive() -> void:
	dive_timer = 0.7


func spike_hand() -> float:
	return jump_h + SPIKE_REACH + reach_add


func block_top() -> float:
	return jump_h + BLOCK_REACH + reach_add + hand_reach


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
		_vel = Vector3.ZERO
	elif dive_timer <= 0.3:
		# Weich anlaufen und vor dem Ziel abbremsen statt sofort auf vollem Tempo.
		var acc := ACCEL_URGENT if urgent else ACCEL
		var want := Vector3.ZERO
		var to := Vector3(target.x - position.x, 0.0, target.z - position.z)
		var dist := to.length()
		if manual_dir.length() > 0.15:
			want = manual_dir.limit_length(1.0) * run_speed
		elif dist > 0.02:
			want = to / dist * minf(run_speed, sqrt(2.0 * acc * dist))
		_vel = _vel.move_toward(want, acc * delta)
		var step := _vel * delta
		if manual_dir.length() <= 0.15 and step.length() > dist:
			step = to  # nicht ueber das Ziel hinaus
			_vel = Vector3.ZERO
		position += step
		if manual_dir.length() > 0.15:
			target = position
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
	# Schrittlaenge passt zum Tempo: die Meshy-Clips machen ca. 1,7 m pro Doppelschritt; schneller
	# wird der Schritt bis 30 % weiter (Beine schwingen weiter aus), damit die Fuesse nicht rutschen
	# und die Beine nicht hektisch trippeln.
	_stride_amp = lerpf(_stride_amp, clampf(1.0 + (speed - 3.5) * 0.1, 1.0, 1.3), k)
	# Beim Anhalten laeuft der Schritt noch zu Ende (Fuss setzt auf), statt mit gehobenem Bein
	# stehen zu bleiben und langsam auszublenden.
	var step_v := maxf(speed, 1.4 * clampf(_run_amt * 4.0, 0.0, 1.0))
	_run_phase += step_v * delta * TAU / (1.7 * _stride_amp)
	# Beschleunigung fuer Vorlage beim Antreten, Ruecklage beim Bremsen und Kurvenneigung.
	var v := moved / maxf(delta, 0.0001)
	if delta > 0.0:
		_acc = _acc.lerp((v - _v_prev) / delta, clampf(delta * 6.0, 0.0, 1.0))
	_v_prev = v
	if airborne and not _was_air:
		_takeoff_t = now
	if _was_air and not airborne:
		_land_t = now
		impact("land", clampf(-_vy_last / 4.0, 0.3, 1.2), Vector3.DOWN)
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
	if _was_dive and dive_timer <= 0.0:
		_getup = GETUP_T
	_was_dive = dive_timer > 0.0
	if _getup > 0.0:
		_getup = maxf(_getup - delta * (1.0 + 0.8 * _run_amt), 0.0)
	_dt_pose = delta
	var p := _target_pose()
	if dive_timer <= 0.0 and _getup <= 0.0:
		# Haltung: Oberkoerper etwas weiter vorn oder aufrechter, Kopf etwas anders
		p["chest"] = (p.get("chest", Vector3.ZERO) as Vector3) + Vector3(-style.posture, 0, 0)
		p["head"] = (p.get("head", Vector3.ZERO) as Vector3) + Vector3(style.posture * 0.6 + style.head, 0, 0)
	fig.phys_k = 42.0 * lerpf(1.0, style.tempo, 0.7)
	fig.phys_zeta = style.sway
	fig.pose_spring(p, delta, _stiff * style.tempo)
	_update_sec(delta)
	# Hechten: ganzer Koerper kippt nach vorn.
	var tilt := 0.0
	if dive_timer > 0.0 and not HumanFigure.clip_pose("vb_hechtbagger", 0.0, false).is_empty():
		pass  # Meshy-Hechtbagger kippt den Koerper selbst
	elif dive_timer > 0.0:
		# Ablauf: nach vorn abdruecken, flach auf den Bauch rutschen, wieder aufstehen.
		var kd := 1.0 - clampf(dive_timer / 0.7, 0.0, 1.0)
		tilt = -1.45 * smoothstep(0.0, 0.35, kd) * (1.0 - smoothstep(0.7, 1.0, kd))
	# Laufen: beim Antreten nach vorn, beim Bremsen nach hinten, in Kurven nach innen neigen.
	var acc_loc := _acc.rotated(Vector3.UP, -_yaw)
	var ground := not airborne and dive_timer <= 0.0
	var want_x := clampf(acc_loc.z * 0.012, -0.12, 0.14) if ground else 0.0
	var want_z := clampf(-acc_loc.x * 0.012, -0.18, 0.18) * clampf(_run_amt * 1.5, 0.0, 1.0) if ground else 0.0
	_lean_x = lerpf(_lean_x, want_x, clampf(delta * 8.0, 0.0, 1.0))
	_lean_z = lerpf(_lean_z, want_z, clampf(delta * 8.0, 0.0, 1.0))
	fig.root_node.rotation.x = lerpf(fig.root_node.rotation.x, tilt, clampf(delta * 12.0, 0.0, 1.0))
	fig.root_node.rotation.z = _lean_z
	if dive_timer <= 0.0:
		fig.root_node.rotation.x = tilt + _lean_x
	# Hoehe: am Boden setzt der tiefste Koerperpunkt genau auf, in der Luft traegt die Sprunghoehe.
	# So sinkt niemand in den Boden ein, egal wie Knie und Huefte gebeugt sind.
	fig.root_node.position = Vector3.ZERO
	var low := fig.lowest_point(dive_timer > 0.0 or _getup > 0.25)
	var y := -low
	if airborne:
		y = maxf(jump_h, -fig.lowest_point(false))
	_root_y = maxf(lerpf(_root_y, y, clampf(delta * 25.0, 0.0, 1.0)), -low)
	fig.root_node.position.y = _root_y
	# Standaufschlag: im Treffpunkt auf die Zehenspitzen, der Koerper streckt sich zum Ball.
	_toe = 0.0
	if anim_kind == "serve" and anim_tech == "stand" and not airborne:
		var rs := now - anim_t
		_toe = TOE_RISE * smoothstep(-0.22, -0.03, rs) * (1.0 - smoothstep(0.06, 0.28, rs))
		fig.root_node.position.y += _toe
		fig._sync()
	elif anim_kind in ["set", "pass", "free"] and anim_tech == "over" and contact_on and not airborne:
		# Pritschen: nach dem Kontakt streckt sich der ganze Koerper bis auf die Zehenspitzen
		var rs := now - anim_t
		_toe = 0.05 * smoothstep(-0.02, 0.14, rs) * (1.0 - smoothstep(0.32, 0.55, rs))
		fig.root_node.position.y += _toe
		fig._sync()
	_reach_ball(delta)
	_net_guard(delta)
	_plant_feet(delta)
	_contact_ik()
	_apply_hits()
	fig.physics_step(delta)
	_hand_shape()
	var bp := ball_node.global_position if ball_node != null and is_instance_valid(ball_node) else Vector3.INF
	fig.fingers_step(delta, bp, BALL_VIS_R)


# ---------------------------------------------------------------- Stoesse (Semi-Ragdoll)
## Der Ball trifft den Koerper: Unterarme, Haende und Rumpf bekommen Schwung in Flugrichtung des
## Balls und geben fuer einen Moment nach (weichere Gelenke), dann holt die Animation sie zurueck.
## Im Kontaktmoment selbst haelt pin die Haende am Ball, deshalb wirkt der Stoss kurz danach.
var _hits := []  # [ab Zeitpunkt, Art, Staerke, Richtung (Welt)]
var _push := Vector3.ZERO  # sichtbares Wegschieben bei Zusammenprall (nur Figur, nicht die Spielposition)
var _push_v := Vector3.ZERO


func impact(kind: String, strength: float, dir: Vector3) -> void:
	_hits.append([now + 0.06, kind, clampf(strength, 0.0, 1.5), dir.normalized() if dir.length() > 0.01 else Vector3.DOWN])


func _apply_hits() -> void:
	var i := 0
	while i < _hits.size():
		var h: Array = _hits[i]
		if now < float(h[0]):
			i += 1
			continue
		_hits.remove_at(i)
		var kind: String = h[1]
		var st: float = h[2]
		var d: Vector3 = h[3]
		var f := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
		var r := Vector3(cos(_yaw), 0.0, -sin(_yaw))
		match kind:
			"bump", "dig":
				# Ball drueckt die Plattform nach unten/hinten, Oberkoerper nickt mit
				for sd in ["l", "r"]:
					_push_limb("sh_" + sd, "wr_" + sd, d, 1.2 + 2.6 * st)
					fig.soften("sh_" + sd, 0.45, 0.28)
					fig.soften("el_" + sd, 0.5, 0.28)
				_push_limb("hips", "chest", d * 0.5 - f * 0.3, 0.5 + 0.8 * st)
				fig.soften("chest", 0.6, 0.3)
			"set":
				# Ball federt in die Haende: Handgelenke klappen kurz nach hinten
				for sd in ["l", "r"]:
					_push_limb("wr_" + sd, "wr_" + sd, d, 1.5 + 2.0 * st, 0.08)
					_push_limb("el_" + sd, "wr_" + sd, d, 0.6 + 1.0 * st)
					fig.soften("wr_" + sd, 0.4, 0.2)
					fig.soften("el_" + sd, 0.6, 0.2)
			"block":
				# harter Angriff in den Block: Haende und Arme werden zurueckgedrueckt
				for sd in ["l", "r"]:
					_push_limb("wr_" + sd, "wr_" + sd, d, 2.0 + 4.0 * st, 0.08)
					_push_limb("sh_" + sd, "wr_" + sd, d, 1.0 + 2.5 * st)
					fig.soften("sh_" + sd, 0.4, 0.35)
					fig.soften("el_" + sd, 0.45, 0.35)
					fig.soften("wr_" + sd, 0.35, 0.35)
				_push_limb("hips", "head", d, 0.4 + 0.8 * st)
				fig.soften("chest", 0.6, 0.35)
			"spike", "serve":
				# Rumpf klappt beim Schlag nach vorn ein, Schlagarm schwingt locker aus
				_push_limb("hips", "head", f - Vector3.UP * 0.5, 0.8 + 1.4 * st)
				fig.soften("chest", 0.6, 0.3)
				fig.soften("sh_" + hit_side(), 0.55, 0.35)
				fig.soften("el_" + hit_side(), 0.5, 0.35)
			"land":
				# Landung: Oberkoerper und Kopf nicken nach vorn, Arme schwingen nach unten
				_push_limb("hips", "head", f * 0.6 - Vector3.UP, 0.6 * st)
				_push_limb("chest", "head", f - Vector3.UP, 0.8 * st)
				for sd in ["l", "r"]:
					_push_limb("sh_" + sd, "wr_" + sd, -Vector3.UP + f * 0.2 + (r if sd == "r" else -r) * 0.2, 1.4 * st)
				fig.soften("chest", 0.7, 0.25)
				fig.soften("head", 0.6, 0.3)
			"bump_body":
				_push_limb("hips", "head", d, 1.0 * st)
				fig.soften("chest", 0.5, 0.35)
				fig.soften("head", 0.5, 0.35)


## Schwung so, dass der Punkt am Gelenk tip (oder off m unter dem Gelenk) mit speed m/s in
## Richtung dir ausweicht: Drehachse = Hebel x Richtung.
func _push_limb(joint: String, tip: String, dir: Vector3, speed: float, off := 0.0) -> void:
	var jp: Vector3 = fig.j[joint].global_position
	var tp: Vector3 = fig.j[tip].global_position
	if off > 0.0:
		tp = fig.j[tip].global_transform * Vector3(0, -off, 0)
	var lever := tp - jp
	if lever.length() < 0.02:
		return
	var w_world := lever.cross(dir.normalized() * speed) / lever.length_squared()
	fig.impulse(joint, fig.world_to_parent(joint, w_world))


## Zusammenprall: Spieler, die sich zu nah kommen, schieben sich sichtbar weg (Federn auf der Figur).
## Die Spielpositionen bleiben, wie das Match sie will.
static func separate(all: Array, delta: float) -> void:
	if delta <= 0.0:
		return
	for i in all.size():
		var a: VPlayer = all[i]
		var want := Vector3.ZERO
		for k in all.size():
			if k == i:
				continue
			var b: VPlayer = all[k]
			var d := a.global_position - b.global_position
			d.y = 0.0
			var l := d.length()
			if l < 0.55 and l > 0.001:
				want += d / l * (0.55 - l) * 0.5
			# Vorausschauen: laufen zwei aufeinander zu (oder durcheinander durch, etwa beim
			# Positionswechsel), weichen sie schon vorher seitlich aus. Sonst kommt die Feder zu spaet.
			var rv: Vector3 = a._vel - b._vel
			rv.y = 0.0
			var rv2 := rv.length_squared()
			if rv2 > 1.0 and l < 2.0:
				var t := clampf(-d.dot(rv) / rv2, 0.0, 0.3)
				if t > 0.0:
					var c := d + rv * t
					var lc := c.length()
					if lc < 0.6:
						var side := c / lc if lc > 0.03 else Vector3(-rv.z, 0.0, rv.x).normalized()
						want += side * (0.6 - lc) * 0.5 * (1.0 - t / 0.3 * 0.6)
		var w := 18.0
		a._push_v += (want - a._push) * (w * w * delta) - a._push_v * (2.0 * 0.7 * w * delta)
		a._push += a._push_v * delta
		a._push = a._push.limit_length(0.4)
		if want.length() > 0.05 and a._push_v.length() > 0.4 and not a._was_bumped:
			a._was_bumped = true
			a.impact("bump_body", clampf(want.length() * 4.0, 0.2, 1.0), want)
		elif want.length() < 0.01:
			a._was_bumped = false
		a.fig.position = a.global_basis.inverse() * a._push


var _was_bumped := false


## Feste Fuesse: ein Fuss, der am Boden steht und sich (fast) nicht bewegt, wird an dieser
## Stelle festgehalten, bis die Animation ihn anhebt oder er zu weit weg muss. Dann loest er sich
## weich und macht dabei einen kleinen Schritt zur neuen Stelle. So gleitet kein Fuss ueber den
## Boden, auch nicht beim Drehen auf der Stelle oder wenn Laufen und Schrittlaenge nicht genau passen.
const ARM_HIT_LEN := 0.46  # m: Schulter bis Handgelenk, Arm ganz gestreckt (Treffpunkt Angriff)
var dbg_tg := {}  # nur fuer das Labor: Handziele dieses Takts
var _toe := 0.0  # m: Zehenstand (Standaufschlag), so weit heben sich Koerper und Fersen
const TOE_RISE := 0.07
var _feet_miss := {}  # Seite -> wie weit das Bein den festen Punkt im letzten Takt verfehlt hat
var _sole_t := {}  # Seite -> Sohlenhoehe der Animation in diesem Takt (vor den Korrekturen)
var _feet := {}  # Seite -> {on, anchor (Sprunggelenk Welt), basis (Fuss Welt), w, from, from_b, last}
const PLANT_H := 0.035  # Sohle so nah am Boden: Fuss steht
const LIFT_H := 0.07  # Animation hebt den Fuss so weit an: loslassen
const PLANT_V := 2.0  # m/s: schneller bewegte Fuesse werden nicht festgehalten
const STRETCH := 0.2  # m: so weit darf der Fuss vom Ziel der Animation weg, dann Schritt
const TWIST := 0.6  # rad: Koerper hat sich so weit gedreht, dann Schritt
const STEP_T := 0.13  # s: Dauer des Loesens / kleinen Schritts


## Baggern: ist der Ball ausser Reichweite (zu spaet dran, Ball seitlich), macht der Koerper einen
## Ausfallschritt zum Ball, statt die Arme ins Leere zu strecken. Vor den festen Fuessen, damit
## die Fuesse dabei nicht rutschen, sondern nachsetzen.
var _reach_off := Vector3.ZERO
var _dt_pose := 0.0
var crouch_want := 0.0  # m: so tief soll die Huefte fuer einen tiefen Ball
var _crouch_drop := 0.0  # m: so tief ist sie gerade (geglaettet)
func _reach_ball(delta: float) -> void:
	var want := Vector3.ZERO
	if contact_on and anim_kind in ["pass", "dig", "free", "set"] and anim_tech != "over" and not airborne and dive_timer <= 0.0:
		var rel := now - anim_t
		var w := smoothstep(-0.32, -0.06, rel) * (1.0 - smoothstep(0.1, 0.3, rel))
		var off: Vector3 = contact_pt - (fig.j["hips"] as Node3D).global_position
		off.y = 0.0
		var excess := off.length() - 0.55
		if excess > 0.0:
			want = off.normalized() * minf(excess, 0.5) * w
		# tiefer Ball: in die Knie gehen, bis die Plattform unter den Ball kommt (ueber die Haltung,
		# siehe _target_pose_main, damit die Fuesse am Boden bleiben)
		var sh_y := (fig.j["sh_r"] as Node3D).global_position.y + _crouch_drop
		crouch_want = clampf((sh_y - 0.62) - (contact_pt.y - 0.17), 0.0, 0.35) * w
	elif contact_on and anim_kind in ["set", "pass", "free"] and anim_tech == "over" and not airborne:
		# Pritschen: unter dem Ball in die Knie gehen, im Kontakt aus den Beinen strecken
		var rel2 := now - anim_t
		# Ball vor und ueber der Stirn nehmen (Ballmitte gut 30 cm schraeg vor-oben, nicht genau
		# senkrecht darueber): Koerper etwas hinter den Ball, und so tief, dass die Arme gebeugt
		# bleiben; im Kontakt streckt der Spieler sich wieder (Beine vor den Armen).
		var w2 := smoothstep(-0.6, -0.3, rel2) * (1.0 - smoothstep(0.0, 0.15, rel2))
		var fw := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
		var head: Vector3 = (fig.j["head"] as Node3D).global_position
		var brow := head + Vector3.UP * 0.13 + fw * 0.1
		var ahead := (contact_pt - brow).dot(fw)
		want = -fw * clampf(0.15 - ahead, 0.0, 0.15) * w2
		var drop_y := brow.y + _crouch_drop - (contact_pt.y - 0.4)
		crouch_want = maxf(0.1 * smoothstep(-0.65, -0.4, rel2) * (1.0 - smoothstep(-0.3, -0.12, rel2)),
			clampf(drop_y, 0.0, 0.16) * smoothstep(-0.5, -0.25, rel2) * (1.0 - smoothstep(-0.02, 0.12, rel2)))
	else:
		crouch_want = 0.0
	_reach_off = _reach_off.lerp(want, clampf(delta * 18.0, 0.0, 1.0))
	if _reach_off.length() > 0.002:
		fig.root_node.position += fig.global_basis.orthonormalized().inverse() * _reach_off
		fig._sync()


## Netz: ragt unterhalb der Netzkante ein Koerperteil auf die andere Seite, lehnt sich der Spieler
## so weit zurueck, dass er das Netz nicht durchdringt (vor den festen Fuessen).
var _net_off := 0.0
func _net_guard(delta: float) -> void:
	var worst := 0.0
	for n in ["head", "chest", "wr_l", "wr_r", "el_l", "el_r", "kn_l", "kn_r"]:
		var pos: Vector3 = (fig.j[n] as Node3D).global_position
		if pos.y < 2.38 and absf(pos.z) < 4.6:
			worst = maxf(worst, (net_x - pos.x) * side + 0.03)  # > 0: ueber die Netzebene
	_net_off = maxf(worst, lerpf(_net_off, 0.0, clampf(delta * 6.0, 0.0, 1.0)))
	if _net_off > 0.002:
		var shift := Vector3(side * minf(_net_off, 0.3), 0.0, 0.0)
		fig.root_node.position += fig.global_basis.orthonormalized().inverse() * shift
		fig._sync()


func _plant_feet(delta: float) -> void:
	var floor_y := global_position.y
	var free := airborne or dive_timer > 0.0 or _getup > 0.25 or delta <= 0.0
	if not free:
		for k in ["hip_l", "kn_l", "an_l", "hip_r", "kn_r", "an_r"]:
			fig.pin[k] = 0.5  # am Boden folgen die Beine eng der Animation
	for sd in ["l", "r"]:
		var at: Transform3D = (fig.j["an_" + sd] as Node3D).global_transform
		_sole_t[sd] = minf((at * Vector3(0, -0.097, 0.085)).y, (at * Vector3(0, -0.097, -0.225)).y) - floor_y
	for sd in ["l", "r"]:
		var an: Node3D = fig.j["an_" + sd]
		var tgt: Vector3 = an.global_position  # wo die Animation das Sprunggelenk haben will
		var tb: Basis = an.global_basis.orthonormalized()
		var sole_y := minf((an.global_transform * Vector3(0, -0.097, 0.085)).y, (an.global_transform * Vector3(0, -0.097, -0.225)).y) - floor_y
		var f: Dictionary = _feet.get(sd, {})
		var vel := 0.0
		if f.has("last"):
			var dv: Vector3 = tgt - (f["last"] as Vector3)
			vel = Vector2(dv.x, dv.z).length() / delta
		# Teleport (neue Aufstellung, ab 30 cm pro Takt) oder erster Takt. Der Fuss der Laufanimation
		# schwingt kurz mit gut 15 m/s nach vorn; das ist kein Teleport (sonst springt das Knie).
		if vel > 36.0 or f.is_empty():
			f = {"on": false, "w": 0.0}
		f["last"] = tgt
		var shown: Vector3 = tgt
		if f.on:
			var a: Vector3 = f.anchor
			var dxz := Vector2(tgt.x - a.x, tgt.z - a.z).length()
			var twist: float = absf(((f.basis as Basis).get_rotation_quaternion() * tb.get_rotation_quaternion().inverse()).get_angle())
			# Bein reicht nicht mehr hin (Koerper ist weiter): Schritt statt Strecken oder Einsinken
			var short: float = _feet_miss.get(sd, 0.0)
			# Nachstellschritt nur, wenn der andere Fuss steht (nie beide zugleich in der Luft),
			# ausser der Fuss ist schon sehr weit weg
			var other: Dictionary = _feet.get("r" if sd == "l" else "l", {})
			var forced := dxz > STRETCH or twist > TWIST or short > 0.02
			if forced and not other.get("on", false) and dxz < STRETCH * 2.0 and short <= 0.02:
				forced = false
			if free or sole_y > LIFT_H or forced:
				f.on = false  # anheben (Animation) oder Nachstellschritt
			f.from = a
			f.from_b = f.basis
		# aufsetzen: Fuss steht fast still, oder er beruehrt den Boden (Fersenaufsatz beim Laufen,
		# da bewegt sich der Fuss der Animation noch nach vorn und wuerde sonst rutschen)
		if not f.on and not free and sole_y < PLANT_H and (vel < PLANT_V or sole_y < 0.012) and float(f.w) <= 0.0:
			f.on = true
			f.anchor = tgt
			f.basis = tb
		if f.on:
			f.w = 1.0
			shown = f.anchor
			if _toe > 0.001:
				# Ferse hebt sich, der Fuss dreht um die Zehen
				var ft := Transform3D(f.basis, f.anchor)
				var toe: Vector3 = ft * Vector3(0, -0.097, -0.225)
				var ang := -asin(clampf(_toe / 0.245, 0.0, 0.8))
				var rot := Basis((f.basis as Basis).x.normalized(), ang)
				_pin_foot(sd, toe + rot * ((f.anchor as Vector3) - toe), rot * (f.basis as Basis), 1.0)
			else:
				_pin_foot(sd, f.anchor, f.basis, 1.0)
		elif float(f.w) > 0.0:
			# loesen: vom alten Standpunkt weich zur Animation, beim Schritt mit kleinem Bogen
			f.w = maxf(float(f.w) - delta / STEP_T, 0.0)
			var k := smoothstep(0.0, 1.0, float(f.w))
			var from: Vector3 = f.from
			var pos: Vector3 = tgt.lerp(from, k)
			# immer im kleinen Bogen (nie ueber den Boden schleifen), hoeher bei weitem Schritt
			var dist := Vector2(tgt.x - from.x, tgt.z - from.z).length()
			# Die Hoehe gleitet mit vom alten Standpunkt zur Animation: stand der Fuss hoeher (etwa nach
			# einer Landung), fiele er sonst am Ende des Schritts auf einmal herunter (Knie springt).
			pos.y += clampf(dist * 0.35, 0.03, 0.06) * sqrt(sin(k * PI))
			_pin_foot(sd, pos, (f.from_b as Basis).slerp(tb, 1.0 - k), 1.0)
			# erst wieder aufsetzen, wenn das Loesen fertig ist
			if f.w <= 0.0:
				f.erase("from")
		elif not free and vel > PLANT_V and sole_y < 0.03:
			# Schwungbein streift in der Animation fast den Boden: etwas hoeher fuehren statt schleifen
			_pin_foot(sd, tgt + Vector3.UP * (0.03 - sole_y), tb, 1.0)
		_feet[sd] = f


func _pin_foot(sd: String, pos: Vector3, b: Basis, w: float) -> float:
	var miss := fig.ik_leg(sd, pos, w)
	_feet_miss[sd] = miss
	fig.orient_world("an_" + sd, b, w)
	for k in ["hip_", "kn_", "an_"]:
		fig.pin[k + sd] = w
	fig.pin["hips"] = maxf(fig.pin.get("hips", 0.0), w)  # sonst verschiebt die Huefte den Fuss
	fig._sync()
	return miss


## Weiche Federung: eine nachschwingende Feder, angestossen von Landung, Absprung und
## Abbremsen. Kopf, Oberkoerper und Arme folgen ihr ein wenig (keine schlaffe Ragdoll).
func _update_sec(delta: float) -> void:
	if delta <= 0.0:
		return
	var h := _root_y + jump_h
	var vy := (h - _vy_prev) / delta
	_vy_prev = h
	var ay := (vy - _vy_last) / delta
	_vy_last = vy
	var acc_loc := _acc.rotated(Vector3.UP, -_yaw)
	# Antrieb: nur harte Stoesse wie die Landung (nicht die Schwerkraft im Flug) lassen den Kopf
	# nicken; Bremsen kippt den Oberkoerper kurz nach vorn.
	var impact := maxf(absf(ay) - 25.0, 0.0) * signf(ay)
	var drive := clampf(-impact * 0.004 - acc_loc.z * 0.004, -0.35, 0.35)
	var k := 70.0
	var damp := 2.0 * 0.3 * sqrt(k)  # schwach gedaempft: schwingt ein- bis zweimal nach
	_sec_v += ((drive - _sec) * k - _sec_v * damp) * delta
	_sec += _sec_v * delta
	_sec = clampf(_sec, -0.35, 0.35)
	_sec_applied = _sec
	_apply_sec(_sec)


func _apply_sec(a: float) -> void:
	if absf(a) < 0.0001:
		return
	(fig.j["head"] as Node3D).rotation.x += a * 0.5
	(fig.j["chest"] as Node3D).rotation.x += a * 0.25
	(fig.j["sh_l"] as Node3D).rotation.z -= a * 0.3
	(fig.j["sh_r"] as Node3D).rotation.z += a * 0.3
	if a == -_sec_applied:
		_sec_applied = 0.0


## Ballkontakt wie im echten Spiel: im Kontaktmoment sitzen Haende oder Unterarme genau am Ball.
## Pro Technik gibt es ein Ziel fuer jedes Handgelenk (Weltkoordinaten) und eine Zeitkurve
## (Hinfuehren, Kontakt, Loslassen). Neue Techniken (z. B. weitere Zuspielarten) bekommen hier
## einen eigenen Zweig.
var _aim_s := Vector3.ZERO  # geglaettete Zielrichtung (_contact_ik)


func _contact_ik() -> void:
	var rel := now - anim_t
	var f := Vector3(-sin(_yaw), 0.0, -cos(_yaw))  # blickt nach vorn
	var r := Vector3(cos(_yaw), 0.0, -sin(_yaw))   # rechte Seite
	var up := Vector3.UP
	var tg := {}
	var w := 0.0
	var wl := -1.0  # eigenes Gewicht fuer die linke Hand (Angriff), sonst wie w
	var _hit_tg := hit_side() if anim_kind in ["attack", "serve"] else "r"  # Schlaghand (Gewicht w, Nachstrecken)
	var b := contact_pt
	var hands := {}  # Seite -> [Finger, Handflaeche] (Weltrichtungen)
	var poles := {}  # Seite -> wohin der Ellbogen zeigen soll (Welt)
	var pole_w := 0.0
	var ad := contact_aim - b
	ad.y = 0.0
	var aim_h := ad.normalized() if ad.length() > 0.1 else f
	# Das Ziel des Schlags kann sich von Takt zu Takt etwas verschieben (Stick, Bot), Hand und
	# Handgelenk folgen ihm geglaettet (sonst zittert die Hand vor dem Treffpunkt hin und her).
	if _aim_s == Vector3.ZERO or _aim_s.dot(aim_h) < 0.0:
		_aim_s = aim_h
	else:
		_aim_s = _aim_s.lerp(aim_h, 0.12).normalized()
	aim_h = _aim_s
	if block_pose and airborne:
		# Haende ueber das Netz gedrueckt, Handflaechen zeigen zum Gegner, Finger gespreizt nach oben.
		var net_side := -side
		var base := Vector3(net_x + net_side * (0.06 + hand_reach * 0.9), block_top() - 0.1, hands_z())
		tg = {"l": base - r * 0.11, "r": base + r * 0.11}
		w = smoothstep(0.05, 0.3, jump_h)
		var opp_dir := Vector3(net_side, 0.0, 0.0)
		hands = {"l": [up - r * 0.25 + opp_dir * 0.2, opp_dir], "r": [up + r * 0.25 + opp_dir * 0.2, opp_dir]}
	elif not contact_on and anim_kind != "serve":
		return
	elif anim_kind in ["pass", "dig", "free", "set"] and anim_tech != "over":
		# Baggern: gestreckte Arme, Plattform aus beiden Unterarmen unter dem Ball.
		w = smoothstep(-0.32, -0.06, rel) * (1.0 - smoothstep(0.1, 0.3, rel))
		var plat := b - up * 0.17 + f * 0.07
		# Plattform immer vor dem Koerper (sonst gehen die Arme durch Bauch und Beine)
		var hp: Vector3 = fig.j["hips"].global_position
		var ahead := (plat - hp).dot(f)
		if ahead < 0.4:
			plat += f * (0.4 - ahead)
		# beim Hinfuehren in einem Bogen vor dem Koerper, nicht dicht am Bauch entlang
		if rel < 0.0:
			plat += f * 0.25 * sin(PI * w)
		tg = {"l": plat - r * 0.065, "r": plat + r * 0.065}
		# Haende ineinander: Finger zeigen nach vorn unten, Handflaechen zueinander, Daumen parallel.
		var fd := f * 0.75 - up * 0.65
		hands = {"l": [fd, r + up * 0.3], "r": [fd, -r + up * 0.3]}
	elif anim_kind in ["set", "pass", "dig", "free"] and anim_tech == "over":
		# Pritschen nach Lehrbild und Sportwissenschaft: frueh die Pritschhaltung (Handgelenke etwa
		# 20 cm vor und 10 cm ueber der Stirn, Ellbogen gebeugt und leicht ausserhalb der Schultern,
		# Handflaechen zum Ball, Daumen zu den Augen). Kurz vor dem Kontakt gehen die Haende unter den
		# Ball, der Ball sinkt rund 5 cm in die Haende ein (die Finger umfassen ihn, siehe
		# _hand_shape), dann strecken sich Arme und Koerper in Zielrichtung; die Haende oeffnen sich
		# dabei leicht nach aussen.
		w = smoothstep(-0.95, -0.55, rel) * (1.0 - smoothstep(0.25, 0.45, rel))
		# Seitlich zum Blick gespielte Baelle: die Haende schieben nur wenig zur Seite (sonst kreuzen
		# die Unterarme vor dem Gesicht); den Rest uebernimmt die Koerperdrehung.
		var aim_l := f * aim_h.dot(f) + r * aim_h.dot(r) * 0.35
		var push := (aim_l * (0.55 if anim_kind == "set" else 0.8) + up).normalized()
		var head: Vector3 = fig.j["head"].global_position
		var brow := head + up * 0.13 + f * 0.1  # Stirn (head = Halsgelenk)
		var ready := brow + f * 0.22 + up * 0.1
		var to_ball := (b - brow).normalized()
		# Die Haende liegen hinten unten am Ball (Fingerkuppen am Ball, Handgelenke gut 7 cm dahinter)
		var cdir := (to_ball + f * 0.5).normalized()
		var at_ball := b - cdir * 0.21
		# Der Ball sinkt in die Haende ein (gut 5 cm, etwa 40 % der Kontaktzeit), dann Strecken
		var give := -to_ball * 0.055 * smoothstep(-0.025, -0.004, rel) * (1.0 - smoothstep(0.004, 0.04, rel))
		var follow := push * 0.42 * smoothstep(0.0, 0.2, rel)
		var hb := ready.lerp(at_ball, smoothstep(-0.2, -0.03, rel)) + give + follow
		var open := 0.035 * smoothstep(0.04, 0.2, rel)
		tg = {"l": hb - r * (0.11 + open), "r": hb + r * (0.11 + open)}
		# Ellbogen zeigen nach aussen vorn (etwas breiter als die Schultern), bis sich die Arme strecken.
		for sd in ["l", "r"]:
			var s_sign := -1.0 if sd == "l" else 1.0
			var shp: Vector3 = fig.j["sh_" + sd].global_position
			poles[sd] = shp + r * (0.55 * style.set_elbows * s_sign) + f * 0.1 - up * 0.1
		pole_w = 1.0 - smoothstep(0.04, 0.2, rel)
		# Handflaechen schauen zum Ball (nach dem Kontakt in Zielrichtung), die Finger nach oben und
		# leicht nach aussen, so zeigen die Daumen nach innen zu den Augen (Dreieck vor der Stirn).
		# (Steht der Ball genau ueber dem Kopf, zeigen die Handflaechen trotzdem schraeg nach vorn
		# oben: Handgelenke etwa 45 Grad nach hinten abgeknickt, Finger nach oben hinten.)
		var palm0 := (to_ball + f * 1.1 + up * 0.5).normalized()
		var palm := palm0.lerp(push, smoothstep(0.0, 0.12, rel)).normalized()
		var fing := (up - palm * up.dot(palm)).normalized()
		hands = {"l": [fing - r * 0.08, palm], "r": [fing + r * 0.08, palm]}
	elif (anim_kind == "attack" and (airborne or rel > -0.5)) or (anim_kind == "serve" and airborne):
		# Angriff wie im Volleyball (Bogenspannung): der Ellbogen holt hoch und weit nach hinten aus,
		# die Hand liegt hinter dem Kopf auf Ohrhoehe, die Schlagschulter dreht zurueck und der
		# Oberkoerper spannt sich. Dann fuehrt der Ellbogen nach vorn oben, der Unterarm peitscht
		# hinterher, und getroffen wird mit ganz gestrecktem Arm hoch vor der Schlagschulter.
		# Nachschwung nach vorn unten und quer ueber den Koerper zur linken Huefte.
		# Linkshaender: dieselbe Technik gespiegelt (Schlagseite hs, r zeigt zur Schlagseite).
		var hs := hit_side()
		var os := "r" if hs == "l" else "l"
		var mir := -1.0 if left_handed else 1.0
		r *= mir
		var wt := smoothstep(-0.55, -0.35, rel) * (1.0 - smoothstep(0.3, 0.5, rel))
		var twist := lerpf(-0.5, 0.35, smoothstep(-0.18, 0.1, rel))
		var arch := 0.2 * (1.0 - smoothstep(-0.12, 0.0, rel)) - 0.3 * smoothstep(0.0, 0.15, rel)
		var ch: Node3D = fig.j["chest"]
		ch.quaternion = ch.quaternion * Quaternion(Vector3.UP, twist * wt * mir) * Quaternion(Vector3.RIGHT, arch * wt)
		fig._sync()
		var hit := b - up * 0.07 - f * 0.17
		# Treffen mit ganz gestrecktem Arm: liegt der Treffpunkt naeher an der Schulter als eine
		# Armlaenge, sinkt der Koerper im Kontaktmoment etwas ab, liegt er weiter weg, streckt er sich.
		if airborne:
			var ext := smoothstep(-0.14, -0.02, rel) * (1.0 - smoothstep(0.06, 0.2, rel))
			var need := (hit - (fig.j["sh_" + hs] as Node3D).global_position).length() - ARM_HIT_LEN * fig.root_node.scale.x / 1.075
			fig.root_node.position.y += clampf(need, -0.2, 0.14) * ext
			fig._sync()
		var sh_r: Vector3 = fig.j["sh_" + hs].global_position
		var sh_l: Vector3 = fig.j["sh_" + os].global_position
		var chest: Vector3 = fig.j["chest"].global_position
		# Ausholen: Oberarm seitlich und zurueck, Ellbogen etwa auf Schulterhoehe, Hand hinter dem Kopf.
		var cock := sh_r + up * 0.3 - f * 0.1 + r * 0.08
		var cock_el := sh_r + up * 0.12 + r * 0.45 - f * 0.25
		var lead_el := sh_r + up * 0.45 + r * 0.15 + f * 0.2
		var over := sh_r + up * 0.32 + r * 0.06 + f * 0.04
		# Nachschwung mit fast gestrecktem Arm: schraeg nach vorn unten in Schlagrichtung, dann tief
		# quer vor den Koerper zur linken Huefte (Ziele auf Armlaenge, damit der Ellbogen nicht hochklappt).
		var thru := sh_r + (aim_h * 0.6 + f * 0.2 - r * 0.1 - up * 0.8).normalized() * 0.45
		var cross := sh_r + (f * 0.5 - r * 0.45 - up * 0.9).normalized() * 0.45
		var hand := cock
		pole_w = 1.0
		poles[hs] = cock_el
		if rel >= -0.2 and rel < 0.0:
			var sw := smoothstep(-0.2, -0.01, rel)
			# Hand bleibt zurueck (peitscht spaet), der Ellbogen fuehrt
			var t := pow(sw, 1.5)
			hand = cock * (1.0 - t) * (1.0 - t) + over * 2.0 * (1.0 - t) * t + hit * t * t
			poles[hs] = cock_el.lerp(lead_el, smoothstep(0.0, 0.55, sw))
		elif rel >= 0.0:
			# Ellbogen zeigt beim Nachschwung nach aussen unten (Pol bleibt, damit nichts umklappt)
			poles[hs] = lead_el.lerp(sh_r + r * 0.4 - up * 0.25 + f * 0.1, smoothstep(0.0, 0.12, rel))
			# Richtung um die Schulter drehen (Bogen auf Armlaenge), nicht quer durch den Raum mischen
			var hd := (hit - sh_r).normalized()
			if rel < 0.07:
				hd = hd.slerp((thru - sh_r).normalized(), smoothstep(0.0, 0.07, rel))
			else:
				hd = (thru - sh_r).normalized().slerp((cross - sh_r).normalized(), smoothstep(0.07, 0.18, rel))
			hand = sh_r + hd * 0.45
		tg = {hs: hand}
		w = smoothstep(-0.5, -0.3, rel) * (1.0 - smoothstep(0.3, 0.45, rel))
		if not airborne:
			w *= 0.6
		# Linker Arm zeigt zum Ball, bis der Schlagarm durchzieht, dann zieht er seitlich am Koerper
		# nach unten (gibt dem Schlag Schwung).
		# Richtung drehen statt Punkte mischen: so schwingt der Arm aussen herum und nicht durch die Brust.
		var ld := (b - sh_l).normalized()
		if rel > -0.1:
			var lt := smoothstep(-0.1, 0.06, rel)
			ld = ld.slerp((f * 0.3 - up * 0.85 - r * 0.05).normalized(), lt)
			ld = (ld - r * 0.15 * sin(PI * lt)).normalized()
		tg[os] = sh_l + ld * 0.6
		wl = smoothstep(-0.5, -0.3, rel) * (1.0 - smoothstep(0.12, 0.3, rel))
		# Hand: beim Ausholen Handflaeche nach vorn, im Treffpunkt flach hinter dem Ball,
		# danach klappt das Handgelenk ab (Finger ueber den Ball nach vorn unten).
		var snap := smoothstep(0.0, 0.1, rel)
		var fingers := up.lerp(aim_h - up * 0.9, snap)
		var palm := (aim_h - up * 0.25).lerp(-up - aim_h * 0.9, snap)
		hands = {hs: [fingers, palm], os: [b - sh_l, -r]}
		r *= mir
	elif anim_kind == "serve":
		w = smoothstep(-0.12, -0.015, rel) * (1.0 - smoothstep(0.03, 0.16, rel))
		# Standaufschlag (der Sprungaufschlag laeuft wie der Angriff, siehe oben)
		tg = {hit_side(): b - up * 0.02 - f * 0.14}
		hands = {hit_side(): [up, aim_h]}
	dbg_tg = tg
	if w <= 0.001 or tg.is_empty():
		return
	# Beim Pritschen bleiben die Ellbogen aussen (staerkere Daempfung haelt die Haltung).
	var over_set := anim_kind in ["set", "pass", "dig", "free"] and anim_tech == "over"
	var miss := 0.0
	for sd in tg:
		var ws := wl if (sd != _hit_tg and wl >= 0.0) else w
		if ws <= 0.001:
			continue
		# Hand am Ball: ganze Kette von der Huefte bis zur Hand haelt das Ziel, aber nur rund um
		# den Kontakt (und beim Block). Davor und danach glaettet die Physik die Bewegung.
		var near := 1.0 if block_pose else 1.0 - smoothstep(0.04, 0.14, absf(rel))
		if over_set:
			# Pritschhaltung frueh und ruhig halten (sonst schwingen die Arme erst spaet hoch)
			near = maxf(near, smoothstep(-0.95, -0.6, rel) * (1.0 - smoothstep(0.25, 0.45, rel)))
		if (anim_kind == "attack" or anim_kind == "serve") and airborne and sd == hit_side():
			# Der Schlag ist schnell (Peitsche): der Arm folgt der Bahn eng, statt nachzuschleifen.
			near = maxf(near, smoothstep(-0.3, -0.18, rel) * (1.0 - smoothstep(0.25, 0.4, rel)))
		var pw := smoothstep(0.3, 0.9, ws) * near
		for k in ["sh_" + sd, "el_" + sd, "wr_" + sd, "chest", "hips"]:
			fig.pin[k] = maxf(fig.pin.get(k, 0.0), pw)
		var res: float
		if over_set:
			res = fig.ik_arm(sd, tg[sd], ws, 14, 0.12, poles.get(sd, Vector3.INF), pole_w)
		else:
			res = fig.ik_arm(sd, tg[sd], ws, 10, 0.02, poles.get(sd, Vector3.INF), pole_w)
		if sd == _hit_tg or over_set:
			miss = maxf(miss, res * ws)
	# In der Luft: fehlt dem gestreckten Arm noch etwas bis zum Ball, streckt sich der ganze
	# Koerper ein Stueck nach (Schultergürtel, hoechstens 20 cm), statt vorbeizuschlagen.
	if (airborne or anim_kind == "serve") and miss > 0.02 and tg.has(_hit_tg):
		var wr: Vector3 = fig.j["wr_" + _hit_tg].global_position
		var lift: Vector3 = ((tg[_hit_tg] as Vector3) - wr).limit_length(0.25)
		lift.y = clampf(lift.y, 0.0, 0.2 if airborne else 0.05)
		if not airborne:
			lift.x = 0.0
			lift.z = 0.0
		# Verschiebung in Weltrichtung -> Figur-Raum (die Figur ist gedreht)
		fig.root_node.position += fig.global_basis.orthonormalized().inverse() * lift
		fig._sync()
		fig.ik_arm(_hit_tg, tg[_hit_tg], w, 10, 0.02, poles.get(_hit_tg, Vector3.INF), pole_w)
	fig._sync()
	for sd in hands:
		var ws := wl if (sd != _hit_tg and wl >= 0.0) else w
		fig.orient_hand(sd, hands[sd][0], hands[sd][1], ws)
	fig._sync()


## Handform je Seite fuer die Finger (HumanFigure.hand): curl = Beugen, spread = Spreizen,
## thumb = Daumen abspreizen, grip = zugreifen (die Finger schliessen, bis der Ball sie aufhaelt).
func _hand_shape() -> void:
	if not fig.has_fingers:
		return
	var rel := now - anim_t
	var shape := HumanFigure.FINGER_REST.duplicate()
	var both := true
	if block_pose and airborne:
		# Block: Finger weit gespreizt und fest
		shape = {"curl": 0.1, "spread": 0.4, "thumb": 0.6, "grip": 0.0}
	elif not contact_on and anim_kind != "serve":
		pass
	elif anim_kind in ["set", "pass", "dig", "free"] and anim_tech == "over":
		# Pritschen: Korb aus gespreizten, leicht gebeugten Fingern; im Kontakt greifen die Finger
		# um den Ball (Fingerkuppen, Daumen und Zeigefinger tragen), danach weit geoeffnet.
		var k := smoothstep(-0.95, -0.5, rel) * (1.0 - smoothstep(0.35, 0.6, rel))
		var grip := smoothstep(-0.025, -0.004, rel) * (1.0 - smoothstep(0.008, 0.035, rel))
		var rls := smoothstep(0.03, 0.12, rel)
		shape = {"curl": lerpf(0.4, 0.08, rls), "spread": lerpf(0.3, 0.38, rls), "thumb": lerpf(1.4, 1.0, rls), "grip": 0.65 * grip}
		shape = _mix_shape(HumanFigure.FINGER_REST, shape, k)
	elif anim_kind in ["pass", "dig", "free", "set"]:
		# Baggern: Haende ineinander, Finger locker gebeugt, Daumen nebeneinander
		var k := smoothstep(-0.32, -0.06, rel) * (1.0 - smoothstep(0.1, 0.3, rel))
		shape = _mix_shape(HumanFigure.FINGER_REST, {"curl": 0.55, "spread": 0.0, "thumb": 0.05, "grip": 0.0}, k)
	elif anim_kind in ["attack", "serve"]:
		# Schlag: offene, feste Hand; im Treffpunkt legt sie sich ueber den Ball (Topspin)
		both = false
		var k := smoothstep(-0.3, -0.1, rel) * (1.0 - smoothstep(0.15, 0.35, rel))
		var grip := smoothstep(-0.02, 0.0, rel) * (1.0 - smoothstep(0.03, 0.09, rel))
		shape = _mix_shape(HumanFigure.FINGER_REST, {"curl": 0.1, "spread": 0.14, "thumb": 0.35, "grip": 0.6 * grip}, k)
	var hs := hit_side()
	fig.hand[hs] = shape
	fig.hand["r" if hs == "l" else "l"] = shape if both else HumanFigure.FINGER_REST.duplicate()


static func _mix_shape(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var out := {}
	for key in a:
		out[key] = lerpf(a[key], b.get(key, a[key]), k)
	return out


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
	# Eigenheit zwischen den Ballwechseln (je Spieler eine), immer wieder fuer ein paar Sekunden
	var t := now * style.bob_rate + style.bob_phase * 3.0
	var on := smoothstep(0.0, 0.25, fposmod(t, 7.0) / 7.0) * (1.0 - smoothstep(0.55, 0.75, fposmod(t, 7.0) / 7.0))
	if on <= 0.001:
		return p
	var q := p.duplicate()
	match style.idle:
		0:
			# Gewicht von einem Bein aufs andere, ein Knie locker
			var w := sin(t * 1.3)
			q["hips"] = Vector3(0, 0, w * 0.06)
			_leg(q, "l", 0.1 + maxf(w, 0.0) * 0.15, 0.15 + maxf(w, 0.0) * 0.35, 0.08)
			_leg(q, "r", 0.1 + maxf(-w, 0.0) * 0.15, 0.15 + maxf(-w, 0.0) * 0.35, 0.08)
		1:
			# Auf den Fussballen wippen und die Arme ausschuetteln
			var b := absf(sin(t * 7.0))
			_leg(q, "l", 0.25 + b * 0.12, 0.4 + b * 0.25, 0.1)
			_leg(q, "r", 0.25 + b * 0.12, 0.4 + b * 0.25, 0.1)
			var sh := sin(t * 18.0) * 0.12
			_arm(q, "l", 0.15 + sh, 0.2, 0.3 - sh)
			_arm(q, "r", 0.15 - sh, 0.2, 0.3 + sh)
		2:
			# Haende in die Hueften
			_arm(q, "l", 0.25, 0.75, 1.6, 0.3)
			_arm(q, "r", 0.25, 0.75, 1.6, 0.3)
			q["chest"] = Vector3(0.04, 0, 0)
		3:
			# Haende auf die Knie, kurz durchschnaufen
			q["hips"] = Vector3(-0.45, 0, 0)
			q["chest"] = Vector3(-0.35, 0, 0)
			q["head"] = Vector3(0.55, 0, 0)
			_arm(q, "l", 0.75, 0.12, 0.25)
			_arm(q, "r", 0.75, 0.12, 0.25)
			_leg(q, "l", 0.55, 0.45, 0.12)
			_leg(q, "r", 0.55, 0.45, 0.12)
	return _mix(p, q, on)


func _p_ready() -> Dictionary:
	# Meshy: Bereitschaftshaltung, langsam vor und zurueck abgespielt (wirkt wie Wippen).
	var cu := 0.05 + 0.55 * (0.5 - 0.5 * cos(now * style.bob_rate * PI / 2.2 + style.bob_phase))
	var clip := HumanFigure.clip_pose("vb_bereitschaft", cu, false)
	if not clip.is_empty():
		MoveStyle.legs(clip, style.stance_depth, style.stance_width)
		return clip
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
		# Laufclip (hohe Fersen) erst bei schnellem Laufen, sonst Gehen: kurze Wege zur Position
		# sehen sonst wie Stelzen aus.
		p = run if walk.is_empty() else _mix(walk, run, smoothstep(0.55, 0.95, a))
		# langsam: Knie weniger gebeugt (Fuss schwingt flacher durch, Schrittlaenge bleibt)
		var flat := lerpf(0.7, 1.0, smoothstep(0.2, 0.9, a))
		for k in ["kn_l", "kn_r"]:
			var v0: Vector3 = p[k]
			p[k] = Vector3(v0.x * flat, v0.y, v0.z)
		# Bei hohem Tempo weiter ausschreiten (Beugung von Huefte und Knie verstaerken).
		if _stride_amp > 1.001:
			for k in ["hip_l", "hip_r", "kn_l", "kn_r"]:
				var v: Vector3 = p[k]
				p[k] = Vector3(v.x * _stride_amp, v.y, v.z)
	# Armschwung je Spieler staerker oder schwaecher
	if absf(style.arm_swing - 1.0) > 0.01:
		for k in ["sh_l", "sh_r"]:
			var v: Vector3 = p.get(k, Vector3.ZERO)
			p[k] = Vector3(v.x * style.arm_swing, v.y, v.z)
	var side_clip := HumanFigure.clip_pose("seitschritt_rechts" if _move_side > 0.0 else "seitschritt_links", fposmod(_run_phase / 4.4, 1.0))
	if side_w > 0.0 and not side_clip.is_empty():
		p = _mix(p, side_clip, side_w)
	elif side_w > 0.0:
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
	# Je Spieler (und je Anlauf ein wenig) tiefer oder hoeher, Arme weiter oder weniger weit hinten
	var d := style.approach_depth * (1.0 + 0.05 * MoveStyle.noise(anim_t, number))
	var p := {"hips": Vector3(-0.3 * d, 0, 0), "chest": Vector3(-0.35 * d, 0, 0), "head": Vector3(0.5, 0, 0)}
	_arm(p, "l", -1.0 * d, 0.15, 0.2)
	_arm(p, "r", -1.0 * d, 0.15, 0.2)
	_leg(p, "l", 0.8 * d, 1.3 * d, 0.1)
	_leg(p, "r", 0.8 * d, 1.3 * d, 0.1)
	return p


func _p_block() -> Dictionary:
	var p := _p_block_code()
	# Meshy-Block: Beine und Huefte (Ausholen, Absprung, Landung), Arme bleiben am Netz gesteuert.
	var cu := 0.2
	if airborne:
		cu = 0.3 + clampf((now - _takeoff_t) / 0.6, 0.0, 1.0) * 0.15
	var clip := HumanFigure.clip_pose("vb_block", cu, false)
	for k in ["hips", "hip_l", "kn_l", "an_l", "hip_r", "kn_r", "an_r"]:
		if clip.has(k):
			p[k] = clip[k]
	return p


func _p_block_code() -> Dictionary:
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
	var clip := HumanFigure.clip_pose("vb_hechtbagger", 0.08 + kd * 0.42, false)
	if not clip.is_empty():
		return clip
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
	var k := 1.0 - clampf((celebrate_until - now) / 1.6, 0.0, 1.0)  # 0..1 durch den Jubel
	var clip := HumanFigure.clip_pose("jubel_faust", k, false)
	if style.cheer == 0 and not clip.is_empty():
		return clip
	var p := {"chest": Vector3(0.15, 0, 0), "head": Vector3(0.5, 0, 0)}
	_leg(p, "l", 0.1, 0.15, 0.1)
	_leg(p, "r", 0.1, 0.15, 0.1)
	match style.cheer:
		2:
			# "Komm schon!": Faust nach unten gezogen, Oberkoerper nach vorn, in die Knie
			var pull := smoothstep(0.1, 0.25, k) * (1.0 - smoothstep(0.8, 1.0, k))
			p = {"hips": Vector3(-0.25 * pull, 0, 0), "chest": Vector3(-0.35 * pull, 0, 0), "head": Vector3(0.45, 0, 0)}
			_arm(p, "r", lerpf(0.3, 0.9, pull), 0.35, lerpf(0.4, 2.0, pull))
			_arm(p, "l", 0.35, 0.3, 0.9)
			_leg(p, "l", 0.45 * pull + 0.1, 0.8 * pull + 0.15, 0.18)
			_leg(p, "r", 0.45 * pull + 0.1, 0.8 * pull + 0.15, 0.18)
		3:
			# Klatschen vor der Brust
			var c := 0.5 + 0.5 * sin(now * 14.0)
			_arm(p, "l", 1.25, lerpf(-0.05, 0.35, c), 0.7)
			_arm(p, "r", 1.25, lerpf(-0.05, 0.35, c), 0.7)
		_:
			# Beide Arme hoch und pumpen
			var pump := sin(now * 9.0 + number) * 0.25
			_arm(p, "l", 2.7 + pump, 0.55, 0.7)
			_arm(p, "r", 2.7 - pump, 0.55, 0.7)
	return p


## Meshy-Animation einmal abspielen: Stuetzpunkte [[rel, u], ...] bilden die Zeit zum
## Ballkontakt (rel) auf den Anteil u der Animation ab (dazwischen linear, ausserhalb geklemmt).
static func _clip_at(clip: String, rel: float, keys: Array) -> Dictionary:
	var u: float = keys[0][1]
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if rel >= a[0]:
			u = lerpf(a[1], b[1], clampf((rel - a[0]) / (b[0] - a[0]), 0.0, 1.0))
	return HumanFigure.clip_pose(clip, u, false)


## Zeitpunkte der Meshy-Volleyball-Animationen (aus den Bildfolgen abgelesen)
## kern_*: Meshy-Kernanimationen (Text-to-Motion, nach echter Technik beschrieben)
const SPIKE_KEYS := [[-1.1, 0.18], [-0.404, 0.40], [0.0, 0.60], [0.4, 0.70], [0.6, 0.78]]
const SET_KEYS := [[-0.7, 0.17], [-0.15, 0.42], [0.0, 0.47], [0.35, 0.56]]
const BUMP_KEYS := [[-0.6, 0.3], [0.0, 0.58], [0.35, 0.7]]


static func _mix(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	if w <= 0.0:
		return a
	if w >= 1.0:
		return b
	var out := {}
	for k in HumanFigure.JOINTS:
		out[k] = (a.get(k, Vector3.ZERO) as Vector3).lerp(b.get(k, Vector3.ZERO), w)
	return out


## Nach dem Hechten: aus der Bauchlage hochdruecken und aufstehen (zweite Haelfte des
## Meshy-Hechtbaggers, schneller abgespielt), statt mit einem Ruck im Stand zu sein. Wer schon
## losrennt, steht schneller auf.
const GETUP_T := 0.7
var _getup := 0.0
var _was_dive := false


func _target_pose() -> Dictionary:
	var p := _target_pose_main()
	if _getup > 0.0 and dive_timer <= 0.0:
		var k := 1.0 - _getup / GETUP_T
		var clip := HumanFigure.clip_pose("vb_hechtbagger", 0.5 + 0.48 * k, false)
		if not clip.is_empty():
			p = _mix(clip, p, smoothstep(0.55, 1.0, k))
			_stiff = 24.0
	return p


func _target_pose_main() -> Dictionary:
	if dive_timer > 0.0:
		_stiff = 30.0
		return _p_dive()
	if celebrate_until > now:
		_stiff = 16.0
		return _p_celebrate()
	var rel := now - anim_t
	if anim_kind == "serve_hold":
		return _mix(_mirror(_p_serve_hold()), _p_run(_run_amt), clampf(_run_amt * 2.0, 0.0, 1.0))
	if anim_kind == "serve" and rel < 0.5:
		_stiff = 42.0
		return _mirror(_p_serve(rel, anim_tech == "jump"))
	if block_pose:
		_stiff = 30.0
		return _p_block()
	if anim_kind == "attack" and rel < 0.5:
		var clip := _mirror(_clip_at("kern_angriff", rel, SPIKE_KEYS))
		if not clip.is_empty() and rel > -1.1:
			# Meshy-Angriff: Anlauf, Absprung, Schlag, Landung als eine Bewegung.
			var run0 := _mix(_p_ready(), _p_run(maxf(_run_amt, 0.3)), clampf(_run_amt * 1.6, 0.0, 1.0))
			_stiff = 45.0 if airborne else 28.0
			if airborne:
				# Beine in der Luft kommen aus der eigenen, symmetrischen Haltung: der Clip
				# schleudert oft ein Bein einzeln durch die Luft.
				var own := _mirror(_p_spike(rel))
				for k in ["hip_l", "kn_l", "an_l", "hip_r", "kn_r", "an_r"]:
					clip[k] = (clip[k] as Vector3).lerp(own.get(k, Vector3.ZERO), 0.95)
			var wi := smoothstep(-1.1, -0.85, rel) * (1.0 - smoothstep(0.3, 0.5, rel))
			return _mix(run0, clip, wi)
		if airborne:
			_stiff = 45.0
			return _mirror(_p_spike(rel))
		if rel > -1.0:
			# Anlauf weich einblenden statt hart umschalten.
			var wa := smoothstep(-1.0, -0.55, rel)
			var run := _mix(_p_ready(), _p_run(maxf(_run_amt, 0.3)), clampf(_run_amt * 1.6, 0.0, 1.0))
			_stiff = lerpf(22.0, 26.0, wa)
			return _mix(run, _mirror(_p_approach()), wa)
	_stiff = 22.0 + _run_amt * 10.0
	var base := _p_ready() if alert else _p_idle()
	if _run_amt > 0.05:
		base = _mix(base, _p_run(_run_amt), clampf(_run_amt * 1.6, 0.0, 1.0))
	if airborne:
		base = _mix(base, _mirror(_p_spike(-0.5)), 0.6)
	# Landung: kurz in die Knie federn.
	var land := 1.0 - clampf((now - _land_t) / 0.35, 0.0, 1.0)
	if land > 0.0:
		base = _mix(base, _p_land(), sin(land * PI * 0.5) * 0.8)
		_stiff = 30.0
	# Taste gehalten: schon vorher in die Grundhaltung fuer Baggern oder Pritschen.
	if prep != "" and not airborne:
		base = _mix(base, _p_over(-0.45) if prep == "over" else _p_under(-0.45), 0.8)
	if anim_kind in ["pass", "dig", "set", "free"] and rel > -0.9 and rel < 0.6:
		var tech := _p_over(rel) if anim_tech == "over" else _p_under(rel)
		var w := smoothstep(-0.9, -0.35, rel) * (1.0 - smoothstep(0.25, 0.6, rel))
		base = _mix(base, tech, w)
		_stiff = 20.0
	_crouch_drop = lerpf(_crouch_drop, crouch_want, clampf(_dt_pose * 14.0, 0.0, 1.0))
	if _crouch_drop > 0.005:
		# Hocke: Oberschenkel nach vorn, Knie doppelt gebeugt, Fuss bleibt flach; Oberkoerper neigt sich
		var a := acos(clampf(1.0 - _crouch_drop / 0.9, -1.0, 1.0))
		for sd in ["l", "r"]:
			base["hip_" + sd] = base.get("hip_" + sd, Vector3.ZERO) + Vector3(a, 0, 0)
			base["kn_" + sd] = base.get("kn_" + sd, Vector3.ZERO) + Vector3(-2.0 * a, 0, 0)
			base["an_" + sd] = base.get("an_" + sd, Vector3.ZERO) + Vector3(a, 0, 0)
		base["chest"] = base.get("chest", Vector3.ZERO) - Vector3(0.35 * a, 0, 0)
	return base


## Pritschen: Meshy-Animation, falls vorhanden, sonst die eigene Haltung.
func _p_over(rel: float) -> Dictionary:
	var clip := _clip_at("kern_pritschen", rel, SET_KEYS)
	if clip.is_empty():
		return _p_set(rel)
	# Eigene Pritschhaltung (Ellbogen aussen, tiefe Knie, Streckung aus den Beinen) dazumischen,
	# damit man das Pritschen deutlich sieht.
	var own := _p_set(rel)
	for k in ["hips", "chest", "head", "hip_l", "kn_l", "an_l", "hip_r", "kn_r", "an_r"]:
		if own.has(k):
			clip[k] = (clip.get(k, Vector3.ZERO) as Vector3).lerp(own[k], 0.6)
	return clip


## Baggern: Meshy-Kernanimation (gestreckte Arme, Schwung aus den Beinen), sonst eigene Haltung.
func _p_under(rel: float) -> Dictionary:
	var clip := _clip_at("kern_baggern", rel, BUMP_KEYS)
	var p := _p_bump(rel) if clip.is_empty() else clip
	MoveStyle.legs(p, style.bump_depth * (1.0 + 0.04 * MoveStyle.noise(anim_t, number + 7)), 0.0)
	return p


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
	fig.apply(HumanFigure.mix_capture(a[8], b[8], w))
	fig.rotation.y = lerp_angle(a[9], b[9], w)
	_yaw = fig.rotation.y
	_root_y = fig.root_node.position.y
	_last_pos = position
