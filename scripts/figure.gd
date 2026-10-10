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


# Weich gerundete Formen (glatte Normalen) fuer die Spielerfiguren.
static func _cached(key: String, m: Mesh) -> Mesh:
	if not _mesh_cache.has(key):
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func scyl(top: float, bottom: float, h: float) -> Mesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 16
	c.rings = 2
	return _cached("sc%.3f_%.3f_%.3f" % [top, bottom, h], c)


static func caps(r: float, h: float) -> Mesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0)
	c.radial_segments = 16
	c.rings = 6
	return _cached("cp%.3f_%.3f" % [r, h], c)


static func sph(r: float) -> Mesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 18
	s.rings = 10
	return _cached("sp%.3f" % r, s)


static func ring(inner: float, outer: float) -> Mesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 16
	t.ring_segments = 6
	return _cached("tr%.3f_%.3f" % [inner, outer], t)


static func rbox(sz: Vector3) -> Mesh:
	var b := BoxMesh.new()
	b.size = sz
	return _cached("rb%s" % sz, b)


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
	# Kleine Details (Finger, Gesicht, Saeume) werfen keinen Schatten, das spart Rechenzeit.
	if mat in ["eye", "pupil", "mouth", "trim", "sole"] or (mesh.get_aabb().size.length() < 0.09):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _joint(name: String, parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	j[name] = n
	return n


## Koerper bauen. colors: jersey, shorts, skin, hair, shoes, socks, (optional) trim.
## Die Gelenkpunkte sind fest (siehe pose()), nur die Formen darum herum sind Detail.
func build(colors: Dictionary, with_pads := true, hair_style := 0) -> void:
	_mat("jersey", colors.get("jersey", Color.WHITE))
	_mat("shorts", colors.get("shorts", Color(0.1, 0.1, 0.15)))
	_mat("skin", colors.get("skin", Color(0.93, 0.76, 0.62)))
	_mat("hair", colors.get("hair", Color(0.25, 0.17, 0.1)))
	_mat("shoes", colors.get("shoes", Color(0.95, 0.95, 0.95)))
	_mat("socks", colors.get("socks", Color(0.95, 0.95, 0.95)))
	_mat("pads", Color(0.12, 0.12, 0.14))
	_mat("trim", colors.get("trim", Color(1, 1, 1)))
	_mat("eye", Color(0.97, 0.97, 0.97))
	_mat("pupil", Color(0.08, 0.07, 0.07))
	_mat("mouth", (colors.get("skin", Color(0.93, 0.76, 0.62)) as Color).darkened(0.35))
	_mat("sole", Color(0.15, 0.15, 0.17))
	(_mats["skin"] as StandardMaterial3D).roughness = 0.65
	(_mats["jersey"] as StandardMaterial3D).roughness = 0.75

	root_node = Node3D.new()
	add_child(root_node)
	var hips := _joint("hips", root_node, Vector3(0, hips_height, 0))
	# Hose: gerundeter Beckenteil
	_part(hips, caps(0.15, 0.36), "shorts", Vector3(0, -0.03, 0), Vector3(0, 0, PI / 2), Vector3(1.0, 1.0, 0.8))
	var chest := _joint("chest", hips, Vector3(0, 0.06, 0))
	# Oberkoerper: Taille schmal, Brust und Schultern breit und rund
	_part(chest, scyl(0.215, 0.165, 0.3), "jersey", Vector3(0, 0.15, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.66))
	_part(chest, caps(0.19, 0.42), "jersey", Vector3(0, 0.35, 0), Vector3.ZERO, Vector3(1.2, 1.0, 0.7))
	_part(chest, scyl(0.055, 0.065, 0.14), "skin", Vector3(0, 0.57, 0))  # Hals
	_part(chest, ring(0.06, 0.085), "trim", Vector3(0, 0.525, -0.005), Vector3.ZERO, Vector3(1.05, 1.0, 0.9))  # Kragen
	for sx in [-1.0, 1.0]:
		_part(chest, rbox(Vector3(0.012, 0.34, 0.035)), "trim", Vector3(sx * 0.222, 0.3, 0), Vector3(0, 0, sx * 0.1))  # Seitennaht
	var head := _joint("head", chest, Vector3(0, 0.62, 0))
	_head(head, hair_style)
	for s in [["l", -1.0], ["r", 1.0]]:
		var side: String = s[0]
		var sx: float = s[1]
		var sh := _joint("sh_" + side, chest, Vector3(sx * 0.25, 0.47, 0))
		_part(sh, sph(0.066), "jersey", Vector3.ZERO)
		_part(sh, scyl(0.066, 0.064, 0.13), "jersey", Vector3(0, -0.06, 0))  # Aermel
		_part(sh, ring(0.058, 0.068), "trim", Vector3(0, -0.125, 0))
		_part(sh, caps(0.056, 0.34), "skin", Vector3(0, -0.16, 0))  # Oberarm
		var el := _joint("el_" + side, sh, Vector3(0, -0.31, 0))
		_part(el, caps(0.047, 0.31), "skin", Vector3(0, -0.13, 0))  # Unterarm
		var wr := _joint("wr_" + side, el, Vector3(0, -0.27, 0))
		_hand(wr, sx)
		var hp := _joint("hip_" + side, hips, Vector3(sx * 0.1, -0.06, 0))
		_part(hp, scyl(0.105, 0.095, 0.2), "shorts", Vector3(0, -0.08, 0))  # Hosenbein
		_part(hp, ring(0.088, 0.1), "trim", Vector3(0, -0.175, 0))
		_part(hp, caps(0.085, 0.48), "skin", Vector3(0, -0.24, 0))  # Oberschenkel
		var kn := _joint("kn_" + side, hp, Vector3(0, -0.46, 0))
		if with_pads:
			_part(kn, caps(0.075, 0.17), "pads", Vector3(0, -0.02, -0.025), Vector3.ZERO, Vector3(1.05, 1.0, 1.0))
		_part(kn, caps(0.062, 0.36), "skin", Vector3(0, -0.16, 0), Vector3.ZERO, Vector3(1.0, 1.0, 1.08))  # Wade
		_part(kn, scyl(0.05, 0.047, 0.17), "socks", Vector3(0, -0.355, 0))
		var an := _joint("an_" + side, kn, Vector3(0, -0.44, 0))
		# Schuh: runde Form mit dunkler Sohle und Streifen
		_part(an, caps(0.055, 0.27), "shoes", Vector3(0, -0.035, -0.05), Vector3(PI / 2, 0, 0), Vector3(1.0, 1.0, 0.75))
		_part(an, rbox(Vector3(0.098, 0.02, 0.25)), "sole", Vector3(0, -0.074, -0.05))
		_part(an, rbox(Vector3(0.112, 0.016, 0.09)), "trim", Vector3(0, -0.04, -0.03), Vector3(0.35, 0, 0))


func _head(head: Node3D, hair_style: int) -> void:
	_part(head, sph(0.125), "skin", Vector3(0, 0.12, 0), Vector3.ZERO, Vector3(0.9, 1.08, 1.0))
	_part(head, sph(0.024), "skin", Vector3(0, 0.1, -0.125), Vector3.ZERO, Vector3(0.8, 1.1, 1.0))  # Nase
	for sx in [-1.0, 1.0]:
		_part(head, sph(0.03), "skin", Vector3(sx * 0.112, 0.11, 0.0), Vector3.ZERO, Vector3(0.5, 1.0, 0.8))  # Ohr
		_part(head, sph(0.019), "eye", Vector3(sx * 0.042, 0.135, -0.106))
		_part(head, sph(0.011), "pupil", Vector3(sx * 0.042, 0.135, -0.122))
		_part(head, rbox(Vector3(0.045, 0.012, 0.015)), "hair", Vector3(sx * 0.044, 0.165, -0.112), Vector3(0, 0, -sx * 0.12))  # Braue
	_part(head, rbox(Vector3(0.036, 0.008, 0.01)), "mouth", Vector3(0, 0.06, -0.112))
	match hair_style:
		0:  # mittellang, Seitenscheitel
			_part(head, sph(0.135), "hair", Vector3(0, 0.165, 0.012), Vector3(-0.1, 0, 0), Vector3(0.96, 0.78, 1.03))
		1:  # kurz geschoren
			_part(head, sph(0.131), "hair", Vector3(0, 0.15, 0.01), Vector3.ZERO, Vector3(0.93, 0.85, 0.99))
		2:  # voll und lockig
			_part(head, sph(0.14), "hair", Vector3(0, 0.17, 0.02), Vector3.ZERO, Vector3(1.0, 0.85, 1.05))
			for k in 8:
				var a := k * TAU / 8.0
				_part(head, sph(0.045), "hair", Vector3(sin(a) * 0.09, 0.225, cos(a) * 0.09 + 0.02))


func _hand(wr: Node3D, sx: float) -> void:
	_part(wr, sph(0.045), "skin", Vector3(0, -0.05, 0), Vector3.ZERO, Vector3(0.95, 1.15, 0.5))  # Handteller
	for f in 4:
		var x := (f - 1.5) * 0.019
		var ln := 0.075 if f in [1, 2] else 0.062
		_part(wr, caps(0.0105, ln), "skin", Vector3(x, -0.1 - ln * 0.4, 0.004), Vector3(0.12, 0, 0))
	_part(wr, caps(0.012, 0.06), "skin", Vector3(-sx * 0.045, -0.06, -0.018), Vector3(0.35, 0, -sx * 0.55))  # Daumen


## Rueckennummer und kleine Nummer vorne.
func set_number(n: int, col: Color) -> void:
	if _num_back == null:
		_num_back = _num_label(0.152, 0.0, 0.0034)
		_num_front = _num_label(-0.15, PI, 0.0018)
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


## Tiefster Punkt des Koerpers (Hoehe ueber dem Boden der Figur). Nur Fuesse oder alles
## (Knie, Haende, Kopf, Brust), etwa wenn der Spieler hechtet.
func lowest_point(all: bool) -> float:
	var base := global_position.y
	var low := INF
	for sd in ["l", "r"]:
		var an: Transform3D = j["an_" + sd].global_transform
		low = minf(low, (an * Vector3(0, -0.088, 0.08)).y)
		low = minf(low, (an * Vector3(0, -0.088, -0.18)).y)
		if all:
			low = minf(low, (j["kn_" + sd].global_transform * Vector3(0, -0.02, -0.08)).y - 0.04)
			low = minf(low, (j["wr_" + sd].global_transform * Vector3(0, -0.17, 0)).y - 0.03)
	if all:
		low = minf(low, (j["head"].global_transform * Vector3(0, 0.12, 0)).y - 0.13)
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
