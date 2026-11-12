extends SceneTree
## Nahaufnahme eines Ballkontakts aus drei Richtungen (Haende und Handgelenke pruefen):
## godot -s res://tools/contact_closeup.gd -- bild.png <spike|set|bump|block> [rel]
var frames := 0
var figs := []
var kind := "set"

func _init() -> void:
	pass


func _setup() -> void:
	var args := OS.get_cmdline_user_args()
	kind = args[1] if args.size() > 1 else "set"
	var rel_end := float(args[2]) if args.size() > 2 else 0.0
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
	sun.rotation_degrees = Vector3(-40, -20, 0)
	root3.add_child(sun)
	# drei Spieler: Blick nach links (Seite), zur Kamera (vorn), schraeg von hinten
	var dirs := [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0.7, 0, -0.7)]
	for i in 3:
		var x0 := -2.6 + i * 2.6
		var pl := VPlayer.new()
		root3.add_child(pl)
		pl.setup(0, "OH", "A", i + 1, Color(0.16, 0.38, 0.86))
		pl.position = Vector3(x0, 0, 0)
		pl._last_pos = pl.position
		pl.alert = true
		var d: Vector3 = dirs[i].normalized()
		var dt := 1.0 / 120.0
		var t_c := 0.75
		var steps := int((t_c + rel_end) / dt)
		var bp := Vector3.ZERO
		for s in steps:
			var t := s * dt
			pl.now = t
			pl.look_target = pl.position + d * 5.0
			match kind:
				"spike":
					pl.anim_kind = "attack"
					pl.anim_t = t_c
					pl.contact_on = true
					bp = pl.position + d * 0.3 + Vector3(0, 3.25, 0)
					pl.contact_pt = bp
					pl.contact_aim = pl.position + d * 6.0
					pl.net_x = pl.position.x + d.x * 1.0
					var air_t := t - 0.35
					pl.airborne = air_t > 0.0 and air_t < 0.8
					pl.jump_h = maxf(0.0, 3.96 * air_t - 4.905 * air_t * air_t) if pl.airborne else 0.0
				"bump", "set":
					pl.anim_kind = "pass" if kind == "bump" else "set"
					pl.anim_tech = "under" if kind == "bump" else "over"
					pl.anim_t = t_c
					pl.contact_on = true
					bp = pl.position + d * (0.38 if kind == "bump" else 0.15) + Vector3(0, 0.85 if kind == "bump" else 2.1, 0)
					pl.contact_pt = bp
					pl.contact_aim = pl.position + d * 5.0
				"block":
					pl.net_x = pl.position.x + d.x * 0.5
					pl.block_pose = t > 0.2
					var air_t := t - 0.3
					pl.airborne = air_t > 0.0 and air_t < 0.6
					pl.jump_h = maxf(0.0, 3.4 * air_t - 4.905 * air_t * air_t) if pl.airborne else 0.0
			# Blick ueber die Bewegung: Spieler schaut immer in Richtung d
			pl._yaw = atan2(-d.x, -d.z)
			pl._animate(dt)
		figs.append(pl.fig)
		if OS.get_environment("CC_DEBUG") != "":
			var wr: Node3D = pl.fig.j["wr_r"]
			var sh: Vector3 = pl.fig.j["sh_r"].global_position
			print("shoulder ", sh.snapped(Vector3.ONE * 0.01), " dist sh-ball ", snappedf(sh.distance_to(bp), 0.01), " jump ", snappedf(pl.jump_h, 0.01), " root ", snappedf(pl.fig.root_node.position.y, 0.01))
			var tgt := bp - Vector3(0, 0.07, 0)
			var res: float = pl.fig.ik_arm("r", tgt, 1.0, 60)
			print("ik60 residual ", snappedf(res, 0.01), " wr ", (pl.fig.j["wr_r"] as Node3D).global_position.snapped(Vector3.ONE * 0.01), " el ", (pl.fig.j["el_r"] as Node3D).rotation.snapped(Vector3.ONE * 0.01), " sh ", (pl.fig.j["sh_r"] as Node3D).rotation.snapped(Vector3.ONE * 0.01))
			print("finger ", (wr.global_basis.orthonormalized() * Vector3(0, -1, 0)).snapped(Vector3.ONE * 0.01), " palm ", (wr.global_basis.orthonormalized() * Vector3(-1, 0, 0)).snapped(Vector3.ONE * 0.01), " wr ", wr.global_position.snapped(Vector3.ONE * 0.01), " ball ", bp)
		if kind != "block":
			var bm := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = 0.105
			sp.height = 0.21
			bm.mesh = sp
			var bmat := StandardMaterial3D.new()
			bmat.albedo_color = Color(1.0, 0.9, 0.2)
			bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			bmat.albedo_color.a = 0.5
			bm.material_override = bmat
			bm.position = bp
			root3.add_child(bm)
	var cam := Camera3D.new()
	root3.add_child(cam)
	var hy := 2.9 if kind in ["spike", "block"] else (1.4 if kind == "set" else 1.0)
	if kind == "set":
		hy = 1.9
	var cp := Vector3(0.0, hy + 0.3, 5.2)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, hy, 0) - cp), cp)
	cam.fov = 45 if OS.get_environment("CC_FOV") == "" else float(OS.get_environment("CC_FOV"))
	if OS.get_environment("CC_Y") != "":
		var yy := float(OS.get_environment("CC_Y"))
		cam.transform = Transform3D(Basis.looking_at(Vector3(0, yy, 0) - Vector3(0, yy + 0.2, 5.2)), Vector3(0, yy + 0.2, 5.2))

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
