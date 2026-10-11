class_name CrowdView
extends Node3D
## Zuschauer auf den Tribuenen (Laengsseiten und hinter den Grundlinien): sitzende Low-Poly-
## Figuren aus Blender (assets/models/fan.glb) in Vereinsfarben, die bei Punkten aufspringen
## und die Arme hochreissen. Je Koerperteil eine MultiMesh-Instanz, damit es schnell bleibt.

const ROWS := 4
const SPACING := 0.62

var team_colors: Array = Teams.playing().map(func(t): return t.jersey)
const SEAT := 0.42  # Sitzflaeche ueber der Stufe (arena.glb)
var _bodies: MultiMeshInstance3D
var _heads: MultiMeshInstance3D
var _arms: MultiMeshInstance3D  # zwei je Zuschauer
var _base: Array = []  # [Position, Phase, Team (0/1/-1 neutral), Temperament, Blickrichtung (Yaw)]
var _jump := [0.0, 0.0]  # Aufregung je Fanblock
var _neutral := 0.0
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 3
	# Laengsseiten: Stufe i ist 0,6 + i*0,6 hoch, 1,2 m tief, ab |z| = 13 (wie arena.gd).
	for side in [-1.0, 1.0]:
		for i in ROWS:
			var h := 0.6 + i * 0.6
			var z: float = side * (13.08 + i * 1.2)
			var x := -15.0
			while x <= 15.0:
				var fan := 0 if x < -2.0 else (1 if x > 1.0 else -1)
				_add(Vector3(x, h, z), fan, 0.0 if side > 0.0 else PI)
				x += SPACING
	# Hinter den Grundlinien: ab |x| = 18,5, nur Fans des Teams auf dieser Seite
	for side in [-1.0, 1.0]:
		for i in ROWS:
			var h := 0.6 + i * 0.6
			var x: float = side * (18.58 + i * 1.2)
			var z := -10.5
			while z <= 10.5:
				_add(Vector3(x, h, z), 0 if side < 0.0 else 1, side * PI / 2.0)
				z += SPACING
	var fan: Node3D = preload("res://assets/models/fan.glb").instantiate()
	var parts := {}
	for mi in fan.find_children("*", "MeshInstance3D", true, false):
		parts[String(mi.name)] = (mi as MeshInstance3D).mesh
	fan.free()
	_bodies = _make_mm(parts["fan_body"], _base.size())
	_heads = _make_mm(parts["fan_head"], _base.size())
	_arms = _make_mm(parts["fan_arm"], _base.size() * 2)
	for i in _base.size():
		var b: Array = _base[i]
		var c: Color
		if b[2] >= 0 and _rng.randf() < 0.7:
			c = (team_colors[b[2]] as Color).lerp(Color(0.85, 0.84, 0.8), _rng.randf_range(0.0, 0.25))
		else:
			c = Color.from_hsv(_rng.randf(), _rng.randf_range(0.1, 0.4), _rng.randf_range(0.35, 0.85))
		_bodies.multimesh.set_instance_color(i, c)
		var skin: Color = VPlayer.SKINS[_rng.randi() % VPlayer.SKINS.size()]
		_heads.multimesh.set_instance_color(i, skin)
		_arms.multimesh.set_instance_color(i * 2, c.darkened(0.1))
		_arms.multimesh.set_instance_color(i * 2 + 1, c.darkened(0.1))
	_update()


func _add(p: Vector3, fan: int, yaw: float) -> void:
	if _rng.randf() > 0.85:
		return
	if _rng.randf() < 0.25:
		fan = -1
	_base.append([p, _rng.randf() * TAU, fan, _rng.randf_range(0.6, 1.2), yaw])


func _make_mm(mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Fans eines Teams jubeln (team = -1: alle, zum Beispiel bei einem tollen Ballwechsel).
func cheer(team: int, strength := 1.0) -> void:
	if team < 0:
		_jump = [maxf(_jump[0], strength), maxf(_jump[1], strength)]
		_neutral = maxf(_neutral, strength)
	else:
		_jump[team] = maxf(_jump[team], strength)
		_neutral = maxf(_neutral, strength * 0.5)


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	_time += real
	for t in 2:
		_jump[t] = maxf(0.0, _jump[t] - real * 0.4)
	_neutral = maxf(0.0, _neutral - real * 0.4)
	_update()


func _update() -> void:
	for i in _base.size():
		var b: Array = _base[i]
		var ex: float = _neutral if b[2] < 0 else _jump[b[2]]
		var ph: float = b[1]
		# Ruhig: leichtes Wippen, Arme unten. Aufgeregt: Springen, Arme hoch und winken.
		var idle := sin(_time * 1.3 + ph) * 0.02
		var hop: float = absf(sin(_time * 7.5 * b[3] + ph)) * 0.3 * ex * b[3]
		var raise: float = clampf(ex * 1.6, 0.0, 1.0)
		# Sitzt auf der Schale; aufgeregt steht er halb auf
		var p: Vector3 = b[0] + Vector3(0, SEAT + idle + hop + raise * 0.25, 0)
		var yaw := Basis(Vector3.UP, b[4])
		_bodies.multimesh.set_instance_transform(i, Transform3D(yaw, p))
		var nod := Basis(Vector3(1, 0, 0), sin(_time * 0.7 + ph) * 0.08)
		_heads.multimesh.set_instance_transform(i, Transform3D(yaw * nod, p + yaw * Vector3(0, 0.65, 0)))
		for a in 2:
			var sx := -1.0 if a == 0 else 1.0
			var wave := sin(_time * 9.0 * b[3] + ph + a) * 0.25 * raise
			# Arm haengt (Winkel 0) oder zeigt nach oben (PI), Drehpunkt an der Schulter
			var ang := lerpf(0.15, 2.8, raise) + wave
			var arm_basis := yaw * Basis(Vector3(0, 0, 1), sx * ang * 0.9) * Basis(Vector3(1, 0, 0), ang * 0.3)
			var shoulder := p + yaw * Vector3(sx * 0.2, 0.58, 0)
			_arms.multimesh.set_instance_transform(i * 2 + a, Transform3D(arm_basis, shoulder))
