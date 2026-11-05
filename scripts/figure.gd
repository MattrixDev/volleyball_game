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
var _fa_bone := {}  # Seite -> Knochenindex des Unterarm-Drehknochens (fehlt beim Schiedsrichter-Modell)
var _fa_rest := {}  # Seite -> Ruhe-Drehung des Unterarm-Drehknochens (Skelett-Raum)
var _fa_axis := {}  # Seite -> Unterarmachse Ellbogen -> Handgelenk in Ruhehaltung (Raum des Ellbogens)
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
		if _parent[name].begins_with("fa_"):
			_parent[name] = "el_" + name.right(1)  # Hand haengt am Unterarm-Drehknochen
	for sd in ["l", "r"]:
		var fb := _skel.find_bone("fa_" + sd)
		if fb >= 0:
			_fa_bone[sd] = fb
			_fa_rest[sd] = _skel.get_bone_global_rest(fb).basis.get_rotation_quaternion()
		_fa_axis[sd] = (rest_pos["wr_" + sd] - rest_pos["el_" + sd]).normalized()
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
	_build_fingers()
	_sync()


## Knochen nach den Gelenkwinkeln ausrichten. Ein Gelenk mit Winkel 0 = Ruhehaltung;
## gedreht wird in den Achsen der Figur (x rechts, y oben, z hinten), nicht in den
## Knochenachsen aus Blender.
func _sync() -> void:
	if _skel == null:
		return
	var g := {}
	for name in JOINTS:
		var par: String = _parent[name]
		var e := (j[name] as Node3D).quaternion
		g[name] = e if par == "" else (g[par] as Quaternion) * e
	_pose_bones(g)


## Knochen aus den Weltdrehungen der Gelenke (Achsen der Figur) setzen. Die Drehung der Hand um
## die Unterarmachse (Ellbogen-Drehung plus Hand-Drehung) uebernimmt der Unterarm-Drehknochen:
## der Unterarm verdrillt sich gleichmaessig vom Ellbogen zum Handgelenk wie bei Elle und Speiche,
## statt dass sich die Haut am Handgelenk oder Ellbogen verdreht. Die Hand selbst steht genau gleich.
func _pose_bones(g: Dictionary) -> void:
	var actual := {}
	for name in JOINTS:
		actual[name] = (g[name] as Quaternion) * (_rest_rot[name] as Quaternion)
	for sd in _fa_bone:
		var d: Vector3 = _fa_axis[sd]
		var ge: Quaternion = g["el_" + sd]
		var gp: Quaternion = g["sh_" + sd]
		var tw_el := twist_angle(gp.inverse() * ge, d)
		var tw_h := twist_angle(ge.inverse() * (g["wr_" + sd] as Quaternion), d)
		actual["el_" + sd] = ge * Quaternion(d, -tw_el) * (_rest_rot["el_" + sd] as Quaternion)
		actual["fa_" + sd] = ge * Quaternion(d, tw_h) * (_fa_rest[sd] as Quaternion)
	for name in JOINTS:
		var par: String = _parent[name]
		var a: Quaternion = actual[name]
		if par == "":
			_skel.set_bone_pose_rotation(_bone[name], a)
			continue
		if name.begins_with("wr_") and actual.has("fa_" + name.right(1)):
			par = "fa_" + name.right(1)
		_skel.set_bone_pose_rotation(_bone[name], (actual[par] as Quaternion).inverse() * a)
	for sd in _fa_bone:
		_skel.set_bone_pose_rotation(_fa_bone[sd], (actual["el_" + sd] as Quaternion).inverse() * (actual["fa_" + sd] as Quaternion))


## Drehwinkel von q um die Achse d (Twist der Swing-Twist-Zerlegung, -PI..PI).
static func twist_angle(q: Quaternion, d: Vector3) -> float:
	return wrapf(2.0 * atan2(Vector3(q.x, q.y, q.z).dot(d), q.w), -PI, PI)


## ------------------------------------------------------------------ Finger
## Das Modell hat je Hand Daumen und vier Finger mit zwei Gliedern (add_finger_bones.py). Die
## Finger sind gedaempfte Federn: hand[sd] gibt die Zielform vor (curl = Beugen, spread = Spreizen,
## thumb = Daumen abspreizen, grip = zugreifen), und der Ball ist ein fester Koerper: ein Finger, der
## in ihn hineinbeugt, wird an seiner Oberflaeche aufgehalten (oder zurueckgedrueckt). So legen sich
## die Finger von selbst um den Ball und geben beim Kontakt nach.
## In Ruhe (Arm haengt) zeigt die Handflaeche zum Koerper und der Daumen nach vorn.
const FINGERS := ["th", "ix", "md", "rg", "pk"]
const FINGER_REST := {"curl": 0.22, "spread": 0.04, "thumb": 0.15, "grip": 0.0}
const FINGER_SKIN := 0.009  # halbe Fingerdicke
var has_fingers := false
var hand := {"l": FINGER_REST.duplicate(), "r": FINGER_REST.duplicate()}
var _fg := {}  # "ix1_r" -> Daten des Fingerknochens (siehe _build_fingers)
var _fa := {}  # "ix1_r" -> [Beugewinkel, Geschwindigkeit]; "ix_r" -> Spreizwinkel


