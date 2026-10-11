class_name HumanFigure
extends Node3D
## Spielerfigur: Mattis' Meshy-Modell (assets/models/player.glb, Schiedsrichter referee.glb,
## erzeugt von tools/blender/build_figure_rigged.py) mit Skelett. Die Posen werden wie bisher als Gelenkwinkel
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


func _hide_mat(name: String) -> void:
	var m: StandardMaterial3D = _mats[name]
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.albedo_color.a = 0.0


func _joint(name: String, parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	j[name] = n
	return n


const MODEL := preload("res://assets/models/player.glb")
const REF_MODEL := preload("res://assets/models/referee.glb")
const MAT_NAMES := ["skin", "jersey", "panel", "collar", "logo", "shorts", "socks", "pads", "shoes", "accent", "sole", "trousers", "hair"]
const DEFAULTS := {
	"skin": Color(0.86, 0.66, 0.52), "hair": Color(0.3, 0.2, 0.13), "jersey": Color(0.15, 0.19, 0.32),
	"panel": Color(0.9, 0.9, 0.88), "collar": Color(0.9, 0.9, 0.88), "logo": Color(0.9, 0.9, 0.88),
	"shorts": Color(0.15, 0.19, 0.32), "socks": Color(0.9, 0.9, 0.88), "pads": Color(0.1, 0.1, 0.11),
	"shoes": Color(0.9, 0.9, 0.88), "accent": Color(0.15, 0.19, 0.32), "sole": Color(0.85, 0.85, 0.84),
	"trousers": Color(0.12, 0.12, 0.14),
}
const HAIR_STYLES := 4
static var _markers := {}
static var _clips := {}  # Animationen aus Meshy (player_clips.json): Name -> {fps, frames}
static var _clip_off := {}  # Name -> Phasenversatz, damit das linke Bein bei u = 0,25 vorn ist

var _skel: Skeleton3D
var _bone := {}  # Gelenkname -> Knochenindex
var _rest_rot := {}  # Gelenkname -> Ruhe-Drehung des Knochens (Skelett-Raum)
var _parent := {}  # Gelenkname -> Elterngelenk ("" fuer die Huefte)
var _rest_pos := {}  # Gelenkname -> Knochenposition in Ruhehaltung (Modell-Raum)
var _model_y := 0.0
var _num_shorts: Label3D
var _num_style := "player"


## Koerper bauen. colors: Schluessel wie MAT_NAMES (fehlende = Standard), meist aus
## TeamStyle.colors() plus skin/hair. hair_style 0..3 waehlt die Frisur, height skaliert
## die Figur leicht. official = lange Hose statt Shorts, Socken und Knieschoner.
func build(colors: Dictionary, with_pads := true, hair_style := 0, official := false, height := 1.0) -> void:
	for n in MAT_NAMES:
		var m := _mat(n, colors.get(n, DEFAULTS[n]))
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.92
	(_mats["skin"] as StandardMaterial3D).roughness = 0.8
	if not with_pads or official:
		_hide_mat("pads")
	if official:
		_hide_mat("shorts")
		_hide_mat("socks")
		_hide_mat("logo")
	else:
		_hide_mat("trousers")

	root_node = Node3D.new()
	add_child(root_node)
	root_node.scale = Vector3.ONE * height
	var model: Node3D = (REF_MODEL if official else MODEL).instantiate()
	root_node.add_child(model)
	_skel = model.find_child("Skeleton3D", true, false)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.name.begins_with("hair_"):
			m.visible = m.name == "hair_%d" % (posmod(hair_style, HAIR_STYLES))
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
		_rest_pos[name] = g.origin
		_rest_rot[name] = g.basis.get_rotation_quaternion()
		var pb := _skel.get_bone_parent(b)
		_parent[name] = _skel.get_bone_name(pb) if pb >= 0 else ""
	# Sitzende Figuren (Bank) haben die Huefte tiefer: ganzes Modell verschieben.
	model.position.y = hips_height - rest_pos["hips"].y
	_model_y = model.position.y
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


## Nummern: gross auf dem Ruecken, kleiner vorn auf der Brust und auf dem linken Hosenbein
## (Positionen aus player_markers.json, die das Blender-Skript mitschreibt).
func set_number(n: int, col: Color, shorts_col: Variant = null) -> void:
	if _num_back == null:
		_num_back = _num_label("num_back", 0.0034)
		_num_front = _num_label("num_front", 0.0021)
		_num_shorts = _num_label("num_shorts", 0.0012)
	for l in [_num_back, _num_front, _num_shorts]:
		if l:
			l.text = str(n)
			l.modulate = col
	if _num_shorts and shorts_col != null:
		_num_shorts.modulate = shorts_col


static func markers() -> Dictionary:
	if _markers.is_empty():
		var f := FileAccess.open("res://assets/models/player_markers.json", FileAccess.READ)
		if f:
			_markers = JSON.parse_string(f.get_as_text())
	return _markers


## Pose aus einer Meshy-Animation (Gehen, Laufen), u = 0..1 durch einen Doppelschritt.
## Bei u = 0,25 ist das linke Bein vorn (wie sin(Phase) in VPlayer._p_run). Leer, wenn es die
## Animation nicht gibt.
## u: Anteil 0..1 der Animation. loop = true: Schleife (Laufen), Phase so verschoben, dass das
## linke Bein bei u = 0,25 vorn ist. loop = false: einmal von vorn bis hinten (Schlag, Jubel).
static func clip_pose(clip: String, u: float, loop := true) -> Dictionary:
	if _clips.is_empty():
		var f := FileAccess.open("res://assets/models/player_clips.json", FileAccess.READ)
		_clips = JSON.parse_string(f.get_as_text()) if f else {"_": {}}
		for name in _clips:
			var fr: Array = _clips[name].get("frames", [])
			if fr.size() < 2:
				continue
			var best := 0
			var best_x := -INF
			for i in fr.size() - 1:
				var x := _clip_euler(fr[i], "hip_l").x
				if x > best_x:
					best_x = x
					best = i
			_clip_off[name] = float(best) / float(fr.size() - 1) - 0.25
	if not _clips.has(clip):
		return {}
	var frames: Array = _clips[clip].frames
	var n := frames.size() - 1  # Schleife: letztes Bild = erstes
	var i0: int
	var i1: int
	var w: float
	if loop:
		var t := fposmod(u + _clip_off.get(clip, 0.0), 1.0) * n
		i0 = int(t) % n
		i1 = (i0 + 1) % n
		w = t - floorf(t)
	else:
		var t := clampf(u, 0.0, 1.0) * n
		i0 = mini(int(t), n)
		i1 = mini(i0 + 1, n)
		w = t - floorf(t)
	var out := {}
	for name in JOINTS:
		var q0 := _clip_quat(frames[i0], name)
		var q1 := _clip_quat(frames[i1], name)
		out[name] = Basis(q0.slerp(q1, w)).get_euler()
	return out


static func _clip_quat(fr: Dictionary, name: String) -> Quaternion:
	var a: Array = fr[name]
	return Quaternion(a[0], a[1], a[2], a[3]).normalized()


static func _clip_euler(fr: Dictionary, name: String) -> Vector3:
	return Basis(_clip_quat(fr, name)).get_euler()


func _num_label(key: String, px: float) -> Label3D:
	var mk: Dictionary = markers().get(key, {})
	if mk.is_empty() or not j.has(mk.bone):
		return null
	var pos := Vector3(mk.pos[0], mk.pos[1], mk.pos[2])
	var nrm := Vector3(mk.normal[0], mk.normal[1], mk.normal[2]).normalized()
	var l := Label3D.new()
	l.font_size = 64
	l.outline_size = 0
	l.pixel_size = px
	l.double_sided = false
	l.shaded = true
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["DejaVu Sans", "Arial", "Sans-Serif"])
	font.font_weight = 800
	l.font = font
	# Label3D zeigt nach +Z: auf die Flaechennormale drehen, knapp ueber dem Stoff
	l.position = pos + nrm * 0.012 - _rest_pos[mk.bone]
	l.basis = Basis.looking_at(-nrm, Vector3.UP)
	(j[mk.bone] as Node3D).add_child(l)
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


