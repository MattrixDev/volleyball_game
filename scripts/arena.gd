class_name Arena
extends Node3D
## Low-Poly-Sporthalle: Boden mit Spielfeld, Netz, Tribuenen, Werbebanden, Anzeigetafeln,
## Decke mit Lichtfeldern, Schiedsrichter auf dem Stuhl, Bank mit Auswechselspielern,
## Kampfgericht, Linienrichter. Die Halle selbst kommt aus Blender (assets/models/arena.glb,
## tools/blender/build_arena.py), hier werden Bildschirme, Licht und Figuren ergaenzt.

## Kleidung der Schiedsrichter, Linienrichter und Schreiber
const OFFICIAL := {"jersey": Color(0.86, 0.86, 0.84), "panel": Color(0.2, 0.21, 0.24), "collar": Color(0.2, 0.21, 0.24),
	"trousers": Color(0.17, 0.18, 0.2), "shoes": Color(0.14, 0.14, 0.15), "accent": Color(0.14, 0.14, 0.15), "sole": Color(0.3, 0.3, 0.3)}
const SPONSORS := ["NORDHAFEN WERFT", "EICHENBERG BRÄU", "VOLLEY TV", "BÄCKEREI KORN", "STADTWERKE", "SPORT MAYER", "HAFENBANK", "BERGQUELLE"]

var referee: HumanFigure
var _boards: Array = []  # Label3D der Anzeigetafeln
var _ref_pose := ""
var _ref_side := 0.0
var _whistle_t := -10.0
var _time := 0.0
var bench: Array = [[], []]  # sitzende Figuren je Team
var line_judges: Array = []  # [Figur, Ecke (Vector3)]
var ball_pos := Vector3.ZERO  # vom Spiel gesetzt: wo der Ball gerade ist
var _meshes := {}  # Name -> MeshInstance3D aus arena.glb
const HALL := preload("res://assets/models/arena.glb")
const FLAG := preload("res://assets/models/flag.glb")
## Gedaempfte Bandenfarben (wie die Stilvorlage)
const AD_COLORS := [Color(0.17, 0.21, 0.33), Color(0.45, 0.19, 0.22), Color(0.36, 0.45, 0.4), Color(0.66, 0.53, 0.28),
	Color(0.32, 0.36, 0.42), Color(0.6, 0.36, 0.27), Color(0.25, 0.37, 0.41), Color(0.5, 0.44, 0.38)]


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
	_hall()
	_screens()
	_officials()
	_line_judges()


## Weiches, gedaempftes Hallenlicht wie in der Stilvorlage: viel Umgebungslicht, eine
## schwache Hauptrichtung fuer die Facetten, weiche Schatten.
func _environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.21, 0.24)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.93, 0.92, 0.9)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.9
	e.adjustment_enabled = true
	e.adjustment_saturation = 0.88
	e.adjustment_contrast = 1.03
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62.0, -32.0, 0.0)
	sun.light_energy = 0.75
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.5
	sun.shadow_blur = 2.0
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	# Zweites, schwaches Licht von der anderen Seite, damit nichts zu dunkel wird.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35.0, 150.0, 0.0)
	fill.light_energy = 0.3
	fill.light_color = Color(0.9, 0.93, 1.0)
	add_child(fill)


## Halle aus Blender (tools/blender/build_arena.py): Boden, Linien, Netz, Pfosten,
## Schiedsrichterstuhl, Kampfgericht, Baenke, Tribuenen, Banden, Waende, Decke, Lampen.
func _hall() -> void:
	var hall: Node3D = HALL.instantiate()
	add_child(hall)
	for mi in hall.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		_meshes[String(m.name)] = m
		# Nur was nah am Feld steht wirft Schatten; Decke, Traeger und Waende wuerden sonst
		# grosse dunkle Flecken aufs Feld legen.
		if not String(m.name) in ["net_mesh", "net_bands", "antennas", "posts", "referee_stand", "scorer_table",
				"benches", "bench_props", "adboard_frames"]:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Bandenwerbung und Anzeigetafeln: die Bildschirme im Modell bekommen Farbe und Schrift.
func _screens() -> void:
	for k in 16:
		var m: MeshInstance3D = _meshes.get("adscreen_%d" % k)
		if m == null:
			continue
		var col: Color = AD_COLORS[k % AD_COLORS.size()]
		m.material_override = _mat(col, 0.6, 0.3)
		var c := m.mesh.get_aabb().get_center()
		var n := _facing(c)
		_label(SPONSORS[k % SPONSORS.size()], c + n * 0.04, atan2(n.x, n.z), 64, Color(0.96, 0.94, 0.89), 0.0075)
	for k in 2:
		var m: MeshInstance3D = _meshes.get("scorescreen_%d" % k)
		if m == null:
			continue
		m.material_override = _mat(Color(0.09, 0.1, 0.12), 0.4, 0.15)
		var c := m.mesh.get_aabb().get_center()
		var n := _facing(c)
		var l := _label("", c + n * 0.05, atan2(n.x, n.z), 96, Color(0.97, 0.9, 0.72), 0.006)
		l.shaded = false
		_boards.append(l)


## Richtung zum Feld (waagerecht, entlang der naeheren Achse).
func _facing(c: Vector3) -> Vector3:
	if absf(c.x) / 15.0 > absf(c.z) / 10.5:
		return Vector3(-signf(c.x), 0, 0)
	return Vector3(0, 0, -signf(c.z))