func _build_fingers() -> void:
	if _skel == null or _skel.find_bone("ix1_r") < 0:
		return
	has_fingers = true
	for sd in ["l", "r"]:
		var n := Vector3(-1.0 if sd == "r" else 1.0, 0.0, 0.0)  # Handflaeche in Ruhe (Skelett-Raum, zum Koerper)
		var md0 := _skel.get_bone_global_rest(_skel.find_bone("md1_" + sd)).origin
		var ix0 := _skel.get_bone_global_rest(_skel.find_bone("ix1_" + sd)).origin
		for fn in FINGERS:
			var b1 := _skel.find_bone(fn + "1_" + sd)
			var b2 := _skel.find_bone(fn + "2_" + sd)
			var g1 := _skel.get_bone_global_rest(b1)
			var g2 := _skel.get_bone_global_rest(b2)
			var d := (g2.origin - g1.origin).normalized()
			var len2 := g1.origin.distance_to(g2.origin) * (1.05 if fn == "th" else 1.0)
			var curl := d.cross(n).normalized()
			# Spreizen: vom Mittelfinger weg (Daumen: vom Zeigefinger weg)
			var o := g1.origin - (ix0 if fn == "th" else md0)
			if fn == "th":
				o = o + (g1.origin - md0) * 0.5
			o -= d * o.dot(d)
			var spread := d.cross(o.normalized()).normalized() if o.length() > 0.002 else Vector3.ZERO
			var i1 := g1.basis.inverse()
			var i2 := g2.basis.inverse()
			_fg[fn + "1_" + sd] = {"b": b1, "rest": _skel.get_bone_rest(b1).basis.get_rotation_quaternion(),
				"curl": (i1 * curl).normalized(), "spread": (i1 * spread).normalized() if spread != Vector3.ZERO else Vector3.ZERO}
			_fg[fn + "2_" + sd] = {"b": b2, "rest": _skel.get_bone_rest(b2).basis.get_rotation_quaternion(),
				"curl": (i2 * curl).normalized(), "dir": (i2 * d).normalized(), "len": len2}
			_fa[fn + "1_" + sd] = [FINGER_REST.curl, 0.0]
			_fa[fn + "2_" + sd] = [FINGER_REST.curl * 1.2, 0.0]
			_fa[fn + "_" + sd] = 0.0
	_apply_fingers()


## Zielwinkel eines Fingerglieds aus der Handform.
func _finger_target(sd: String, fn: String, seg: int) -> float:
	var h: Dictionary = hand[sd]
	var c: float = h.get("curl", 0.2)
	var g: float = h.get("grip", 0.0)
	if fn == "th":
		# Daumen: Grundglied beugt wenig (er spreizt vor allem ab), Endglied etwas mehr
		return (c * 0.5 + g * 0.6) if seg == 1 else (c * 0.8 + g * 0.8)
	var k := 1.0 if seg == 1 else 1.25
	if fn == "pk":
		k *= 1.1
	return (c + g * 1.1) * k


func _finger_spread(sd: String, fn: String) -> float:
	var h: Dictionary = hand[sd]
	if fn == "th":
		return h.get("thumb", 0.15)
	var w: float = {"ix": 1.0, "md": 0.0, "rg": 0.7, "pk": 1.3}[fn]
	return (h.get("spread", 0.04) as float) * w


## Finger einen Physiktakt weiterrechnen. ball = Ballmitte (Welt) oder INF, ball_r = Radius.
func fingers_step(delta: float, ball: Vector3, ball_r: float) -> void:
	if not has_fingers or delta <= 0.0:
		return
	var kf := 34.0  # Eigenfrequenz der Finger (1/s): schnell, aber sichtbar weich
	for sd in ["l", "r"]:
		for fn in FINGERS:
			_fa[fn + "_" + sd] = lerpf(_fa[fn + "_" + sd], _finger_spread(sd, fn), 1.0 - exp(-delta * 18.0))
			for seg in [1, 2]:
				var key: String = fn + str(seg) + "_" + sd
				var st: Array = _fa[key]
				var tgt := _finger_target(sd, fn, seg)
				var v: float = st[1] + ((tgt - st[0]) * kf * kf - st[1] * 2.0 * 0.8 * kf) * delta
				st[0] = clampf(st[0] + v * delta, -0.45, 1.65)
				st[1] = v
	_apply_fingers()
	if ball == Vector3.INF:
		return
	# Ball als fester Koerper: Fingerglieder, die in ihn hineinragen, werden zur Oberflaeche
	# zurueckgedreht (zwei Durchgaenge, Endglied zuerst).
	var to_world := _skel.global_transform
	for sd in ["l", "r"]:
		var wr_w: Vector3 = j["wr_" + sd].global_position
		if wr_w.distance_to(ball) > ball_r + 0.25:
			continue
		for _it in 2:
			var moved := false
			for fn in FINGERS:
				for seg in [2, 1]:
					if _push_out(sd, fn, seg, to_world, ball, ball_r):
						moved = true
			if not moved:
				break
			_apply_fingers()


## Prueft Spitze (seg 2) bzw. Mittelgelenk (seg 1) gegen den Ball und dreht das Glied heraus.
func _push_out(sd: String, fn: String, seg: int, to_world: Transform3D, ball: Vector3, ball_r: float) -> bool:
	var b2: Dictionary = _fg[fn + "2_" + sd]
	var joint_key: String = fn + str(seg) + "_" + sd
	var jb: int = _fg[joint_key].b
	var jt := to_world * _skel.get_bone_global_pose(jb)
	var p: Vector3
	if seg == 2:
		p = to_world * (_skel.get_bone_global_pose(b2.b) * ((b2.dir as Vector3) * float(b2.len)))
	else:
		p = to_world * _skel.get_bone_global_pose(b2.b).origin
	var dist := p.distance_to(ball)
	var pen := ball_r + FINGER_SKIN - dist
	if pen <= 0.0:
		return false
	var nb := (p - ball) / maxf(dist, 1e-5)
	var ax_w := (jt.basis * (_fg[joint_key].curl as Vector3)).normalized()
	var g := ax_w.cross(p - jt.origin).dot(nb)  # wie weit die Spitze je rad Beugen nach aussen kommt
	if absf(g) < 0.004:
		return false
	var st: Array = _fa[joint_key]
	var da := clampf(pen / g, -0.35, 0.35)
	st[0] = clampf(st[0] + da, -0.45, 1.65)
	if signf(st[1]) != signf(da):
		st[1] = 0.0  # Stoss: die Bewegung in den Ball hinein endet
	return true


