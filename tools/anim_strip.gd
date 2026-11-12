extends SceneTree
## Bildfolge einer Bewegung zum Pruefen: godot -s res://tools/anim_strip.gd -- bild.png [spike|run|shuffle|dive|land]
var frames := 0
var figs := []

func _init() -> void:
	pass


func _setup() -> void:
	var args := OS.get_cmdline_user_args()
	var kind: String = args[1] if args.size() > 1 else "spike"
	var root3 := Node3D.new()
	root.add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.6, 0.7, 0.8)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.5
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	root3.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 6)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.9, 0.45, 0.2)
	floor_mi.material_override = fm
	root3.add_child(floor_mi)
	var n := 9
	for i in n:
		var pl := VPlayer.new()
		root3.add_child(pl)
		pl.setup(0, "OH", "A", i + 1, Color(0.16, 0.38, 0.86))
		var x0 := -7.2 + i * 1.8
		pl.position = Vector3(x0, 0, 0)
		pl._last_pos = pl.position
		figs.append(pl.fig)
		pl.alert = true
		var dt := 1.0 / 120.0
		var steps := 30 + i * 9
		for s in steps:
			var t := s * dt
			pl.now = t
			match kind:
				"spike":
					pl.anim_kind = "attack"
					pl.anim_t = 0.75
					pl.contact_on = true
					pl.contact_pt = Vector3(x0 - 0.3, 3.2, 0.0)
					pl.contact_aim = Vector3(x0 - 6.0, 0.0, 0.0)
					var air_t := t - 0.25
					pl.airborne = air_t > 0.0 and air_t < 0.8
					pl.jump_h = maxf(0.0, 3.96 * air_t - 4.905 * air_t * air_t) if pl.airborne else 0.0
				"bump", "set":
					pl.anim_kind = "pass" if kind == "bump" else "set"
					pl.anim_tech = "under" if kind == "bump" else "over"
					pl.anim_t = 0.7
					pl.contact_on = true
					pl.contact_pt = Vector3(x0 - (0.38 if kind == "bump" else 0.15), 0.85 if kind == "bump" else 2.3, 0.0)
					pl.contact_aim = Vector3(x0 - 5.0, 0.0, 0.0)
				"block":
					pl.net_x = x0 + 0.5
					pl.block_pose = t > 0.2
					var air_t := t - 0.3
					pl.airborne = air_t > 0.0 and air_t < 0.6
					pl.jump_h = maxf(0.0, 3.4 * air_t - 4.905 * air_t * air_t) if pl.airborne else 0.0
				"run":
					pl.position.x -= 5.0 * dt
				"shuffle":
					pl.position.z += 3.5 * dt
				"dive":
					if s == 20: pl.dive()
					if pl.dive_timer > 0.0: pl.dive_timer -= dt
				"land":
					var air_t := t
					pl.airborne = air_t < 0.4
					pl.jump_h = maxf(0.0, 0.8 - 4.905 * (air_t) * (air_t) * 1.0) if pl.airborne else 0.0
			pl.look_target = pl.position + Vector3(-5, 0, 0)
			pl._animate(dt)
		pl.position = Vector3(x0, 0, 0)
		pl._last_pos = pl.position
		figs.append(pl.fig)
	if kind in ["spike", "bump", "set"]:
		for i in n:
			var bm := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = 0.105
			sp.height = 0.21
			bm.mesh = sp
			var bmat := StandardMaterial3D.new()
			bmat.albedo_color = Color(1.0, 0.9, 0.2)
			bm.material_override = bmat
			var x0b := -7.2 + i * 1.8
			var by := 3.2 if kind == "spike" else (0.85 if kind == "bump" else 2.3)
			var bx := x0b - (0.3 if kind == "spike" else (0.38 if kind == "bump" else 0.15))
			bm.position = Vector3(bx, by, 0.0)
			root3.add_child(bm)
	var cam := Camera3D.new()
	root3.add_child(cam)
	var cp := Vector3(0.0, 1.3, 9.0)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 1.2, 0) - cp), cp)
	cam.fov = 40

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 1:
		_setup()
		return false
	for f in figs:
		f._sync()
	if frames == 10:
		root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		return true
	return false