## Arm so stellen, dass das Handgelenk an der Weltposition target sitzt (Ballkontakt).
## Loest Schulter vor/seitlich und Ellbogen numerisch (gedaempfte Gauss-Newton-Schritte),
## ausgehend von der aktuellen Haltung. w blendet zwischen Pose (0) und Ziel (1). Rueckgabe:
## verbleibender Abstand in m (zum Pruefen, ob die Figur den Ball erreicht).
func ik_arm(sd: String, target: Vector3, w: float, iters := 4, damp := 0.02) -> float:
	var sh: Node3D = j["sh_" + sd]
	var el: Node3D = j["el_" + sd]
	var wr: Node3D = j["wr_" + sd]
	var s := -1.0 if sd == "l" else 1.0
	var y0 := sh.rotation.y
	# Ellbogen-Drehung um die anderen Achsen (Meshy-Animationen) bleibt erhalten.
	var ey := el.rotation.y
	var ez := el.rotation.z
	var v := Vector3(sh.rotation.x, sh.rotation.z * s, el.rotation.x)  # vor, seitlich, Ellbogen
	var v_start := v
	var lo := Vector3(minf(-0.6, v.x), minf(-0.5, v.y), minf(0.0, v.z))
	var hi := Vector3(maxf(3.1, v.x), maxf(2.0, v.y), maxf(2.6, v.z))
	var pos := Callable(self, "_ik_wrist").bind(sh, el, wr, y0, s, ey, ez)
	var err := 0.0
	for it in iters:
		var p0: Vector3 = pos.call(v)
		var e := target - p0
		err = e.length()
		if err < 0.004:
			break
		var d := 0.02
		var c0: Vector3 = ((pos.call(v + Vector3(d, 0, 0)) as Vector3) - p0) / d
		var c1: Vector3 = ((pos.call(v + Vector3(0, d, 0)) as Vector3) - p0) / d
		var c2: Vector3 = ((pos.call(v + Vector3(0, 0, d)) as Vector3) - p0) / d
		var a := Basis(
			Vector3(c0.dot(c0) + damp, c0.dot(c1), c0.dot(c2)),
			Vector3(c1.dot(c0), c1.dot(c1) + damp, c1.dot(c2)),
			Vector3(c2.dot(c0), c2.dot(c1), c2.dot(c2) + damp))
		var step := a.inverse() * Vector3(c0.dot(e), c1.dot(e), c2.dot(e))
		v += step.limit_length(0.6)
		v = v.clamp(lo, hi)
	var fin: Vector3 = v_start.lerp(v, clampf(w, 0.0, 1.0))
	sh.rotation = Vector3(fin.x, y0, fin.y * s)
	el.rotation = Vector3(fin.z, ey, ez)
	return ((pos.call(fin) as Vector3) - target).length()


func _ik_wrist(v: Vector3, sh: Node3D, el: Node3D, wr: Node3D, y0: float, s: float, ey := 0.0, ez := 0.0) -> Vector3:
	sh.rotation = Vector3(v.x, y0, v.y * s)
	el.rotation = Vector3(v.z, ey, ez)
	return wr.global_position


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