func _apply_fingers() -> void:
	if not has_fingers:
		return
	for sd in ["l", "r"]:
		for fn in FINGERS:
			var a: Dictionary = _fg[fn + "1_" + sd]
			var q: Quaternion = a.rest
			if a.spread != Vector3.ZERO:
				q = q * Quaternion(a.spread, _fa[fn + "_" + sd])
			_skel.set_bone_pose_rotation(a.b, q * Quaternion(a.curl, (_fa[fn + "1_" + sd] as Array)[0]))
			var c: Dictionary = _fg[fn + "2_" + sd]
			_skel.set_bone_pose_rotation(c.b, (c.rest as Quaternion) * Quaternion(c.curl, (_fa[fn + "2_" + sd] as Array)[0]))


## Fingerwinkel fuer das Replay (eine flache Liste).
func finger_state() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if has_fingers:
		for sd in ["l", "r"]:
			for fn in FINGERS:
				out.append(_fa[fn + "_" + sd])
				out.append((_fa[fn + "1_" + sd] as Array)[0])
				out.append((_fa[fn + "2_" + sd] as Array)[0])
	return out


func set_finger_state(a: PackedFloat32Array) -> void:
	if not has_fingers or a.size() < 30:
		return
	var i := 0
	for sd in ["l", "r"]:
		for fn in FINGERS:
			_fa[fn + "_" + sd] = a[i]
			_fa[fn + "1_" + sd] = [a[i + 1], 0.0]
			_fa[fn + "2_" + sd] = [a[i + 2], 0.0]
			i += 3
	_apply_fingers()


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
		g[name] = jb.get_rotation_quaternion()
	_pose_bones(g)


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
	_reset_spring()
	_sync()


var _q := {}  # Gelenk -> Drehung der Animationsfeder (eigener Zustand, siehe pose_spring)


## Weich zur Pose federn (kritisch gedaempfte Feder je Gelenk): Bewegungen beschleunigen und
## bremsen natuerlich statt ruckartig. w = Steifigkeit (hoeher = schneller, ~18 ruhig, ~45 Schlag).
## Gefedert wird als Drehung (Quaternion, immer der kurze Weg), nicht in Euler-Winkeln: so
## springt kein Gelenk, wenn ein Winkel ueber 180 Grad umklappt. Die Feder hat einen eigenen
## Zustand; was danach auf die Knoten kommt (Ball-IK, Fuesse, Physik), wirkt nicht zurueck.
## Bewegungskette: wie schnell jedes Gelenk seiner Zielhaltung folgt (relativ). Kopf und Rumpf
## fuehren, Arm und Hand folgen spaeter nach (Schwung von innen nach aussen), Beine bleiben straff.
const CHAIN := {"hips": 1.1, "chest": 0.95, "head": 1.3, "sh_l": 0.88, "sh_r": 0.88, "el_l": 0.78, "el_r": 0.78,
	"wr_l": 0.68, "wr_r": 0.68}
const INERT_RATE := 9.0  # rad/s: springt die Zielhaltung schneller, wird der Sprung weich abgebaut
const INERT_LEG_MAX := 0.3  # rad: Beine nur wenig versetzen (sonst verdreht sich das Knie gegen die Fuss-IK)
const INERT_T := 0.11  # s: Abklingzeit des Versatzes nach einem Sprung
var _tq := {}  # Gelenk -> letzte Zielhaltung (ohne Versatz)
var _tstep := {}  # Gelenk -> Aenderung der Zielhaltung im letzten Takt
var _toff := {}  # Gelenk -> Versatz, der nach einem Sprung der Zielhaltung abklingt


## Weiche Uebergaenge (Traegheits-Ueberblendung): springt die Zielhaltung eines Gelenks (neue
## Aktion, neu geplanter Ballkontakt), wird nicht dorthin gerissen; der Versatz zum alten Ziel
## klingt stattdessen weich ab. So bleibt die Bewegung stetig, ohne sie sonst zu verzoegern.
func _inertial(name: String, target: Quaternion, delta: float) -> Quaternion:
	var off: Quaternion = _toff.get(name, Quaternion.IDENTITY)
	var prev: Quaternion = _tq.get(name, target)
	var last: Quaternion = _tstep.get(name, Quaternion.IDENTITY)
	_tq[name] = target
	var step := target * prev.inverse()
	# Schnelle, aber stetige Bewegung (Schlag, Peitsche) ist kein Sprung: nur wenn sich die
	# Geschwindigkeit des Ziels in einem Takt sprunghaft aendert.
	var dev := step * last.inverse()
	if dev.w < 0.0:
		dev = -dev
	if dev.get_angle() > INERT_RATE * delta:
		# Sprung: Versatz so, dass das wirksame Ziel dort bleibt, wo es war
		off = (off * prev * target.inverse()).normalized()
		_tstep[name] = Quaternion.IDENTITY
	else:
		_tstep[name] = step
	off = Quaternion.IDENTITY.slerp(off, exp(-delta / INERT_T))
	if name.begins_with("kn_") or name.begins_with("hip_") or name.begins_with("an_"):
		var oa := off.get_angle()
		if oa > INERT_LEG_MAX:
			off = Quaternion.IDENTITY.slerp(off, INERT_LEG_MAX / oa)
	_toff[name] = off
	return (off * target).normalized()


