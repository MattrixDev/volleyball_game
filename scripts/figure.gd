class_name HumanFigure
extends Node3D
## Spielerfigur: das in Blender gebaute Modell (assets/models/player.glb, erzeugt von
## tools/blender/build_player.py) mit Skelett. Die Posen werden wie bisher als Gelenkwinkel
## gesetzt (siehe pose()); unsichtbare Gelenk-Knoten tragen die Winkel und jedes Bild werden
## die Knochen des Modells danach ausgerichtet. Blickrichtung ist lokal -Z.

const JOINTS := ["hips", "chest", "head", "sh_l", "el_l", "wr_l", "sh_r", "el_r", "wr_r", "hip_l", "kn_l", "an_l", "hip_r", "kn_r", "an_r"]

static var _mesh_cache := {}

var j := {}  # Gelenkname -> Node3D
var root_node: Node3D  # traegt den ganzen Koerper (Hoehe, Kippen beim Hechten)
var hips_height := 1.02
var _mats := {}
var _vel := {}  # Gelenk -> Winkelgeschwindigkeit (pose_spring)
var _num_back: Label3D
var _num_front: Label3D


## Ein Primitiv in ein flach schattiertes Mesh verwandeln (Normalen je Dreieck).
static func flat(key: String, prim: PrimitiveMesh) -> ArrayMesh:
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var arr := prim.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var center := Vector3.ZERO
	for p in v:
		center += p
	center /= maxf(v.size(), 1)
	for i in range(0, idx.size(), 3):
		var a := v[idx[i]]
		var b := v[idx[i + 1]]
		var c := v[idx[i + 2]]
		var n := (c - a).cross(b - a)
		if n.length_squared() < 1e-12:
			continue
		n = n.normalized()
		if n.dot((a + b + c) / 3.0 - center) < 0.0:
			n = -n
		out_v.append_array([a, b, c])
		out_n.append_array([n, n, n])
	var res := []
	res.resize(Mesh.ARRAY_MAX)
	res[Mesh.ARRAY_VERTEX] = out_v
	res[Mesh.ARRAY_NORMAL] = out_n
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res)
	_mesh_cache[key] = m
	return m


static func cyl(top: float, bottom: float, h: float, seg := 7) -> ArrayMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return flat("c%.3f_%.3f_%.3f_%d" % [top, bottom, h, seg], c)


static func box(sz: Vector3) -> ArrayMesh:
	var b := BoxMesh.new()
	b.size = sz
	return flat("b%s" % sz, b)


static func ball_mesh(r: float, seg := 8, rings := 5) -> ArrayMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = rings
	return flat("s%.3f_%d_%d" % [r, seg, rings], s)


