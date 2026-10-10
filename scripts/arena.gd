class_name Arena
extends Node3D
## Low-Poly-Sporthalle: Boden mit Spielfeld, Netz, Tribuenen, Werbebanden, Anzeigetafeln,
## Decke mit Lichtfeldern, Schiedsrichter auf dem Stuhl, Bank mit Auswechselspielern,
## Kampfgericht. Hell und freundlich.

const TEAM_COLORS := [Color(0.16, 0.38, 0.86), Color(0.85, 0.2, 0.18)]
const SPONSORS := ["NORDHAFEN WERFT", "EICHENBERG BRÄU", "VOLLEY TV", "BÄCKEREI KORN", "STADTWERKE", "SPORT MAYER", "HAFENBANK", "BERGQUELLE"]

var referee: HumanFigure
var _boards: Array = []  # Label3D der Anzeigetafeln
var _ref_pose := ""
var _ref_side := 0.0
var _whistle_t := -10.0
var _time := 0.0
var bench: Array = [[], []]  # sitzende Figuren je Team


func _mat(c: Color, rough := 0.85, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = HumanFigure.box(size)
	mi.material_override = mat
	mi.position = pos
	(parent if parent else self).add_child(mi)
	return mi


func _cyl(r: float, h: float, pos: Vector3, mat: Material, seg := 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = HumanFigure.cyl(r, r, h, seg)
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _label(text: String, pos: Vector3, rot_y: float, size: int, col: Color, px := 0.01) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 0
	l.double_sided = false
	l.position = pos
	l.rotation.y = rot_y
	add_child(l)
	return l


func _ready() -> void:
	_environment()
	_floor()
	_net()
	_walls_and_ceiling()
	_stands()
	_ad_boards()
	_scoreboards()
	_officials()


func _environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.72)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.92, 0.94, 1.0)
	e.ambient_light_energy = 0.42
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.92
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-68.0, -28.0, 0.0)
	sun.light_energy = 0.9
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.65
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	# Zweites, schwaches Licht von der anderen Seite, damit nichts zu dunkel wird.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35.0, 150.0, 0.0)
	fill.light_energy = 0.22
	add_child(fill)


func _floor() -> void:
	# Freizone blau, Spielfeld orange (18 x 9 m), Linien 5 cm
	_box(Vector3(44.0, 0.1, 30.0), Vector3(0, -0.05, 0), _mat(Color(0.22, 0.5, 0.82), 0.6))
	_box(Vector3(18.0, 0.01, 9.0), Vector3(0, 0.003, 0), _mat(Color(0.9, 0.42, 0.18), 0.55))
	var white := _mat(Color(0.98, 0.98, 0.98), 0.5)
	var lw := 0.05
	for x in [-9.0, 9.0]:
		_box(Vector3(lw, 0.012, 9.0 + lw), Vector3(x, 0.006, 0), white)
	for z in [-4.5, 4.5]:
		_box(Vector3(18.0 + lw, 0.012, lw), Vector3(0, 0.006, z), white)
	for x in [-3.0, 0.0, 3.0]:
		_box(Vector3(lw, 0.012, 9.0), Vector3(x, 0.006, 0), white)
	# Angriffslinien gestrichelt ueber das Feld hinaus verlaengert (FIVB)
	for x in [-3.0, 3.0]:
		for sz in [-1.0, 1.0]:
			for k in 5:
				_box(Vector3(lw, 0.012, 0.15), Vector3(x, 0.006, sz * (4.5 + 0.25 + k * 0.35)), white)
	# Trainerzone und Aufwaermflaechen (dezent dunkler)
	for sx in [-1.0, 1.0]:
		_box(Vector3(3.0, 0.008, 3.0), Vector3(sx * 13.5, 0.004, 9.0), _mat(Color(0.19, 0.44, 0.74), 0.6))