func pose_spring(p: Dictionary, delta: float, w: float) -> void:
	var steps := maxi(1, ceili(w * 1.3 * delta / 0.3))
	var dt := delta / steps
	for name in JOINTS:
		var target := _inertial(name, Quaternion.from_euler(p.get(name, Vector3.ZERO)), delta) if delta > 0.0 and not "inert" in VPlayer._off else Quaternion.from_euler(p.get(name, Vector3.ZERO))
		var wj: float = w * (1.0 if "chain" in VPlayer._off else CHAIN.get(name, 1.0))
		var n: Node3D = j[name]
		var q: Quaternion = _q.get(name, n.quaternion)
		var v: Vector3 = _vel.get(name, Vector3.ZERO)
		for i in steps:
			var e := target * q.inverse()
			if e.w < 0.0:
				e = -e
			var ang := e.get_angle()
			var err := e.get_axis() * ang if ang > 1e-6 else Vector3.ZERO
			v += err * (wj * wj * dt) - v * (2.0 * wj * dt)
			var vl := v.length()
			if vl > 1e-7:
				q = (Quaternion(v / vl, vl * dt) * q).normalized()
		if LEG_JOINTS.has(name):
			q = _limit(name, q)  # Beine: vor der Fuss-IK begrenzen, damit die Fuesse fest stehen bleiben
		_q[name] = q
		_vel[name] = v
		n.quaternion = q
	_sync()


## Federzustand an die aktuelle Haltung der Knoten angleichen (nach pose(), Wiederholung).
func _reset_spring() -> void:
	_tw_prev.clear()
	_swiv.clear()
	_tq.clear()
	_tstep.clear()
	_toff.clear()
	for name in JOINTS:
		_q[name] = (j[name] as Node3D).quaternion
		_vel[name] = Vector3.ZERO
		_pq[name] = _q[name]
		_pv[name] = Vector3.ZERO


# ---------------------------------------------------------------- Semi-Ragdoll
# Die fertige Haltung (Animation + Ball-IK + feste Fuesse) ist nur das Ziel. Jedes Gelenk ist ein
# Motor mit Masse, der diesem Ziel mit einer bestimmten Kraft folgt (gedaempfte Feder). Stoesse
# (Ball, Landung, Zusammenprall) geben den Gelenken Schwung, weich gestellte Gelenke (soften)
# geben nach und schwingen nach. Wo es genau sein muss (Hand am Ball, Fuss am Boden), haelt
# pin das Gelenk auf dem Ziel. Alles im Physiktakt und ohne Zufall: Wiederholungen bleiben gleich.

var _pq := {}  # Gelenk -> Drehung (Physik)
var _pv := {}  # Gelenk -> Winkelgeschwindigkeit (rad/s, im Raum des Elterngelenks)
var pin := {}  # Gelenk -> 0..1, nur fuer diesen Takt (vom Spieler gesetzt)
var _soft := {}  # Gelenk -> [Faktor fuer die Kraft, verbleibende Zeit]
var phys_k := 42.0  # Grundkraft: hoeher = folgt schneller (1/s)
var phys_zeta := 0.75  # Daempfung: unter 1 schwingt ein wenig nach
## Kraft je Gelenk (Anteil von phys_k): Rumpf und Kopf weicher, sie schwingen sichtbar nach.
## Beine straff: ein nachhaengendes Schwungbein wuerde in den Boden treten.
const PHYS_K := {"hips": 1.4, "chest": 0.75, "head": 0.55, "sh_l": 0.95, "sh_r": 0.95, "el_l": 0.9, "el_r": 0.9,
	"wr_l": 0.8, "wr_r": 0.8, "hip_l": 3.0, "hip_r": 3.0, "kn_l": 3.0, "kn_r": 3.0, "an_l": 2.5, "an_r": 2.5}


## Menschliche Gelenkgrenzen (rad) als [Drehung um die Knochenachse lo, hi, Beugen um X lo, hi,
## seitlich um Z lo, hi]. Am Ende jedes Takts wird jedes Gelenk weich in seinen Bereich gebremst:
## so kann sich nichts unmenschlich verdrehen, auch wenn Clip, IK und Handausrichtung einmal
## gegeneinander arbeiten. (Werte aus den Bereichen, die die Animationen im Spiel wirklich nutzen.)
const LIMITS := {
	"chest": [-1.0, 1.0, -1.2, 0.6, -0.7, 0.7], "head": [-1.2, 1.2, -1.0, 1.55, -0.75, 0.75],
	"el_l": [-1.1, 1.1, -0.05, 2.6, -0.45, 0.45], "el_r": [-1.1, 1.1, -0.05, 2.6, -0.45, 0.45],
	"hip_l": [-0.7, 0.7, -0.5, 2.1, -1.0, 0.45], "hip_r": [-0.7, 0.7, -0.5, 2.1, -0.45, 1.0],
	"kn_l": [-0.55, 0.55, -2.5, 0.0, -0.35, 0.35], "kn_r": [-0.55, 0.55, -2.5, 0.0, -0.35, 0.35],
	"an_l": [-0.9, 0.9, -1.1, 1.1, -0.8, 0.8], "an_r": [-0.9, 0.9, -1.1, 1.1, -0.8, 0.8]}
var swivel_on := not "swivel" in ",".join(OS.get_cmdline_user_args()).get_slice("--lab-off=", 1)
var hand_lim_on := not "handlim" in ",".join(OS.get_cmdline_user_args()).get_slice("--lab-off=", 1)
var limits: Dictionary = {} if "limits" in ",".join(OS.get_cmdline_user_args()).get_slice("--lab-off=", 1) else LIMITS
static var jstats := {}  # Labor: Gelenkwinkel sammeln (--lab-jstats)
static var _jstat_on := "--lab-jstats" in ",".join(OS.get_cmdline_user_args())


## Drehung in (Beugen X, Drehung um Y = Knochenachse, seitlich Z) zerlegen (Swing-Twist).
static func swing_twist(q: Quaternion) -> Vector3:
	if q.w < 0.0:
		q = -q
	var tw := 2.0 * atan2(q.y, q.w)
	var twist := Quaternion(Vector3.UP, tw)
	var sw := (q * twist.inverse()).normalized()
	if sw.w < 0.0:
		sw = -sw
	var sa := 2.0 * acos(clampf(sw.w, -1.0, 1.0))
	var sv := Vector3(sw.x, sw.y, sw.z)
	var v := sv.normalized() * sa if sv.length() > 1e-6 else Vector3.ZERO
	return Vector3(v.x, wrapf(tw, -PI, PI), v.z)


