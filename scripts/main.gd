extends Node3D
## Baut Halle, Licht, Kamera und Steuerung auf und startet das Match.

const MatchScript := preload("res://scripts/match.gd")
const HudScript := preload("res://scripts/hud.gd")

var camera: Camera3D
var match_node
var _shake := 0.0
var _cam_base := Vector3(-18.5, 9.5, 0.0)
var _cam_pos := Vector3(-18.5, 9.5, 0.0)
var _cam_look := Vector3(1.5, 1.0, 0.0)


func _ready() -> void:
	_setup_input()
	_build_hall()
	camera = Camera3D.new()
	camera.fov = 52.0
	add_child(camera)
	camera.position = _cam_base
	camera.look_at(Vector3(1.5, 1.0, 0.0))

	var hud := HudScript.new()
	add_child(hud)
	match_node = MatchScript.new()
	match_node.hud = hud
	match_node.big_hit.connect(_on_big_hit)
	add_child(match_node)
	var menu := preload("res://scripts/menu.gd").new()
	menu.cfg = match_node.cfg
	hud.add_child(menu)
	if OS.get_cmdline_user_args().has("--menu"):
		menu.call_deferred("open")

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_screenshot_later(a.get_slice("=", 1))


func _process(delta: float) -> void:
	# Kamera in Echtzeit bewegen, auch waehrend der Zeitlupe.
	var rd := delta / maxf(Engine.time_scale, 0.01)
	var bz: float = match_node.ball.position.z if match_node and match_node.ball else 0.0
	var want_pos := _cam_base + Vector3(0.0, 0.0, bz * 0.25)
	var want_look := Vector3(1.5, 1.0, bz * 0.2)
	var want_fov := 52.0
	var subj = match_node.cam_subject if match_node else null
	if subj != null:
		var s: float = subj.side
		var p: Vector3 = subj.position
		match match_node.cam_mode:
			"serve":
				# Hinter der Schulter des Aufschlaegers.
				want_pos = p + Vector3(s * 4.4, 3.3, 2.4)
				want_look = Vector3(-s * 4.0, 2.6, p.z * 0.4)
				want_fov = 55.0
			"attack":
				want_pos = Vector3(s * 5.2, 3.3, p.z * 0.75 + 0.6)
				want_look = Vector3(-s * 2.0, 2.4, p.z * 0.6)
				want_fov = 56.0
			"block":
				want_pos = Vector3(s * 5.6, 3.6, p.z * 0.7)
				want_look = Vector3(-s * 3.0, 2.2, p.z * 0.6)
				want_fov = 56.0
	var k := clampf(rd * 4.0, 0.0, 1.0)
	_cam_pos = _cam_pos.lerp(want_pos, k)
	_cam_look = _cam_look.lerp(want_look, k)
	camera.fov = lerpf(camera.fov, want_fov, k)
	var off := Vector3.ZERO
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - rd * 2.5)
		off = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.25
	camera.position = _cam_pos + off
	camera.look_at(_cam_look + off * 0.5)


func _on_big_hit(strength: float) -> void:
	_shake = maxf(_shake, strength)


## Testhilfe: --shot=bild.png@2,4.5 speichert Bilder nach 2 und 4,5 Sekunden.
func _screenshot_later(spec: String) -> void:
	var path := spec.get_slice("@", 0)
	var times := spec.get_slice("@", 1).split(",") if spec.contains("@") else PackedStringArray(["2"])
	var waited := 0.0
	for ts in times:
		var t := float(ts)
		await get_tree().create_timer(t - waited, true, false, true).timeout
		waited = t
		var img := get_viewport().get_texture().get_image()
		var out := path.get_basename() + "_" + ts + ".png"
		img.save_png(out)
		print("Screenshot gespeichert: ", out)
	if OS.get_cmdline_user_args().has("--quit-after-shot"):
		get_tree().quit()


# ---------------------------------------------------------------- Steuerung

