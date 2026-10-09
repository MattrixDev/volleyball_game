class_name CrowdView
extends Node3D
## Zuschauer auf den Tribuenen: einfache Figuren in Vereinsfarben, die bei Punkten
## aufspringen. Eine MultiMesh-Instanz je Koerperteil, damit es schnell bleibt.

const ROWS := 4
const SPACING := 0.62

var team_colors: Array = [Color(0.16, 0.38, 0.86), Color(0.85, 0.2, 0.18)]
var _bodies: MultiMeshInstance3D
var _heads: MultiMeshInstance3D
var _base: Array = []  # [Position, Phase, Team (0/1/-1 neutral), Temperament]
var _jump := [0.0, 0.0]  # Aufregung je Fanblock
var _neutral := 0.0
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 3
	# Tribuenen wie in main.gd: Stufe i ist 0,6 + i*0,6 hoch, 1,2 m tief, ab |z| = 13.
	for side in [-1.0, 1.0]:
		for i in ROWS:
			var h := 0.6 + i * 0.6
			var z: float = side * (13.0 + i * 1.2)
			var x := -14.5
			while x <= 14.5:
				if _rng.randf() < 0.86:
					var fan := 0 if x < -1.5 else (1 if x > 1.5 else -1)
					if _rng.randf() < 0.25:
						fan = -1
					var jitter := Vector3(_rng.randf_range(-0.12, 0.12), 0.0, _rng.randf_range(-0.15, 0.15))
					_base.append([Vector3(x, h, z) + jitter, _rng.randf() * TAU, fan, _rng.randf_range(0.6, 1.2)])
				x += SPACING
	_bodies = _make_mm(_body_mesh(), true)
	_heads = _make_mm(_head_mesh(), false)
	for i in _base.size():
		var b: Array = _base[i]
		var c: Color
		if b[2] >= 0 and _rng.randf() < 0.75:
			c = (team_colors[b[2]] as Color).lerp(Color.WHITE, _rng.randf_range(0.0, 0.25))
		else:
			c = Color.from_hsv(_rng.randf(), _rng.randf_range(0.1, 0.5), _rng.randf_range(0.3, 0.85))
		_bodies.multimesh.set_instance_color(i, c)
		var skin := Color(0.93, 0.76, 0.62).lerp(Color(0.45, 0.3, 0.2), _rng.randf() * 0.8)
		_heads.multimesh.set_instance_color(i, skin)
	_update(0.0)


func _body_mesh() -> Mesh:
	var cap := CapsuleMesh.new()
	cap.radius = 0.2
	cap.height = 0.9
	cap.radial_segments = 8
	cap.rings = 2
	return cap


func _head_mesh() -> Mesh:
	var s := SphereMesh.new()
	s.radius = 0.12
	s.height = 0.24
	s.radial_segments = 8
	s.rings = 4
	return s


func _make_mm(mesh: Mesh, _body: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = _base.size()
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
	_update(real)


func _update(_d: float) -> void:
	for i in _base.size():
		var b: Array = _base[i]
		var ex: float = _neutral if b[2] < 0 else _jump[b[2]]
		var ph: float = b[1]
		# Ruhig: leichtes Wippen. Aufgeregt: Springen mit hochgerissenen Armen (gestreckt).
		var idle := sin(_time * 1.3 + ph) * 0.02
		var hop: float = absf(sin(_time * 7.5 * b[3] + ph)) * 0.35 * ex * b[3]
		var stretch := 1.0 + 0.15 * ex
		var p: Vector3 = b[0] + Vector3(0, 0.45 + idle + hop, 0)
		var basis := Basis().scaled(Vector3(1.0, stretch, 1.0))
		_bodies.multimesh.set_instance_transform(i, Transform3D(basis, p))
		_heads.multimesh.set_instance_transform(i, Transform3D(Basis(), p + Vector3(0, 0.45 * stretch + 0.12, 0)))