static func _soft_clamp(x: float, lo: float, hi: float, k := 0.15) -> float:
	if x > hi - k:
		return hi - k + k * tanh((x - hi + k) / k)
	if x < lo + k:
		return lo + k - k * tanh((lo + k - x) / k)
	return x


const LEG_JOINTS := ["hip_l", "kn_l", "an_l", "hip_r", "kn_r", "an_r"]
var _tw_prev := {}  # Gelenk -> letzte Drehung um die Knochenachse (fortlaufend, ohne Sprung bei +-180 Grad)


func _limit(name: String, q: Quaternion) -> Quaternion:
	if _jstat_on:
		var st: Array = jstats.get(name, [])
		if st.size() < 200000:
			st.append(swing_twist(q))
		jstats[name] = st
	var lim: Array = limits.get(name, [])
	if lim.is_empty():
		return q
	var a := swing_twist(q)
	# Drehung fortlaufend zaehlen: steht ein Gelenk ueber der Grenze nahe +-180 Grad, darf es nicht
	# zwischen beiden Grenzen hin und her springen.
	if _tw_prev.has(name):
		var pv: float = _tw_prev[name]
		a.y = pv + wrapf(a.y - pv, -PI, PI)
		if absf(a.y) > TAU:
			a.y = wrapf(a.y, -PI, PI)
	_tw_prev[name] = a.y
	var b := Vector3(_soft_clamp(a.x, lim[2], lim[3]), _soft_clamp(a.y, lim[0], lim[1]), _soft_clamp(a.z, lim[4], lim[5]))
	if b.is_equal_approx(a):
		return q
	var sv := Vector3(b.x, 0.0, b.z)
	var sw := Quaternion(sv.normalized(), sv.length()) if sv.length() > 1e-6 else Quaternion.IDENTITY
	return (sw * Quaternion(Vector3.UP, b.y)).normalized()


func physics_step(delta: float) -> void:
	if delta <= 0.0:
		return
	for name in JOINTS:
		var n: Node3D = j[name]
		var t: Quaternion = n.quaternion
		# Ziel in den menschlichen Bereich holen, die Physik-Feder folgt dann weich dorthin
		# (Beine schon vor der Fuss-IK, siehe pose_spring).
		if name.begins_with("wr_"):
			t = limit_hand(name.right(1), (j["el_" + name.right(1)] as Node3D).quaternion, t)
		elif not LEG_JOINTS.has(name):
			t = _limit(name, t)
		var q: Quaternion = _pq.get(name, t)
		var v: Vector3 = _pv.get(name, Vector3.ZERO)
		var k: float = phys_k * PHYS_K.get(name, 1.0)
		var sf: Array = _soft.get(name, [])
		if not sf.is_empty():
			k *= lerpf(1.0, float(sf[0]), clampf(float(sf[1]) / 0.08, 0.0, 1.0))  # Ende weich ausblenden
			sf[1] = float(sf[1]) - delta
			if float(sf[1]) <= 0.0:
				_soft.erase(name)
		var steps := maxi(1, ceili(k * delta / 0.25))
		var dt := delta / steps
		for i in steps:
			var e := t * q.inverse()
			if e.w < 0.0:
				e = -e
			var ang := e.get_angle()
			var err := e.get_axis() * ang if ang > 1e-6 else Vector3.ZERO
			v += err * (k * k * dt) - v * (2.0 * phys_zeta * k * dt)
			var vl := v.length()
			if vl > 1e-7:
				q = (Quaternion(v / vl, vl * dt) * q).normalized()
		var pw: float = clampf(pin.get(name, 0.0), 0.0, 1.0)
		if pw > 0.0:
			q = q.slerp(t, pw)
			v *= 1.0 - pw
		_pq[name] = q
		_pv[name] = v
		n.quaternion = q
	pin.clear()
	_sync()


## Schwung auf ein Gelenk geben (rad/s im Raum des Elterngelenks, z. B. Vector3(-3, 0, 0)).
func impulse(name: String, w: Vector3) -> void:
	_pv[name] = (_pv.get(name, Vector3.ZERO) as Vector3) + w


## Ein Gelenk fuer eine Weile weicher stellen (factor < 1: gibt nach, schwingt laenger).
func soften(name: String, factor: float, seconds: float) -> void:
	_soft[name] = [factor, seconds]


## Weltrichtung als Winkelgeschwindigkeit im Raum des Elterngelenks (fuer impulse()).
func world_to_parent(name: String, w_world: Vector3) -> Vector3:
	var par := (j[name] as Node3D).get_parent() as Node3D
	return par.global_basis.orthonormalized().inverse() * w_world


## Arm so stellen, dass das Handgelenk an der Weltposition target sitzt (Ballkontakt).
## w blendet zwischen Pose (0) und Ziel (1). Rueckgabe: verbleibender Abstand in m.
## pole (Welt): wohin der Ellbogen zeigen soll, z. B. hoch und nach hinten beim Ausholen zum Schlag.
## Vector3.INF = Ellbogen bleibt in der Ebene der Animation.
func ik_arm(sd: String, target: Vector3, w: float, iters := 10, damp := 0.02, pole := Vector3.INF, pole_w := 1.0) -> float:
	return _ik_limb("arm_" + sd, j["sh_" + sd], j["el_" + sd], j["wr_" + sd], target, w, iters, damp, 1.0, 0.0, 2.6, pole, pole_w)


## Bein so stellen, dass das Sprunggelenk an der Weltposition target sitzt (Fuss steht fest).
func ik_leg(sd: String, target: Vector3, w: float, iters := 10, damp := 0.005) -> float:
	return _ik_limb("leg_" + sd, j["hip_" + sd], j["kn_" + sd], j["an_" + sd], target, w, iters, damp, -1.0, 0.03, 2.6)