## Netz als Gitter-Textur, Ober- und Unterband, Antennen rot-weiss, Pfosten mit Polster.
func _net() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 64:
		for k in 3:
			img.set_pixel(i, k, Color(0.05, 0.05, 0.06, 0.95))
			img.set_pixel(k, i, Color(0.05, 0.05, 0.06, 0.95))
	var tex := ImageTexture.create_from_image(img)
	var nm := StandardMaterial3D.new()
	nm.albedo_texture = tex
	nm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	nm.alpha_scissor_threshold = 0.4
	nm.cull_mode = BaseMaterial3D.CULL_DISABLED
	nm.uv1_scale = Vector3(98.0, 10.0, 1.0)
	nm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(9.8, 0.95)
	q.mesh = qm
	q.material_override = nm
	q.rotation.y = PI / 2.0
	q.position = Vector3(0, 1.915, 0)
	add_child(q)
	var white := _mat(Color(0.98, 0.98, 0.98))
	_box(Vector3(0.03, 0.07, 9.8), Vector3(0, 2.395, 0), white)
	_box(Vector3(0.02, 0.05, 9.8), Vector3(0, 1.44, 0), white)
	for z in [-4.5, 4.5]:
		_box(Vector3(0.025, 0.95, 0.05), Vector3(0, 1.915, z), white)  # Seitenband
		for k in 9:
			var c := Color(0.92, 0.12, 0.12) if k % 2 == 0 else Color(0.98, 0.98, 0.98)
			_cyl(0.011, 0.2, Vector3(0, 1.53 + 0.2 * k, z), _mat(c), 6)
	for z in [-5.6, 5.6]:
		_cyl(0.055, 2.6, Vector3(0, 1.3, z), _mat(Color(0.75, 0.77, 0.8), 0.4), 8)
		_cyl(0.13, 1.8, Vector3(0, 0.9, z), _mat(Color(0.12, 0.3, 0.65)), 8)  # Polster
		_box(Vector3(0.5, 0.06, 0.5), Vector3(0, 0.03, z), _mat(Color(0.3, 0.32, 0.36)))


func _walls_and_ceiling() -> void:
	var wall := _mat(Color(0.86, 0.88, 0.92))
	var band := _mat(Color(0.2, 0.32, 0.55))
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.5, 14.0, 52.0), Vector3(sx * 26.0, 7.0, 0), wall)
		_box(Vector3(0.52, 1.6, 52.0), Vector3(sx * 25.98, 3.4, 0), band)
		_box(Vector3(60.0, 14.0, 0.5), Vector3(0, 7.0, sx * 21.0), wall)
		_box(Vector3(60.0, 1.6, 0.52), Vector3(0, 9.0, sx * 20.98), band)
		# Fensterband oben, leuchtet etwas
		for k in 8:
			_box(Vector3(5.0, 1.4, 0.55), Vector3(-21.0 + k * 6.0, 11.6, sx * 20.97), _mat(Color(0.75, 0.88, 1.0), 0.3, 0.6))
	# Decke mit Traegern und Lichtfeldern
	_box(Vector3(60.0, 0.4, 44.0), Vector3(0, 14.2, 0), _mat(Color(0.42, 0.46, 0.55)))
	var beam := _mat(Color(0.32, 0.35, 0.42))
	for k in 7:
		_box(Vector3(0.35, 0.7, 42.0), Vector3(-21.0 + k * 7.0, 13.6, 0), beam)
	var lamp := _mat(Color(1.0, 0.98, 0.9), 0.3, 2.2)
	for xi in 6:
		for zi in 3:
			_box(Vector3(2.4, 0.12, 1.0), Vector3(-17.5 + xi * 7.0, 13.25, -7.0 + zi * 7.0), lamp)


