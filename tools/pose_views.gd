extends SceneTree
## Pritschen/Aufschlag aus Front- und Seitenansicht zum Pruefen:
## godot -s res://tools/pose_views.gd -- bild.png [set|serve] [front|side]
var frames := 0
var figs := []

func _initialize() -> void:
	await process_frame
	_build()


func _build() -> void:
	var args := OS.get_cmdline_user_args()
	var kind: String = args[1] if args.size() > 1 else "set"
	var view: String = args[2] if args.size() > 2 else "front"
	var root3 := Node3D.new()
	root.add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.6, 0.7, 0.8)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.6
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	root3.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.9, 0.45, 0.2)
	floor_mi.material_override = fm
	root3.add_child(floor_mi)
	var rels := [-0.3, -0.12, -0.03, 0.08, 0.2]
	var n := rels.size()
	for i in n:
		var pl := VPlayer.new()
		root3.add_child(pl)
		pl.setup(0, "S", "A", i + 1, Color(0.16, 0.38, 0.86))
		var pos := Vector3(0, 0, -(i - 2) * 1.3) if view == "front" else Vector3((i - 2) * 1.3, 0, 0)
		pl.position = pos
		pl._last_pos = pos
		pl.alert = true
		var dt := 1.0 / 120.0
		var t_hit := 0.9
		var steps := int((t_hit + rels[i]) / dt)
		for s in steps:
			var t := s * dt
			pl.now = t
			if kind == "set":
				pl.anim_kind = "set"
				pl.anim_tech = "over"
				pl.anim_t = t_hit
				pl.contact_on = true
				pl.contact_pt = pos + Vector3(-0.15, 2.1, 0.0)
				pl.contact_aim = pos + Vector3(-5.0, 0.0, 0.0)
			pl.look_target = pos + Vector3(-5, 0, 0)
			pl._animate(dt)
		figs.append(pl.fig)
		var bm := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.105
		sp.height = 0.21
		bm.mesh = sp
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(1.0, 0.9, 0.2)
		bm.material_override = bmat
		bm.position = pos + Vector3(-0.15, 2.1, 0.0)
		root3.add_child(bm)
	var cam := Camera3D.new()
	root3.add_child(cam)
	var cp := Vector3(-6.0, 1.9, 0.0) if view == "front" else Vector3(0.0, 1.9, 6.0)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 1.7, 0) - cp), cp)
	cam.fov = 38

func _process(_delta: float) -> bool:
	frames += 1
	for f in figs:
		f._sync()
	if frames == 12:
		root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		return true
	return false