## Zwei-Glieder-IK, geometrisch statt geschaetzt: erst beugt das mittlere Gelenk (Ellbogen, Knie)
## als Scharnier so weit, dass der Abstand Schulter/Huefte -> Ziel stimmt (Kosinussatz), dann
## dreht das obere Gelenk das ganze Glied auf dem kuerzesten Weg zum Ziel. So bleibt die Ebene
## des Glieds aus der Animation erhalten und nichts klappt um, auch nicht bei hoch erhobenem Arm
## oder weit gebeugtem Knie. Alles als Drehungen (Quaternionen), keine Euler-Winkel.
## flex: Beugerichtung (+1 Ellbogen nach vorn, -1 Knie nach hinten), lo/hi: erlaubte Beugung.
func _ik_limb(_key: String, up: Node3D, mid: Node3D, end: Node3D, target: Vector3, w: float, _iters: int, _damp: float, flex: float, lo: float, hi: float, pole := Vector3.INF, pole_w := 1.0) -> float:
	var qu0 := up.quaternion
	var qm0 := mid.quaternion
	var u := up.global_position
	var l1 := u.distance_to(mid.global_position)
	var l2 := mid.global_position.distance_to(end.global_position)
	# Weiche Streckung: kurz vor ganz gestreckt waechst der Abstand nur noch langsam. Sonst
	# schnappt das Gelenk beim Hineinreichen in einem Takt von gestreckt auf gebeugt.
	var reach := l1 + l2
	var soft := reach * 0.06
	var raw := u.distance_to(target)
	if raw > reach - soft:
		raw = reach - soft + soft * (1.0 - exp(-(raw - reach + soft) / soft))
	var dist := clampf(raw, absf(l1 - l2) + 0.001, reach - 0.0005)
	# 1. Scharnier: zweimal messen und nachbeugen (die Achse liegt nicht ganz quer zum Glied)
	for it in 2:
		var cur := u.distance_to(end.global_position)
		var cos_cur := clampf((l1 * l1 + l2 * l2 - cur * cur) / (2.0 * l1 * l2), -1.0, 1.0)
		var cos_want := clampf((l1 * l1 + l2 * l2 - dist * dist) / (2.0 * l1 * l2), -1.0, 1.0)
		var more_bend := acos(cos_cur) - acos(cos_want)  # > 0: weiter beugen
		var d := mid.quaternion * Vector3.DOWN
		var bend := atan2(-flex * d.z, -d.y)
		more_bend = clampf(more_bend, lo - bend, hi - bend)
		mid.quaternion = mid.quaternion * Quaternion(Vector3.RIGHT, flex * more_bend)
	# 2. Oberes Gelenk dreht das Glied zum Ziel (Weltdrehung, ins Elterngelenk umgerechnet)
	var from := end.global_position - u
	var to := target - u
	if from.length() > 0.001 and to.length() > 0.001:
		var dq := _arc(from.normalized(), to.normalized())
		var pr := ((up.get_parent() as Node3D).global_basis.orthonormalized()).get_rotation_quaternion()
		up.quaternion = (pr.inverse() * dq * pr * up.quaternion).normalized()
	# 2b. Ellbogen/Knie um die Achse Schulter -> Ziel zum Pol drehen (Hand bleibt am Ziel)
	if pole != Vector3.INF and pole_w > 0.001:
		var ax := (end.global_position - u)
		if ax.length() > 0.01:
			ax = ax.normalized()
			var m := mid.global_position - u
			var pv := pole - u
			m -= ax * m.dot(ax)
			pv -= ax * pv.dot(ax)
			if m.length() > 0.005 and pv.length() > 0.005:
				# fast gestreckt: kaum ein sichtbarer Ellbogen, die Drehung wuerde nur den Arm verdrillen
				var ang := m.signed_angle_to(pv, ax)
				# Zeigt der Ellbogen fast genau vom Pol weg, springt der Winkel zwischen +180 und -180
				# Grad (Arm dreht sich in einem Takt einmal um). Dort blendet der Pol weich aus.
				ang *= 1.0 - smoothstep(2.3, 3.05, absf(ang))
				ang *= clampf(pole_w, 0.0, 1.0) * smoothstep(0.02, 0.16, m.length()) * smoothstep(0.04, 0.14, pv.length())
				var pr2 := ((up.get_parent() as Node3D).global_basis.orthonormalized()).get_rotation_quaternion()
				up.quaternion = (pr2.inverse() * Quaternion(ax, ang) * pr2 * up.quaternion).normalized()
	# 3. Mit w zwischen Animation und Loesung mischen
	var wk := clampf(w, 0.0, 1.0)
	if wk < 1.0:
		up.quaternion = qu0.slerp(up.quaternion, wk)
		mid.quaternion = qm0.slerp(mid.quaternion, wk)
	return end.global_position.distance_to(target)


## Kuerzeste Drehung, die Richtung a auf Richtung b dreht.
static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	var c := a.cross(b)
	var d := a.dot(b)
	if d < -0.9999:
		var ax := a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT).normalized()
		return Quaternion(ax, PI)
	return Quaternion(c.x, c.y, c.z, 1.0 + d).normalized()


## IK beginnt bei der Loesung aus dem letzten Takt (falls es einen gab): sonst landet die
## Rechnung jedes Mal etwas anders und Arm oder Bein zittern.
var _ik_last := {}  # Glied -> [Takt, Loesung]


func _ik_warm(key: String, v: Vector3) -> Vector3:
	var e: Array = _ik_last.get(key, [])
	var f := Engine.get_physics_frames()
	if not e.is_empty() and f - int(e[0]) <= 1:
		return e[1]
	return v


func _ik_keep(key: String, v: Vector3) -> void:
	_ik_last[key] = [Engine.get_physics_frames(), v]