func _mat(name: String, c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	_mats[name] = m
	return m


func _joint(name: String, parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	j[name] = n
	return n


const MODEL := preload("res://assets/models/player.glb")
const MAT_NAMES := ["skin", "jersey", "trim", "shorts", "socks", "pads", "shoes", "sole", "eyes", "hair"]

var _skel: Skeleton3D
var _bone := {}  # Gelenkname -> Knochenindex
var _rest_rot := {}  # Gelenkname -> Ruhe-Drehung des Knochens (Skelett-Raum)
var _parent := {}  # Gelenkname -> Elterngelenk ("" fuer die Huefte)


## Koerper bauen. colors: jersey, shorts, skin, hair, shoes, socks, trim (fehlende = Standard).
## hair_style ist fuer spaetere Frisur-Varianten reserviert.
func build(colors: Dictionary, with_pads := true, _hair_style := 0) -> void:
	for n in MAT_NAMES:
		_mat(n, Color.WHITE)
	set_color("jersey", colors.get("jersey", Color.WHITE))
	set_color("shorts", colors.get("shorts", Color(0.1, 0.1, 0.15)))
	set_color("skin", colors.get("skin", Color(0.93, 0.76, 0.62)))
	set_color("hair", colors.get("hair", Color(0.25, 0.17, 0.1)))
	set_color("shoes", colors.get("shoes", Color(0.95, 0.95, 0.95)))
	set_color("socks", colors.get("socks", Color(0.95, 0.95, 0.95)))
	set_color("trim", colors.get("trim", Color(1, 1, 1)))
	set_color("pads", Color(0.13, 0.13, 0.15))
	set_color("sole", Color(0.2, 0.2, 0.22))
	set_color("eyes", Color(0.08, 0.07, 0.07))
	(_mats["skin"] as StandardMaterial3D).roughness = 0.7
	if not with_pads:
		var pm: StandardMaterial3D = _mats["pads"]
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		pm.albedo_color.a = 0.0

	root_node = Node3D.new()
	add_child(root_node)
	var model: Node3D = MODEL.instantiate()
	root_node.add_child(model)
	_skel = model.find_child("Skeleton3D", true, false)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var mat_name := m.mesh.surface_get_material(i).resource_name
			if _mats.has(mat_name):
				m.set_surface_override_material(i, _mats[mat_name])
	# Gelenk-Knoten an den Knochenpositionen der Ruhehaltung (Arme haengen, alles gerade).
	var rest_pos := {}
	for name in JOINTS:
		var b := _skel.find_bone(name)
		_bone[name] = b
		var g := _skel.get_bone_global_rest(b)
		rest_pos[name] = g.origin
		_rest_rot[name] = g.basis.get_rotation_quaternion()
		var pb := _skel.get_bone_parent(b)
		_parent[name] = _skel.get_bone_name(pb) if pb >= 0 else ""
	# Sitzende Figuren (Bank) haben die Huefte tiefer: ganzes Modell verschieben.
	model.position.y = hips_height - rest_pos["hips"].y
	for name in JOINTS:
		var par: String = _parent[name]
		var parent_node: Node3D = root_node if par == "" else j[par]
		var off: Vector3 = rest_pos[name] - (Vector3.ZERO if par == "" else rest_pos[par])
		if par == "":
			off.y = hips_height
		_joint(name, parent_node, off)
	_sync()


## Knochen nach den Gelenkwinkeln ausrichten. Ein Gelenk mit Winkel 0 = Ruhehaltung;
## gedreht wird in den Achsen der Figur (x rechts, y oben, z hinten), nicht in den
## Knochenachsen aus Blender.
func _sync() -> void:
	if _skel == null:
		return
	for name in JOINTS:
		var e := (j[name] as Node3D).quaternion
		var par: String = _parent[name]
		var r: Quaternion = _rest_rot[name]
		var q := e * r if par == "" else (_rest_rot[par] as Quaternion).inverse() * e * r
		_skel.set_bone_pose_rotation(_bone[name], q)


## Bildschirm-Frame: die Knochen aus den weich interpolierten Gelenklagen setzen. Die Posen
## entstehen im Physiktakt (120 Hz, in der Zeitlupe weniger); ohne das wuerden Arme und Beine
## dann sichtbar ruckeln, waehrend der Koerper selbst schon fluessig gleitet.
func _process(_delta: float) -> void:
	if _skel == null or not is_physics_interpolated_and_enabled():
		return
	var inv := _skel.get_global_transform_interpolated().affine_inverse()
	var g := {}
	for name in JOINTS:
		var jb := (inv * (j[name] as Node3D).get_global_transform_interpolated()).basis.orthonormalized()
		var actual: Quaternion = jb.get_rotation_quaternion() * (_rest_rot[name] as Quaternion)
		g[name] = actual
		var par: String = _parent[name]
		_skel.set_bone_pose_rotation(_bone[name], actual if par == "" else (g[par] as Quaternion).inverse() * actual)


## Rueckennummer und kleine Nummer vorne.
func set_number(n: int, col: Color) -> void:
	if _num_back == null:
		_num_back = _num_label(0.165, 0.0, 0.0034)
		_num_front = _num_label(-0.17, PI, 0.0018)
		_num_front.position.y = 0.38
		_num_front.position.x = 0.08
	_num_back.text = str(n)
	_num_front.text = str(n)
	_num_back.modulate = col
	_num_front.modulate = col


func _num_label(z: float, rot_y: float, px: float) -> Label3D:
	var l := Label3D.new()
	l.font_size = 64
	l.outline_size = 0
	l.pixel_size = px
	l.double_sided = false
	l.position = Vector3(0, 0.25, z)
	l.rotation.y = rot_y
	l.shaded = true
	j["chest"].add_child(l)
	return l


func set_color(part: String, c: Color) -> void:
	if _mats.has(part):
		(_mats[part] as StandardMaterial3D).albedo_color = c


## Pose setzen: Dictionary Gelenk -> Vector3 (Euler in Radiant). Fehlende Gelenke = 0.
## k = 1 setzt sofort, kleiner blendet weich dorthin.
func pose(p: Dictionary, k := 1.0) -> void:
	for name in JOINTS:
		var target: Vector3 = p.get(name, Vector3.ZERO)
		var n: Node3D = j[name]
		n.rotation = n.rotation.lerp(target, k) if k < 1.0 else target
	_sync()


## Weich zur Pose federn (kritisch gedaempfte Feder je Gelenk): Bewegungen beschleunigen und
## bremsen natuerlich statt ruckartig. w = Steifigkeit (hoeher = schneller, ~18 ruhig, ~45 Schlag).
func pose_spring(p: Dictionary, delta: float, w: float) -> void:
	var steps := maxi(1, ceili(w * delta / 0.3))
	var dt := delta / steps
	for name in JOINTS:
		var target: Vector3 = p.get(name, Vector3.ZERO)
		var n: Node3D = j[name]
		var r := n.rotation
		var v: Vector3 = _vel.get(name, Vector3.ZERO)
		for i in steps:
			v += (target - r) * (w * w * dt) - v * (2.0 * w * dt)
			r += v * dt
		n.rotation = r
		_vel[name] = v
	_sync()


## Tiefster Punkt des Koerpers (Hoehe ueber dem Boden der Figur). Nur Fuesse oder alles
## (Knie, Haende, Kopf, Brust), etwa wenn der Spieler hechtet.
func lowest_point(all: bool) -> float:
	var base := global_position.y
	var low := INF
	for sd in ["l", "r"]:
		var an: Transform3D = j["an_" + sd].global_transform
		# Sohle des Schuhs: Ferse und Spitze (Knoechel 9,5 cm ueber dem Boden)
		low = minf(low, (an * Vector3(0, -0.097, 0.085)).y)
		low = minf(low, (an * Vector3(0, -0.097, -0.225)).y)
		if all:
			low = minf(low, (j["kn_" + sd].global_transform * Vector3(0, -0.02, -0.08)).y - 0.04)
			low = minf(low, (j["wr_" + sd].global_transform * Vector3(0, -0.19, 0)).y - 0.02)
	if all:
		low = minf(low, (j["head"].global_transform * Vector3(0, 0.115, 0)).y - 0.125)
		low = minf(low, (j["chest"].global_transform * Vector3(0, 0.26, 0)).y - 0.15)
	return low - base


func capture() -> Array:
	var out := []
	for name in JOINTS:
		out.append(j[name].rotation)
	out.append(root_node.position)
	out.append(root_node.rotation)
	return out


func apply(c: Array) -> void:
	for i in JOINTS.size():
		j[JOINTS[i]].rotation = c[i]
	root_node.position = c[JOINTS.size()]
	root_node.rotation = c[JOINTS.size() + 1]
	_sync()
