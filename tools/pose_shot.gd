extends SceneTree
## Testbild aller Posen: godot -s res://tools/pose_shot.gd -- bild.png
var frames := 0
var pls := []

func _init() -> void:
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
	var kinds := [["idle", ""], ["ready", ""], ["bump", "pass"], ["set", "set"], ["spike_pre", "attack"], ["spike_hit", "attack"], ["block", ""], ["dive", ""], ["approach", "attack"], ["celebrate", ""]]
	for i in kinds.size():
		var pl := VPlayer.new()
		root3.add_child(pl)
		pl.setup(0, "OH", "A", i + 1, Color(0.16, 0.38, 0.86))
		pl.position = Vector3(-6.5 + i * 1.45, 0, 0)
		pl.look_target = pl.position + Vector3(5, 0, 0)
		pls.append([pl, kinds[i][0]])
	var cam := Camera3D.new()
	root3.add_child(cam)
	var cp := Vector3(0.0, 1.6, 9.0) if OS.get_cmdline_user_args().size() < 2 else Vector3(9.0, 1.8, 3.0)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 1.1, 0) - cp), cp)
	cam.fov = 60

func _process(delta: float) -> bool:
	frames += 1
	for e in pls:
		var pl: VPlayer = e[0]
		pl.now = 10.0
		pl.alert = true
		match e[1]:
			"bump":
				pl.anim_kind = "pass"; pl.anim_t = 10.0
			"set":
				pl.anim_kind = "set"; pl.anim_tech = "over"; pl.anim_t = 10.0
			"spike_pre":
				pl.anim_kind = "attack"; pl.anim_t = 10.2; pl.airborne = true; pl.jump_h = 0.6; pl.jump_v = 0.0
			"spike_hit":
				pl.anim_kind = "attack"; pl.anim_t = 9.97; pl.airborne = true; pl.jump_h = 0.6; pl.jump_v = 0.0
			"block":
				pl.block_pose = true; pl.airborne = true; pl.jump_h = 0.5; pl.jump_v = 0.0; pl.hand_shift = 0.3
			"dive":
				pl.dive_timer = 0.35
			"approach":
				pl.anim_kind = "attack"; pl.anim_t = 10.5
			"celebrate":
				pl.celebrate_until = 20.0
			"idle":
				pl.alert = false
		pl.look_target = pl.position + Vector3(5, 0, 0)
		pl.jump_v = 0.0
		pl._animate(0.05)
	if frames == 40:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(OS.get_cmdline_user_args()[0])
		print("saved")
		return true
	return false