func set_scoreboard(text: String) -> void:
	for l in _boards:
		l.text = text


# ---------------------------------------------------------------- Schiedsrichter und Bank

func _officials() -> void:
	# Schiedsrichter auf dem Stuhl am Netzpfosten (Stuhl ist Teil von arena.glb)
	referee = HumanFigure.new()
	add_child(referee)
	referee.build(OFFICIAL.merged({"skin": Color(0.86, 0.68, 0.55), "hair": Color(0.42, 0.42, 0.43)}), false, 1, true)
	referee.position = Vector3(0, 1.468, -6.3)
	referee.rotation.y = PI  # schaut zum Feld (+z)
	referee.pose(_ref_idle())

	# Kampfgericht gegenueber: zwei Schreiber am Tisch
	for x in [-0.6, 0.6]:
		var f := _seated(OFFICIAL.merged({"skin": VPlayer.SKINS[1 if x < 0.0 else 3], "hair": VPlayer.HAIRS[2 if x < 0.0 else 4]}),
			Vector3(x, 0, 9.3), 0.0, true, 0.55)
		f.pose(_sit_pose(true), 1.0)
	# Bank: sechs Ersatzspieler je Team, in der Haelfte des eigenen Teams
	for t in 2:
		var sx := -1.0 if t == 0 else 1.0
		for i in 6:
			var style: TeamStyle = Teams.playing()[t]
			var c := style.colors()
			c["skin"] = VPlayer.SKINS[(i * 3 + t) % VPlayer.SKINS.size()]
			c["hair"] = VPlayer.HAIRS[(i + t * 2) % VPlayer.HAIRS.size()]
			var f := _seated(c, Vector3(sx * (4.4 + i * 0.7), 0, 9.05), 0.0)
			f.set_number(20 + i + t * 10, style.number)
			bench[t].append(f)


func _seated(colors: Dictionary, pos: Vector3, rot_y: float, official := false, seat := 0.5) -> HumanFigure:
	var f := HumanFigure.new()
	add_child(f)
	f.hips_height = seat
	f.build(colors, false, posmod(int(pos.x * 10.0), HumanFigure.HAIR_STYLES), official)
	f.position = pos
	f.rotation.y = rot_y
	f.pose(_sit_pose(false))
	return f


## Vier Linienrichter an den Ecken (FIVB), jeder mit Fahne, Blick schraeg aufs Feld.
func _line_judges() -> void:
	var i := 0
	for c in [Vector3(-10.4, 0, -5.9), Vector3(10.4, 0, 5.9), Vector3(-10.4, 0, 5.9), Vector3(10.4, 0, -5.9)]:
		var f := HumanFigure.new()
		add_child(f)
		f.build(OFFICIAL.merged({"skin": VPlayer.SKINS[(i * 2 + 1) % VPlayer.SKINS.size()],
			"hair": VPlayer.HAIRS[(i * 3) % VPlayer.HAIRS.size()]}), false, i, true, 0.97 + 0.02 * i)
		f.position = c
		# Blick zur Feldmitte (Figur schaut lokal nach -Z)
		f.rotation.y = atan2(c.x, c.z)
		var flag: Node3D = FLAG.instantiate()
		f.j["wr_r"].add_child(flag)
		flag.position = Vector3(0, -0.14, -0.02)
		flag.rotation = Vector3(PI, 0, 0)  # Stiel liegt in der Hand, Tuch zeigt nach unten/aussen
		f.pose(_judge_pose(""))
		line_judges.append([f, c])
		i += 1


func _judge_pose(sig: String) -> Dictionary:
	var p := {"chest": Vector3(-0.03, 0, 0), "head": Vector3(0.05, 0, 0),
		"sh_l": Vector3(0.1, 0, -0.06), "sh_r": Vector3(0.25, 0, 0.06), "el_l": Vector3(0.2, 0, 0), "el_r": Vector3(0.5, 0, 0)}
	match sig:
		"in":  # Fahne nach unten auf den Boden zeigen
			p["sh_r"] = Vector3(0.6, 0, 0.15)
			p["el_r"] = Vector3(0.0, 0, 0)
			p["chest"] = Vector3(-0.15, 0, 0)
		"out":  # Fahne senkrecht nach oben
			p["sh_r"] = Vector3(2.95, 0, 0.1)
			p["el_r"] = Vector3(0.0, 0, 0)
	return p


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
	# Linienrichter: nur der dem Ball naechste zeigt "in" oder "aus"
	var near := -1
	if _ref_pose in ["in", "out"]:
		var best := INF
		for k in line_judges.size():
			var d := (line_judges[k][1] as Vector3).distance_to(Vector3(ball_pos.x, 0, ball_pos.z))
			if d < best:
				best = d
				near = k
	for k in line_judges.size():
		var lj: HumanFigure = line_judges[k][0]
		lj.pose(_judge_pose(_ref_pose if k == near else ""), clampf(delta * 8.0, 0.0, 1.0))
	# Bank: ab und zu ein bisschen Bewegung
	for t in 2:
		for i in bench[t].size():
			var f: HumanFigure = bench[t][i]
			f.j["head"].rotation.y = sin(_time * 0.4 + i * 1.7 + t) * 0.35
