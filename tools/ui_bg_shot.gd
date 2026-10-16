extends SceneTree
## Hintergrundbilder fuer UI-Entwuerfe: Halle mit Spielern, ohne HUD, aus festen Kamerapositionen.
## godot -s res://tools/ui_bg_shot.gd -- --play --botplay ordner
var frames := 0
var cam: Camera3D
var out := ""
const PRESETS := [
	["eck", Vector3(-15.5, 6.5, 12.0), Vector3(0, 0.5, 0), 48.0],
	["grund", Vector3(-13.5, 1.7, 2.5), Vector3(0, 1.6, 0), 52.0],
	["seite", Vector3(-3.0, 1.9, 10.5), Vector3(0.5, 1.9, 0), 46.0],
	["spiel", Vector3.ZERO, Vector3.ZERO, 0.0],
	["grund2", Vector3(-12.0, 2.4, -3.0), Vector3(0, 1.4, 0.5), 50.0],
]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[args.size() - 1]
	root.add_child(load("res://scenes/main.tscn").instantiate())

func _hide_ui(n: Node) -> void:
	for c in n.get_children():
		if c is CanvasLayer:
			c.visible = false
		elif c is Control or c is Label3D:
			c.visible = false
		_hide_ui(c)

func _process(_d: float) -> bool:
	frames += 1
	if frames % 20 == 0: print("f", frames)
	if frames < 90:
		return false
	if cam == null:
		cam = Camera3D.new()
		root.add_child(cam)
		cam.make_current()
	_hide_ui(root)
	var i := (frames - 90) / 10
	if i >= PRESETS.size():
		return true
	var p: Array = PRESETS[i]
	if p[3] == 0.0:
		cam.clear_current(true)
	else:
		cam.make_current()
		cam.fov = p[3]
		cam.transform = Transform3D(Basis.looking_at(p[2] - p[1]), p[1])
	if (frames - 90) % 10 == 9:
		root.get_viewport().get_texture().get_image().save_png("%s/bg_%s.png" % [out, p[0]])
		print("saved ", p[0])
	return false