## Tribuenen an beiden Laengsseiten und hinter den Grundlinien, Stufen mit farbigen Sitzreihen.
## Die Zuschauer (crowd.gd) stehen auf denselben Stufen.
func _stands() -> void:
	var step := _mat(Color(0.62, 0.65, 0.72))
	var rail := _mat(Color(0.85, 0.87, 0.9), 0.3)
	for sz in [-1.0, 1.0]:
		for i in CrowdView.ROWS:
			var h := 0.6 + i * 0.6
			var z: float = sz * (13.0 + i * 1.2)
			_box(Vector3(32.0, h, 1.2), Vector3(0, h / 2.0, z), step)
			# Sitzschalen: Bloecke in Vereinsfarben, in der Mitte grau
			for b in 8:
				var x0 := -15.0 + b * 4.0
				var col := TEAM_COLORS[0] if x0 < -2.0 else (TEAM_COLORS[1] if x0 > 1.0 else Color(0.5, 0.52, 0.58))
				_box(Vector3(3.8, 0.08, 0.4), Vector3(x0 + 2.0, h + 0.04, z + sz * 0.3), _mat(col.lerp(Color.WHITE, 0.15)))
		_box(Vector3(32.0, 0.06, 0.06), Vector3(0, 1.3, sz * 12.4), rail)
		for k in 9:
			_box(Vector3(0.06, 0.7, 0.06), Vector3(-16.0 + k * 4.0, 0.95, sz * 12.4), rail)
	for sx in [-1.0, 1.0]:
		for i in CrowdView.ROWS:
			var h := 0.6 + i * 0.6
			var x: float = sx * (18.5 + i * 1.2)
			_box(Vector3(1.2, h, 22.0), Vector3(x, h / 2.0, 0), step)
			var col: Color = TEAM_COLORS[0 if sx < 0.0 else 1]
			_box(Vector3(0.4, 0.08, 21.0), Vector3(x + sx * 0.3, h + 0.04, 0), _mat(col.lerp(Color.WHITE, 0.15)))


func _ad_boards() -> void:
	var k := 0
	# Laengsseiten (hinter Bank und Kampfgericht) und hinter den Grundlinien
	for sz in [-1.0, 1.0]:
		for b in 5:
			var x := -12.0 + b * 6.0
			_board(Vector3(x, 0.5, sz * 10.5), Vector3(5.8, 0.9, 0.12), PI if sz < 0.0 else 0.0, k)
			k += 1
	for sx in [-1.0, 1.0]:
		for b in 3:
			var z := -6.0 + b * 6.0
			_board(Vector3(sx * 15.0, 0.5, z), Vector3(0.12, 0.9, 5.8), PI / 2.0 if sx < 0.0 else -PI / 2.0, k)
			k += 1


func _board(pos: Vector3, size: Vector3, rot_y: float, k: int) -> void:
	var hue := fmod(k * 0.13, 1.0)
	var bg := Color.from_hsv(hue, 0.55, 0.85)
	_box(size, pos, _mat(bg, 0.5, 0.25))
	# Schrift auf der Feldseite
	var inward := Vector3(0, 0, 1).rotated(Vector3.UP, rot_y) * 0.07
	_label(SPONSORS[k % SPONSORS.size()], pos + inward, rot_y, 64, Color(1, 1, 1), 0.0075)


func _scoreboards() -> void:
	for sx in [-1.0, 1.0]:
		var pos := Vector3(sx * 25.6, 6.4, 0)
		var rot := PI / 2.0 if sx < 0.0 else -PI / 2.0
		_box(Vector3(0.4, 3.0, 9.0), pos, _mat(Color(0.08, 0.09, 0.12), 0.4))
		_box(Vector3(0.42, 0.2, 9.2), pos + Vector3(0, 1.55, 0), _mat(Color(1.0, 0.78, 0.25), 0.5, 0.4))
		var inward := Vector3(0, 0, 1).rotated(Vector3.UP, rot) * 0.22
		var l := _label("", pos + inward, rot, 96, Color(1.0, 0.95, 0.75), 0.006)
		l.shaded = false
		_boards.append(l)


func set_scoreboard(text: String) -> void:
	for l in _boards:
		l.text = text


# ---------------------------------------------------------------- Schiedsrichter und Bank

