extends SceneTree
## Bildfolge einer Meshy-Animation aus player_clips.json:
## godot -s res://tools/clip_strip.gd -- bild.png <clip> [von bis]   (von/bis: Anteil 0..1)
var frames := 0
var figs := []

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var clip: String = args[1]
	var u0 := float(args[2]) if args.size() > 2 else 0.0
	var u1 := float(args[3]) if args.size() > 3 else 1.0
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
		pl.position = Vector3(-7.2 + i * 1.8, 0, 0)
		pl.fig.rotation.y = PI * 0.5
		var u := lerpf(u0, u1, float(i) / float(n - 1)) * 0.999
		pl.fig.pose(HumanFigure.clip_pose(clip, u, false))
		figs.append(pl)
	var cam := Camera3D.new()
	root3.add_child(cam)
	var cp := Vector3(0.0, 1.3, 9.0)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 1.2, 0) - cp), cp)
	cam.fov = 40

func _process(_delta: float) -> bool:
	frames += 1
	for pl in figs:
		pl.fig._sync()
		pl.fig.root_node.position.y -= pl.fig.lowest_point(true)
	if frames == 10:
		root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		return true
	return false