func _setup_input() -> void:
	_action("move_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_action("move_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_action("move_up", [KEY_W, KEY_UP], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]])
	_action("move_down", [KEY_S, KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]])
	# Rechter Stick = Trefferpunkt am Ball (Tastatur: Maus oder I J K L)
	_action("aim_left", [KEY_J], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_action("aim_right", [KEY_L], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_action("aim_up", [KEY_I], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_action("aim_down", [KEY_K], [], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_action("bump", [KEY_SPACE, KEY_ENTER], [JOY_BUTTON_A])
	_action("overhand", [KEY_Q], [JOY_BUTTON_X])
	_action("hit", [KEY_E], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_action("serve_prev", [KEY_1], [JOY_BUTTON_LEFT_SHOULDER])
	_action("serve_next", [KEY_2], [JOY_BUTTON_RIGHT_SHOULDER])
	_action("toggle_assist", [KEY_F1], [JOY_BUTTON_BACK])
	_action("toggle_slowmo", [KEY_F2], [])
	_action("toggle_zoom", [KEY_F3], [])
	_action("menu", [KEY_ESCAPE], [JOY_BUTTON_START])


func _action(name: String, keys: Array, buttons: Array, axes: Array = []) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, 0.25)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(name, ev)
	for b in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		InputMap.action_add_event(name, jb)
	for a in axes:
		var jm := InputEventJoypadMotion.new()
		jm.axis = a[0]
		jm.axis_value = a[1]
		InputMap.action_add_event(name, jm)


# ---------------------------------------------------------------- Halle

func _mat(c: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _box(size: Vector3, pos: Vector3, c: Color, unshaded := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(c, unshaded)
	mi.position = pos
	add_child(mi)
	return mi


func _cyl(radius: float, height: float, pos: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = radius
	cy.bottom_radius = radius
	cy.height = height
	mi.mesh = cy
	mi.material_override = _mat(c)
	mi.position = pos
	add_child(mi)


func _build_hall() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.09, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60.0, -35.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)

	# Boden: Freizone und Spielfeld (18 x 9 m)
	_box(Vector3(34.0, 0.1, 24.0), Vector3(0, -0.05, 0), Color(0.16, 0.32, 0.5))
	_box(Vector3(18.0, 0.01, 9.0), Vector3(0, 0.003, 0), Color(0.86, 0.5, 0.24))
	var white := Color(0.97, 0.97, 0.97)
	var lw := 0.05
	for x in [-9.0, 9.0]:
		_box(Vector3(lw, 0.012, 9.0 + lw), Vector3(x, 0.006, 0), white, true)
	for z in [-4.5, 4.5]:
		_box(Vector3(18.0 + lw, 0.012, lw), Vector3(0, 0.006, z), white, true)
	for x in [-3.0, 0.0, 3.0]:
		_box(Vector3(lw, 0.012, 9.0), Vector3(x, 0.006, 0), white, true)

	# Netz (Maenner 2,43 m), Antennen, Pfosten
	_box(Vector3(0.02, 1.0, 9.8), Vector3(0, 1.93, 0), Color(0.05, 0.05, 0.05, 0.55))
	_box(Vector3(0.04, 0.07, 9.8), Vector3(0, 2.395, 0), white)
	for z in [-4.5, 4.5]:
		_cyl(0.012, 1.8, Vector3(0, 2.33, z), Color(0.9, 0.15, 0.15))
	for z in [-5.6, 5.6]:
		_cyl(0.05, 2.6, Vector3(0, 1.3, z), Color(0.6, 0.6, 0.65))

	# Hallenwaende und Tribuenen fuer etwas Atmosphaere
	var wall := Color(0.22, 0.24, 0.3)
	_box(Vector3(0.5, 8.0, 40.0), Vector3(22.0, 4.0, 0), wall)
	_box(Vector3(48.0, 8.0, 0.5), Vector3(0, 4.0, 16.0), wall)
	_box(Vector3(48.0, 8.0, 0.5), Vector3(0, 4.0, -16.0), wall)
	for i in 4:
		var h := 0.6 + i * 0.6
		_box(Vector3(30.0, h, 1.2), Vector3(0, h / 2.0, 13.0 + i * 1.2), Color(0.3, 0.32, 0.4))
		_box(Vector3(30.0, h, 1.2), Vector3(0, h / 2.0, -13.0 - i * 1.2), Color(0.3, 0.32, 0.4))
