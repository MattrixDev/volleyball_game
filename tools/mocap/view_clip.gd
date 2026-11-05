extends SceneTree
## Labor: einen Mocap-Clip auf der Spielfigur als Bilder ausgeben (Seite und vorn).
## godot --rendering-driver opengl3 --script res://tools/mocap/view_clip.gd -- <clips.json> <name> <ordner> [schritt]
var fig: HumanFigure
var cam: Camera3D
var clip: Dictionary
var frames: Array
var out := ""
var step := 6
var i := 0
var side := true


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	clip = (JSON.parse_string(FileAccess.open(a[0], FileAccess.READ).get_as_text()) as Dictionary)[a[1]]
	frames = clip.frames
	out = a[2]
	if a.size() > 3:
		step = int(a[3])
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.85, 0.87, 0.9)
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	root.add_child(env)
	var l := DirectionalLight3D.new()
	l.rotation = Vector3(-0.8, 0.6, 0)
	root.add_child(l)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	fl.mesh = pm
	root.add_child(fl)
	fig = HumanFigure.new()
	root.add_child(fig)
	fig.build({})
	cam = Camera3D.new()
	root.add_child(cam)
	cam.fov = 40


var pending := ""
var low := 0.0


func _process(_d: float) -> bool:
	if pending != "":
		root.get_viewport().get_texture().get_image().save_jpg(pending)
		pending = ""
	if i >= frames.size():
		return true
	var fr: Dictionary = frames[i]
	for n in HumanFigure.JOINTS:
		var q: Array = fr[n]
		(fig.j[n] as Node3D).quaternion = Quaternion(q[0], q[1], q[2], q[3]).normalized()
	fig.root_node.position.y = fig.hips_height
	fig._sync()
	fig.root_node.position.y -= fig.lowest_point(true)
	fig._sync()
	fig._process(0.0)
	var c := Vector3(0, 0.9, 0)
	cam.position = c + (Vector3(3.6, 0.3, 0) if side else Vector3(0.3, 0.3, -3.6))
	cam.look_at(c)
	pending = "%s/%s_%04d.jpg" % [out, "s" if side else "f", i]
	if side:
		side = false
	else:
		side = true
		i += step
	return false
