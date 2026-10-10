extends SceneTree
## Nahaufnahme der Spielerfigur von vorn, seitlich und hinten: godot -s res://tools/closeup.gd -- bild.png
var frames := 0
var pls := []

func _init() -> void:
	var root3 := Node3D.new()
	root.add_child(root3)
	var a := Arena.new()
	root3.add_child(a)
	var yaws := [0.0, PI / 2.0, PI, 0.0]
	for i in 4:
		var pl := VPlayer.new()
		root3.add_child(pl)
		pl.setup(i % 2, "OH", "A", 7 + i, Color(0.16, 0.38, 0.86) if i % 2 == 0 else Color(0.85, 0.2, 0.18))
		pl.position = Vector3(-9.8 + i * 1.2, 0, 2.0)
		pl._last_pos = pl.position
		pls.append([pl, yaws[i]])
	var cam := Camera3D.new()
	root3.add_child(cam)
	var cp := Vector3(-8.0, 1.4, 6.4)
	cam.transform = Transform3D(Basis.looking_at(Vector3(-8.0, 1.0, 2.0) - cp), cp)
	cam.fov = 40

func _process(_delta: float) -> bool:
	frames += 1
	for e in pls:
		var pl: VPlayer = e[0]
		pl.now = frames * 0.02
		pl.alert = e == pls[3]
		pl.look_target = pl.position + Vector3(0, 0, -5).rotated(Vector3.UP, e[1] + PI)
		pl._animate(0.02)
		pl._yaw = e[1]
		pl.fig.rotation.y = e[1]
	if frames == 60:
		root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		return true
	return false
