extends SceneTree
## Lauf-Test: zwei Spieler laufen (einer schnell, einer langsam) an der Kamera vorbei,
## Bilder an mehreren Zeitpunkten.  godot -s res://tools/run_test.gd -- ordner
var frames := 0
var pls := []
var cam: Camera3D

func _init() -> void:
	var root3 := Node3D.new()
	root.add_child(root3)
	root3.add_child(Arena.new())
	for i in 2:
		var pl := VPlayer.new()
		root3.add_child(pl)
		pl.setup(0, "OH", "A", 4 + i, Color(0.16, 0.38, 0.86))
		pl.position = Vector3(-3.0 - i * 1.6, 0, 4.0)
		pl._last_pos = pl.position
		pls.append(pl)
	cam = Camera3D.new()
	root3.add_child(cam)
	cam.fov = 40

func _process(_delta: float) -> bool:
	frames += 1
	var dt := 1.0 / 30.0
	for i in pls.size():
		var pl: VPlayer = pls[i]
		var v := 5.5 if i == 0 else 1.6
		pl.now = frames * dt
		pl.alert = true
		pl.position.z -= v * dt
		pl.look_target = pl.position + Vector3(0, 0, -5)
		pl._animate(dt)
	var p0: Vector3 = pls[0].position
	var c := p0 + Vector3(4.0, 1.3, 0.6)
	cam.transform = Transform3D(Basis.looking_at(p0 + Vector3(0, 0.9, 0.8) - c), c)
	if frames in [30, 32, 34, 36]:
		root.get_viewport().get_texture().get_image().save_png("%s/lauf_%d.png" % [OS.get_cmdline_user_args()[0], frames])
	return frames >= 36