func _officials() -> void:
	# Schiedsrichterstuhl am Netzpfosten (Seite z negativ), Plattform auf 1,4 m
	var metal := _mat(Color(0.75, 0.77, 0.8), 0.4)
	for dx in [-0.35, 0.35]:
		for dz in [-0.35, 0.35]:
			_cyl(0.03, 1.4, Vector3(dx, 0.7, -6.3 + dz), metal, 6)
	_box(Vector3(0.9, 0.08, 0.9), Vector3(0, 1.42, -6.3), _mat(Color(0.2, 0.3, 0.55)))
	_box(Vector3(0.9, 0.5, 0.06), Vector3(0, 1.7, -6.73), metal)
	referee = HumanFigure.new()
	add_child(referee)
	referee.build({"jersey": Color(0.97, 0.97, 0.97), "shorts": Color(0.12, 0.13, 0.17), "skin": Color(0.9, 0.72, 0.58),
		"hair": Color(0.45, 0.45, 0.47), "shoes": Color(0.1, 0.1, 0.1), "socks": Color(0.12, 0.13, 0.17), "trim": Color(0.12, 0.13, 0.17)}, false, 0)
	referee.position = Vector3(0, 1.46, -6.3)
	referee.rotation.y = PI  # schaut zum Feld (+z)
	referee.pose(_ref_idle())

	# Kampfgericht gegenueber, Tisch mit zwei Schreibern
	_box(Vector3(2.4, 0.75, 0.7), Vector3(0, 0.375, 8.6), _mat(Color(0.2, 0.3, 0.55)))
	_box(Vector3(2.5, 0.05, 0.8), Vector3(0, 0.77, 8.6), _mat(Color(0.95, 0.95, 0.95)))
	for x in [-0.6, 0.6]:
		var f := _seated({"jersey": Color(0.95, 0.95, 0.95), "shorts": Color(0.15, 0.15, 0.2)}, Vector3(x, 0, 9.3), 0.0)
		f.pose(_sit_pose(true), 1.0)
	# Bank: sechs Ersatzspieler je Team, in der Haelfte des eigenen Teams
	for t in 2:
		var sx := -1.0 if t == 0 else 1.0
		_box(Vector3(4.2, 0.45, 0.5), Vector3(sx * 6.2, 0.225, 9.0), _mat(Color(0.3, 0.32, 0.38)))
		for i in 6:
			var c := {"jersey": TEAM_COLORS[t], "shorts": Color(0.08, 0.12, 0.3) if t == 0 else Color(0.95, 0.95, 0.95),
				"skin": VPlayer.SKINS[(i * 3 + t) % VPlayer.SKINS.size()], "hair": VPlayer.HAIRS[(i + t * 2) % VPlayer.HAIRS.size()]}
			var f := _seated(c, Vector3(sx * (4.4 + i * 0.7), 0, 9.05), 0.0)
			f.set_number(20 + i + t * 10, Color.WHITE)
			bench[t].append(f)


func _seated(colors: Dictionary, pos: Vector3, rot_y: float) -> HumanFigure:
	var f := HumanFigure.new()
	add_child(f)
	f.hips_height = 0.5
	f.build(colors, false, int(pos.x * 10.0) % 3)
	f.position = pos
	f.rotation.y = rot_y
	f.pose(_sit_pose(false))
	return f


func _sit_pose(writing: bool) -> Dictionary:
	var p := {"chest": Vector3(-0.15, 0, 0), "head": Vector3(0.1, 0, 0),
		"hip_l": Vector3(1.45, 0, -0.1), "hip_r": Vector3(1.45, 0, 0.1),
		"kn_l": Vector3(-1.5, 0, 0), "kn_r": Vector3(-1.5, 0, 0),
		"an_l": Vector3(0.05, 0, 0), "an_r": Vector3(0.05, 0, 0)}
	var fwd := 1.1 if writing else 0.6
	var el := 1.0 if writing else 0.9
	p["sh_l"] = Vector3(fwd, 0, -0.1)
	p["sh_r"] = Vector3(fwd, 0, 0.1)
	p["el_l"] = Vector3(el, 0, 0)
	p["el_r"] = Vector3(el, 0, 0)
	return p


