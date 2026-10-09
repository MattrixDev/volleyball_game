class_name HumanFigure
extends Node3D
## Low-Poly-Mensch mit Gelenken: Rumpf, Kopf mit Haaren, Arme mit Haenden, Beine mit Schuhen.
## Blickrichtung ist lokal -Z. Posen werden als Gelenkwinkel gesetzt (siehe pose()).
## Die Formen sind flach schattiert (jede Flaeche eine Farbe), das gibt den Low-Poly-Look.

const JOINTS := ["hips", "chest", "head", "sh_l", "el_l", "wr_l", "sh_r", "el_r", "wr_r", "hip_l", "kn_l", "an_l", "hip_r", "kn_r", "an_r"]

static var _mesh_cache := {}

var j := {}  # Gelenkname -> Node3D
var root_node: Node3D  # traegt den ganzen Koerper (Hoehe, Kippen beim Hechten)
var hips_height := 1.02
var _mats := {}
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


func _part(parent: Node3D, mesh: Mesh, mat: String, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mats[mat]
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _joint(name: String, parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	j[name] = n
	return n


## Koerper bauen. colors: jersey, shorts, skin, hair, shoes, socks, (optional) trim.
func build(colors: Dictionary, with_pads := true, hair_style := 0) -> void:
	_mat("jersey", colors.get("jersey", Color.WHITE))
	_mat("shorts", colors.get("shorts", Color(0.1, 0.1, 0.15)))
	_mat("skin", colors.get("skin", Color(0.93, 0.76, 0.62)))
	_mat("hair", colors.get("hair", Color(0.25, 0.17, 0.1)))
	_mat("shoes", colors.get("shoes", Color(0.95, 0.95, 0.95)))
	_mat("socks", colors.get("socks", Color(0.95, 0.95, 0.95)))
	_mat("pads", Color(0.12, 0.12, 0.14))
	_mat("trim", colors.get("trim", Color(1, 1, 1)))

	root_node = Node3D.new()
	add_child(root_node)
	var hips := _joint("hips", root_node, Vector3(0, hips_height, 0))
	_part(hips, box(Vector3(0.36, 0.2, 0.22)), "shorts", Vector3(0, -0.02, 0))
	var chest := _joint("chest", hips, Vector3(0, 0.06, 0))
	# Oberkoerper: oben breiter (Schultern), vorne flacher
	_part(chest, cyl(0.24, 0.18, 0.52, 6), "jersey", Vector3(0, 0.26, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.68))
	_part(chest, cyl(0.06, 0.07, 0.12, 6), "skin", Vector3(0, 0.56, 0))
	for sx in [-1.0, 1.0]:
		_part(chest, box(Vector3(0.05, 0.04, 0.16)), "trim", Vector3(sx * 0.2, 0.5, 0))
	var head := _joint("head", chest, Vector3(0, 0.62, 0))
	_part(head, ball_mesh(0.125, 7, 5), "skin", Vector3(0, 0.12, 0), Vector3.ZERO, Vector3(0.92, 1.08, 1.0))
	_part(head, box(Vector3(0.05, 0.06, 0.05)), "skin", Vector3(0, 0.1, -0.12))  # Nase
	match hair_style:
		0:
			_part(head, ball_mesh(0.13, 7, 4), "hair", Vector3(0, 0.17, 0.015), Vector3.ZERO, Vector3(0.96, 0.75, 1.02))
		1:
			_part(head, box(Vector3(0.245, 0.1, 0.265)), "hair", Vector3(0, 0.205, 0.012))
		2:
			_part(head, ball_mesh(0.135, 7, 4), "hair", Vector3(0, 0.15, 0.03), Vector3.ZERO, Vector3(1.0, 0.9, 1.05))
	for s in [["l", -1.0], ["r", 1.0]]:
		var side: String = s[0]
		var sx: float = s[1]
		var sh := _joint("sh_" + side, chest, Vector3(sx * 0.25, 0.47, 0))
		_part(sh, ball_mesh(0.075, 6, 4), "jersey", Vector3.ZERO)
		_part(sh, cyl(0.06, 0.05, 0.3, 6), "skin", Vector3(0, -0.16, 0))
		_part(sh, cyl(0.072, 0.066, 0.12, 6), "jersey", Vector3(0, -0.05, 0))  # Aermel
		var el := _joint("el_" + side, sh, Vector3(0, -0.31, 0))
		_part(el, cyl(0.048, 0.04, 0.27, 6), "skin", Vector3(0, -0.135, 0))
		var wr := _joint("wr_" + side, el, Vector3(0, -0.27, 0))
		# Hand: flacher Handteller, Finger als Block, Daumen nach innen/vorn
		_part(wr, box(Vector3(0.085, 0.1, 0.04)), "skin", Vector3(0, -0.05, 0))
		_part(wr, box(Vector3(0.08, 0.075, 0.032)), "skin", Vector3(0, -0.135, 0.004), Vector3(0.15, 0, 0))
		_part(wr, box(Vector3(0.03, 0.07, 0.03)), "skin", Vector3(-sx * 0.05, -0.06, -0.025), Vector3(0.3, 0, -sx * 0.5))
		var hp := _joint("hip_" + side, hips, Vector3(sx * 0.1, -0.06, 0))
		_part(hp, cyl(0.1, 0.09, 0.2, 6), "shorts", Vector3(0, -0.08, 0))
		_part(hp, cyl(0.085, 0.065, 0.44, 6), "skin", Vector3(0, -0.24, 0))
		var kn := _joint("kn_" + side, hp, Vector3(0, -0.46, 0))
		if with_pads:
			_part(kn, box(Vector3(0.12, 0.12, 0.08)), "pads", Vector3(0, -0.02, -0.04))
		_part(kn, cyl(0.065, 0.045, 0.3, 6), "skin", Vector3(0, -0.15, 0))
		_part(kn, cyl(0.05, 0.046, 0.16, 6), "socks", Vector3(0, -0.36, 0))
		var an := _joint("an_" + side, kn, Vector3(0, -0.44, 0))
		_part(an, box(Vector3(0.1, 0.08, 0.26)), "shoes", Vector3(0, -0.04, -0.05))
		_part(an, box(Vector3(0.105, 0.025, 0.27)), "trim", Vector3(0, -0.075, -0.05))


## Rueckennummer und kleine Nummer vorne.
func set_number(n: int, col: Color) -> void:
	if _num_back == null:
		_num_back = _num_label(0.16, 0.0, 0.0034)
		_num_front = _num_label(-0.16, PI, 0.0018)
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
	l.position = Vector3(0, 0.3, z)
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