## Gelenk so drehen, dass seine Weltausrichtung want ist (w blendet ein). Fuer feste Fuesse.
func orient_world(name: String, want: Basis, w: float) -> void:
	if w <= 0.001:
		return
	var n: Node3D = j[name]
	var parent_b := (n.get_parent() as Node3D).global_basis.orthonormalized()
	var local := (parent_b.inverse() * want.orthonormalized()).get_rotation_quaternion()
	n.quaternion = n.quaternion.slerp(local, clampf(w, 0.0, 1.0))


## Hand ausrichten: fingers = Richtung der Finger, palm = wohin die Handflaeche zeigt (Welt).
## In Ruhe zeigen die Finger nach unten und die Handflaeche zum Oberschenkel. w blendet ein.
var _hand_a := {}  # letzte Ziel-Handwinkel je Seite (orient_hand)
var _hand_f := {}  # Takt dazu
const HAND_MAX_STEP := 0.09  # rad je Takt (120 Hz): schnellste Drehung des Handziels


func orient_hand(sd: String, fingers: Vector3, palm: Vector3, w: float, swivel := 0.0) -> void:
	if w <= 0.001 or fingers.length() < 0.01 or palm.length() < 0.01:
		return
	var s := -1.0 if sd == "l" else 1.0
	var ly := -fingers.normalized()
	var lx := (-s * palm).normalized()
	lx = (lx - ly * lx.dot(ly)).normalized()  # rechtwinklig zu den Fingern machen
	var lz := lx.cross(ly).normalized()
	var want := Basis(lx, ly, lz).get_rotation_quaternion()
	var wr: Node3D = j["wr_" + sd]
	var el: Node3D = j["el_" + sd]
	# Ellbogen-Kreis: Die Hand kann eine Ausrichtung nur erreichen, wenn der Unterarm passend
	# steht. Der Arm darf sich dafuer um die Linie Schulter -> Handgelenk drehen (der Ellbogen
	# wandert auf einem Kreis, das Handgelenk bleibt am Ball). Gesucht wird die Stellung, in der
	# Unterarm und Handgelenk am bequemsten im menschlichen Bereich bleiben, nahe an der Vorgabe.
	if swivel > 0.0 and swivel_on:
		var sh: Node3D = j["sh_" + sd]
		var ax := wr.global_position - sh.global_position
		var a_best := 0.0
		if ax.length() > 0.05:
			ax = ax.normalized()
			var eb := el.global_basis.orthonormalized().get_rotation_quaternion()
			var tw_el := twist_angle(el.quaternion, _fa_axis[sd])
			var c_best := INF
			for i in range(-10, 11):
				var a := swivel * i / 10.0
				var h := (Quaternion(ax, a) * eb).inverse() * want
				var c := _hand_cost(sd, tw_el, h) + 0.5 * a * a
				if c < c_best:
					c_best = c
					a_best = a
		var e: Array = _swiv.get(sd, [0, 0.0])
		var prev: float = e[1] if Engine.get_physics_frames() - int(e[0]) <= 2 else 0.0
		var a_s := prev + (a_best - prev) * 0.1
		_swiv[sd] = [Engine.get_physics_frames(), a_s]
		# Bei stark gebeugtem Arm (Hand nahe der Schulter) ist die Achse unsicher: dort nicht drehen.
		var reach := (wr.global_position - sh.global_position).length() / maxf(root_node.scale.x, 0.5)
		var aw := a_s * clampf(w, 0.0, 1.0) * smoothstep(0.18, 0.32, reach)
		if absf(aw) > 1e-4 and ax.length() > 0.5:
			var pr := ((sh.get_parent() as Node3D).global_basis.orthonormalized()).get_rotation_quaternion()
			sh.quaternion = (pr.inverse() * Quaternion(ax, aw) * pr * sh.quaternion).normalized()
	var parent_b := el.global_basis.orthonormalized().get_rotation_quaternion()
	var h := parent_b.inverse() * want
	if not hand_lim_on or limits.is_empty():
		wr.quaternion = wr.quaternion.slerp(h, clampf(w, 0.0, 1.0)).normalized()
		return
	# Eingeblendet wird in den Gelenkwinkeln (Unterarm-Drehung, Strecken, Seitneigung), nicht als
	# Drehung im Raum: liegen Pose und Ziel weit auseinander, gibt es sonst zwei Wege um die Achse,
	# und die Hand springt von einem auf den anderen. Beide Enden liegen im menschlichen Bereich,
	# also auch alles dazwischen.
	var tw_el := twist_angle(el.quaternion, _fa_axis[sd])
	var a0 := _hand_limited(sd, tw_el, wr.quaternion, "hand0_" + sd)
	var a1 := _hand_limited(sd, tw_el, h, "hand_" + sd)
	if _jstat_on:
		var key := "hand_" + sd + "_" + (jstat_tag if w > 0.7 else "lowW")
		var st: Array = jstats.get(key, [])
		if st.size() < 200000:
			st.append(_hand_angles(sd, tw_el, h))
		jstats[key] = st
	# Springt das Ziel (etwa wenn der Ball hinter den Kopf wandert), dreht die Hand schnell, aber
	# sichtbar dorthin statt in einem Bild.
	if Engine.get_physics_frames() - int(_hand_f.get(sd, -10)) <= 2:
		var last: Vector3 = _hand_a[sd]
		var dv := a1 - last
		if dv.length() > HAND_MAX_STEP:
			a1 = last + dv * (HAND_MAX_STEP / dv.length())
			_tw_prev["hand_" + sd] = a1.y
	_hand_a[sd] = a1
	_hand_f[sd] = Engine.get_physics_frames()
	wr.quaternion = _hand_quat(sd, tw_el, a0.lerp(a1, clampf(w, 0.0, 1.0)))