func _ref_idle() -> Dictionary:
	return {"chest": Vector3(-0.05, 0, 0), "head": Vector3(0.1, 0, 0),
		"sh_l": Vector3(0.15, 0, -0.08), "sh_r": Vector3(0.15, 0, 0.08), "el_l": Vector3(0.4, 0, 0), "el_r": Vector3(0.4, 0, 0)}


## Schiedsrichter-Handzeichen in 3D. team_x = Weltseite (x) des Teams, auf das er zeigt.
func referee_signal(sig: String, team_x: float) -> void:
	_ref_pose = sig
	_ref_side = team_x


func referee_whistle() -> void:
	_whistle_t = _time


func _process(delta: float) -> void:
	_time += delta / maxf(Engine.time_scale, 0.01)
	if referee == null:
		return
	# Der Schiedsrichter schaut zum Feld (+z); Welt -x liegt dann zu seiner Rechten (lokal +x).
	var arm_r := _ref_side < 0.0  # Team links im Bild der Kamera -> rechter Arm
	var p := _ref_idle()
	var s := "r" if arm_r else "l"
	var sgn := 1.0 if arm_r else -1.0
	match _ref_pose:
		"serve_0", "serve_1":
			p["sh_" + s] = Vector3(0.3, 0, sgn * 1.45)
			p["el_" + s] = Vector3(0.0, 0, 0)
		"in":
			p["sh_" + s] = Vector3(0.9, 0, sgn * 0.6)
			p["el_" + s] = Vector3(0.1, 0, 0)
		"out":
			p["sh_l"] = Vector3(2.9, 0, -0.15)
			p["sh_r"] = Vector3(2.9, 0, 0.15)
			p["el_l"] = Vector3(0.2, 0, 0)
			p["el_r"] = Vector3(0.2, 0, 0)
		"net":
			p["sh_" + s] = Vector3(1.4, 0, sgn * 0.5)
			p["el_" + s] = Vector3(0.4, 0, 0)
		"double", "fault":
			p["sh_" + s] = Vector3(2.9, 0, sgn * 0.2)
			p["el_" + s] = Vector3(0.1, 0, 0)
		"held":
			p["sh_" + s] = Vector3(1.6, 0, sgn * 0.3)
			p["el_" + s] = Vector3(1.2, 0, 0)
		"timeout":
			p["sh_l"] = Vector3(2.9, 0, -0.1)
			p["el_l"] = Vector3(0.1, 0, 0)
			p["sh_r"] = Vector3(2.5, 0, 0.9)
			p["el_r"] = Vector3(1.4, 0, 0)
		"sub":
			var roll := sin(_time * 8.0) * 0.4
			p["sh_l"] = Vector3(1.4 + roll, 0, 0.2)
			p["sh_r"] = Vector3(1.4 - roll, 0, -0.2)
			p["el_l"] = Vector3(1.4, 0, 0)
			p["el_r"] = Vector3(1.4, 0, 0)
		"sidechange", "setend":
			p["sh_l"] = Vector3(1.5, 0, 0.5)
			p["sh_r"] = Vector3(1.5, 0, -0.5)
			p["el_l"] = Vector3(0.6, 0, 0)
			p["el_r"] = Vector3(0.6, 0, 0)
	# Beim Pfiff: linke Hand kurz zum Mund
	if _time - _whistle_t < 0.6 and _ref_pose in ["", "serve_0", "serve_1", "in"]:
		var o := "l" if arm_r else "r"
		p["sh_" + o] = Vector3(2.0, 0, 0.0)
		p["el_" + o] = Vector3(2.3, 0, 0)
	referee.pose(p, clampf(delta * 10.0, 0.0, 1.0))
	# Bank: ab und zu ein bisschen Bewegung
	for t in 2:
		for i in bench[t].size():
			var f: HumanFigure = bench[t][i]
			f.j["head"].rotation.y = sin(_time * 0.4 + i * 1.7 + t) * 0.35
