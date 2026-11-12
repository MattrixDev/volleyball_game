extends SceneTree
## Netz-Test: Ball fliegt ins Netz, Bilder vor, waehrend und nach dem Ausbeulen.
## godot -s res://tools/net_test.gd -- ordner   (schreibt netz_00.png ... in den Ordner)
var frames := 0
var arena: Arena
var cam: Camera3D
var ball: MeshInstance3D
const SHOTS := [0, 3, 6, 10, 16, 30]
const HIT := 20

func _init() -> void:
	var root3 := Node3D.new()
	root.add_child(root3)
	arena = Arena.new()
	root3.add_child(arena)
	cam = Camera3D.new()
	root3.add_child(cam)
	var cp := Vector3(-6.5, 3.2, 5.5) if OS.get_cmdline_user_args().size() < 2 else Vector3(-2.2, 1.8, 2.2)  # "nah" = Nahaufnahme
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 1.8, 0.8) - cp), cp)
	cam.fov = 45
	var src: Node3D = load("res://assets/models/ball.glb").instantiate()
	ball = MeshInstance3D.new()
	ball.mesh = (src.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	ball.scale = Vector3.ONE * (0.14 / 0.105)
	root3.add_child(ball)

func _process(_delta: float) -> bool:
	frames += 1
	var f := frames - HIT
	# Ball kommt von links (x < 0) und prallt bei (0, 1.9, 1.0) ab
	ball.position = Vector3(-0.15 - absf(f) * 0.35, 1.9 - maxf(f, 0) * 0.05, 1.0)
	if f == 0:
		arena.net.hit(Vector3(0, 1.9, 1.0), 1.0, 1.0)
	if f in SHOTS:
		var dir := OS.get_cmdline_user_args()[0]
		root.get_viewport().get_texture().get_image().save_png("%s/netz_%02d.png" % [dir, f])
	return f >= SHOTS[-1]