## Menschlicher Bereich der Hand (rad): die Drehung um die Unterarmachse (Ellbogen plus Hand,
## wie Elle und Speiche) und das Abknicken im Handgelenk.
## [Pronation, Supination, Strecken (Handruecken nach hinten), Beugen, zur Daumenseite, zur Kleinfingerseite]
const HAND_LIM := [1.45, 1.4, 1.35, 1.3, 0.35, 0.6]
var _swiv := {}  # Seite -> [Takt, Drehung des Arms um Schulter -> Handgelenk] (orient_hand)
var jstat_tag := ""  # Labor: Aktion fuer die Statistik der Handwinkel


## Hand relativ zum Ellbogen (h) in Unterarm-Drehung und Abknicken zerlegen. Rueckgabe:
## Vector3(zur Daumenseite +, Pronation +, Strecken +), fuer beide Seiten gleich gerechnet.
## (Die Unterarmachse zeigt vom Ellbogen zur Hand; Pronation rechts = negative Drehung um sie.)
func _hand_angles(sd: String, tw_el: float, h: Quaternion) -> Vector3:
	var d: Vector3 = _fa_axis[sd]
	var tw_h := twist_angle(h, d)
	var sw := Quaternion(d, -tw_h) * h
	if sw.w < 0.0:
		sw = -sw
	var v := sw.get_axis() * sw.get_angle() if sw.get_angle() > 1e-6 else Vector3.ZERO
	var s := -1.0 if sd == "l" else 1.0
	return Vector3(v.x, -s * (tw_el + tw_h), s * v.z)


func _hand_cost(sd: String, tw_el: float, h: Quaternion) -> float:
	var a := _hand_angles(sd, tw_el, h)
	var tw := wrapf(a.y, -PI, PI)
	var c := 0.0
	c += pow(maxf(0.0, tw - (HAND_LIM[0] - 0.25)), 2.0) + pow(maxf(0.0, -tw - (HAND_LIM[1] - 0.25)), 2.0)
	c += pow(maxf(0.0, a.z - (HAND_LIM[2] - 0.2)), 2.0) + pow(maxf(0.0, -a.z - (HAND_LIM[3] - 0.2)), 2.0)
	c += 2.0 * (pow(maxf(0.0, a.x - HAND_LIM[4]), 2.0) + pow(maxf(0.0, -a.x - HAND_LIM[5]), 2.0))
	return c * 8.0 + 0.04 * tw * tw


## Hand weich in den menschlichen Bereich holen (el_q: Ellbogen-Gelenk, h: Hand relativ zum Ellbogen).
func limit_hand(sd: String, el_q: Quaternion, h: Quaternion) -> Quaternion:
	if limits.is_empty() or not hand_lim_on or not _fa_axis.has(sd):
		return h
	var tw_el := twist_angle(el_q, _fa_axis[sd])
	return _hand_quat(sd, tw_el, _hand_limited(sd, tw_el, h, "handp_" + sd))


## Handwinkel (siehe _hand_angles), fortlaufend gezaehlt (kein Sprung bei +-180 Grad, key merkt
## sich den letzten Wert) und weich in den menschlichen Bereich gebremst.
func _hand_limited(sd: String, tw_el: float, h: Quaternion, key: String) -> Vector3:
	var a := _hand_angles(sd, tw_el, h)
	a.y = wrapf(a.y, -PI, PI)
	# Weit hinter der Grenze (nahe 180 Grad) bleibt die Hand auf der Seite, von der sie kam, statt
	# zur anderen Grenze zu springen. Im erreichbaren Bereich zaehlt immer der echte Winkel.
	if _tw_prev.has(key):
		var pv: float = _tw_prev[key]
		if absf(a.y) > 2.2 and absf(pv) > 1.0 and signf(a.y) != signf(pv):
			a.y += TAU * signf(pv)
	_tw_prev[key] = a.y
	return Vector3(_soft_clamp(a.x, -HAND_LIM[5], HAND_LIM[4]), _soft_clamp(a.y, -HAND_LIM[1], HAND_LIM[0]),
		_soft_clamp(a.z, -HAND_LIM[3], HAND_LIM[2]))


## Handdrehung relativ zum Ellbogen aus den Handwinkeln (Umkehrung von _hand_angles).
func _hand_quat(sd: String, tw_el: float, a: Vector3) -> Quaternion:
	var s := -1.0 if sd == "l" else 1.0
	var sv := Vector3(a.x, 0.0, s * a.z)
	var sw := Quaternion(sv.normalized(), sv.length()) if sv.length() > 1e-6 else Quaternion()
	return (Quaternion(_fa_axis[sd], -s * a.y - tw_el) * sw).normalized()


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
	# Gelenke als Quaternion: so laesst sich im Replay weich zwischen zwei Bildern mischen, ohne dass
	# Euler-Winkel ueber +-180 Grad springen und Arme oder Beine einmal herumzucken.
	var out := []
	for name in JOINTS:
		out.append((j[name] as Node3D).quaternion)
	out.append(root_node.position)
	out.append(root_node.quaternion)
	out.append(finger_state())
	return out


## Zwischen zwei Aufnahmen von capture() mischen (w = 0..1).
static func mix_capture(a: Array, b: Array, w: float) -> Array:
	var out := []
	for i in a.size():
		if a[i] is Quaternion:
			out.append((a[i] as Quaternion).slerp(b[i], w))
		elif a[i] is PackedFloat32Array:
			var fa: PackedFloat32Array = a[i]
			var fb: PackedFloat32Array = b[i]
			var fm := fa.duplicate()
			for k in mini(fa.size(), fb.size()):
				fm[k] = lerpf(fa[k], fb[k], w)
			out.append(fm)
		else:
			out.append((a[i] as Vector3).lerp(b[i], w))
	return out


func apply(c: Array) -> void:
	for i in JOINTS.size():
		(j[JOINTS[i]] as Node3D).quaternion = c[i]
	root_node.position = c[JOINTS.size()]
	root_node.quaternion = c[JOINTS.size() + 1]
	if c.size() > JOINTS.size() + 2:
		set_finger_state(c[JOINTS.size() + 2])
	_reset_spring()
	_sync()
