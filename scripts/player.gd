class_name VPlayer
extends Node3D
## Ein Spieler: laeuft zu einem Ziel, springt, hechtet. Gesteuert wird er vom Match
## (KI-Laufwege) oder ueber manual_dir vom Menschen.

const G := 9.81
const JUMP_V := 3.96  # ergibt ca. 0,80 m Sprunghoehe
const SPIKE_REACH := 2.45  # Handhoehe im Stand beim Angriff
const BLOCK_REACH := 2.45  # Handhoehe im Stand beim Block

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

var _rig: Node3D
var _tag: Label3D
var _ring: MeshInstance3D
var _arms: Array = []
var _torso: MeshInstance3D


func setup(p_team: int, p_role: String, tag_letter: String, p_number: int, color: Color) -> void:
	team = p_team
	role = p_role
	number = p_number
	side = -1.0 if team == 0 else 1.0

	_rig = Node3D.new()
	add_child(_rig)

	var torso := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.27
	cap.height = 1.62
	torso.mesh = cap
	torso.material_override = _mat(color)
	_torso = torso
	torso.position.y = 0.81
	_rig.add_child(torso)

	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	head.mesh = sphere
	head.material_override = _mat(Color(0.93, 0.76, 0.62))
	head.position.y = 1.80
	_rig.add_child(head)

	for i in 2:
		var arm := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.09, 0.95, 0.09)
		arm.mesh = box
		arm.material_override = _mat(color.darkened(0.15))
		_rig.add_child(arm)
		_arms.append(arm)
	_pose_arms()

	_tag = Label3D.new()
	_tag.text = "%s%d" % [tag_letter, number]
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = true
	_tag.font_size = 40
	_tag.outline_size = 10
	_tag.pixel_size = 0.006
	_tag.modulate = Color(1, 1, 1, 0.85)
	_tag.position.y = 2.25
	add_child(_tag)

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.54
	_ring.mesh = torus
	var rm := _mat(Color(1.0, 0.9, 0.1))
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = rm
	_ring.scale = Vector3(1, 0.15, 1)
	_ring.position.y = 0.02
	_ring.visible = false
	add_child(_ring)


## Neue Identitaet (Wechsel, Libero): Rolle, Nummer und Trikotfarbe tauschen.
func change_identity(p_role: String, tag_letter: String, p_number: int, color: Color) -> void:
	role = p_role
	number = p_number
	(_torso.material_override as StandardMaterial3D).albedo_color = color
	for arm in _arms:
		(arm.material_override as StandardMaterial3D).albedo_color = color.darkened(0.15)
	_tag.text = "%s%d" % [tag_letter, number]


func set_side(s: float) -> void:
	side = s


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m


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


func _pose_arms() -> void:
	for i in 2:
		var arm: MeshInstance3D = _arms[i]
		var sz := -0.22 if i == 0 else 0.22
		if airborne and block_pose:
			# Beide Arme hoch, Haende seitlich verschoben und leicht ueber das Netz.
			arm.position = Vector3(-side * hand_reach * 0.8, 1.95, sz * 0.85 + hand_shift)
			arm.rotation = Vector3(-hand_shift * 0.6, 0.0, side * hand_reach * 1.2)
		elif airborne:
			# Schlagarm hoch, anderer Arm vorn.
			arm.position = Vector3(0.0, 1.95 if i == 1 else 1.4, sz + (lean * 0.15 if i == 1 else 0.0))
			arm.rotation = Vector3(lean * 0.3 if i == 1 else 0.0, 0.0, 0.0 if i == 1 else -side * 1.0)
		else:
			arm.position = Vector3(0.0, 1.0, sz * 1.45)
			arm.rotation = Vector3.ZERO


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

	_rig.position.y = jump_h
	_pose_arms()
	if dive_timer > 0.0:
		dive_timer -= delta
		var k := clampf(dive_timer / 0.7, 0.0, 1.0)
		_rig.rotation.z = side * deg_to_rad(65.0) * sin(k * PI)
	else:
		_rig.rotation.z = 0.0
