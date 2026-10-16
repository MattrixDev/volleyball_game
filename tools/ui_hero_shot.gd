extends SceneTree
## Freigestellter Einzelspieler fuer UI-Entwuerfe (transparenter Hintergrund).
## godot -s res://tools/ui_hero_shot.gd -- pose team nummer camx camy camz bild.png
var frames := 0
var pl: VPlayer
var kind := ""
var ball: Node3D

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	kind = a[0]
	root.transparent_bg = true
	var root3 := Node3D.new()
	root.add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.9, 1.0)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root3.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -40, 0)
	key.light_color = Color(1.0, 0.95, 0.88)
	key.light_energy = 1.25
	root3.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_color = Color(0.8, 0.88, 1.0)
	rim.light_energy = 0.9
	root3.add_child(rim)
	pl = VPlayer.new()
	root3.add_child(pl)
	pl.setup(int(a[1]), "OH", "A", int(a[2]), Color(0.16, 0.38, 0.86))
	pl.position = Vector3.ZERO
	pl.look_target = Vector3(5, 0, 0)
	if kind.begins_with("spike"):
		ball = (load("res://assets/models/ball.glb") as PackedScene).instantiate()
		root3.add_child(ball)
	var cam := Camera3D.new()
	root3.add_child(cam)
	var cp := Vector3(float(a[3]), float(a[4]), float(a[5]))
	var look := Vector3(0, 1.55 if kind != "spike_hit" else 2.0, 0)
	cam.transform = Transform3D(Basis.looking_at(look - cp), cp)
	cam.fov = 26

func _process(_d: float) -> bool:
	frames += 1
	pl.now = 10.0
	pl.alert = true
	match kind:
		"spike_pre":
			pl.anim_kind = "attack"; pl.anim_t = 10.2; pl.airborne = true; pl.jump_h = 0.6
		"spike_hit":
			pl.anim_kind = "attack"; pl.anim_t = 9.97; pl.airborne = true; pl.jump_h = 0.6
		"block":
			pl.block_pose = true; pl.airborne = true; pl.jump_h = 0.5; pl.hand_shift = 0.3
		"celebrate":
			pl.celebrate_until = 20.0
		"ready":
			pass
		"set":
			pl.anim_kind = "set"; pl.anim_tech = "over"; pl.anim_t = 10.0
	pl.jump_v = 0.0
	pl.look_target = Vector3(5, 0, 0)
	pl._animate(0.05)
	if ball and frames > 2:
		var sk: Skeleton3D = pl.fig._skel
		var best := Vector3(0, -99, 0)
		for sd in ["r", "l"]:
			var b := sk.find_bone("md2_" + sd)
			var p := (sk.global_transform * sk.get_bone_global_pose(b)).origin
			if p.y > best.y:
				best = p
		ball.global_position = best + Vector3(0.14, 0.06, 0.0)
	if frames == 50:
		root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[6])
		print("saved")
		return true
	return false
