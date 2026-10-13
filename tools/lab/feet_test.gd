extends SceneTree
## Fuss-Test ohne Bild: ein Spieler laeuft verschieden schnell geradeaus, seitlich und dreht sich
## auf der Stelle; misst, wie oft ein Fuss am Boden rutscht oder beide Fuesse in der Luft sind.
## godot --headless -s res://tools/lab/feet_test.gd [-- --trace]
var pl: VPlayer
var t := 0
var stats := {}
var prev := {}
var trace := false
const DT := 1.0 / 120.0
## Abschnitte: [Dauer s, Geschwindigkeit m/s, Laufrichtung relativ zum Blick (Grad), Drehung Grad/s]
const PHASES := [[1.0, 0.0, 0, 0], [2.0, 1.0, 0, 0], [2.0, 2.5, 0, 0], [2.0, 5.5, 0, 0], [1.0, 0.0, 0, 0],
	[2.0, 2.0, 90, 0], [2.0, 1.2, 180, 0], [2.0, 0.0, 0, 120], [2.0, 3.0, 0, 60]]

func _initialize() -> void:
	trace = OS.get_cmdline_user_args().has("--trace")
	var r := Node3D.new()
	root.add_child(r)
	pl = VPlayer.new()
	r.add_child(pl)
	pl.setup(0, "OH", "A", 5, Color(0.2, 0.4, 0.9))


func _physics_process(_d: float) -> bool:
	t += 1
	if t < 3:
		return false
	var tt := (t - 3) * DT
	var acc := 0.0
	var ph: Array = []
	var pi := 0
	for i in PHASES.size():
		acc += PHASES[i][0]
		if tt < acc:
			ph = PHASES[i]
			pi = i
			break
	if ph.is_empty():
		for k in stats:
			var s: Dictionary = stats[k]
			print("%-28s Takte=%4d  rutscht=%5.1f%%  schwebt=%5.1f%%  Fuss weit weg (Lift)=%5.1f%%" % [k, s.n, 100.0 * s.slide / s.n, 100.0 * s.float / s.n, 100.0 * s.lift / s.n])
		return true
	var key := "v=%.1f dir=%d dreh=%d" % [ph[1], ph[2], ph[3]]
	var yaw0: float = pl._yaw
	var look := Vector3(-sin(yaw0), 0, -cos(yaw0)).rotated(Vector3.UP, deg_to_rad(ph[3]) * DT * 6.0)
	var mv := Vector3(-sin(yaw0), 0, -cos(yaw0)).rotated(Vector3.UP, deg_to_rad(ph[2]))
	pl.now = tt
	pl.alert = true
	pl.target = pl.position + mv * float(ph[1]) * DT * 3.0
	pl.run_speed = maxf(float(ph[1]), 0.01)
	pl.look_target = pl.position + look * 5.0
	pl.tick(DT)
	var s: Dictionary = stats.get(key, {"n": 0, "slide": 0, "float": 0, "lift": 0})
	s.n += 1
	var low := INF
	var line := ""
	for sd in ["l", "r"]:
		var an: Transform3D = pl.fig.j["an_" + sd].global_transform
		var c: Vector3 = an * Vector3(0, -0.097, -0.07)
		var y := minf((an * Vector3(0, -0.097, 0.085)).y, (an * Vector3(0, -0.097, -0.225)).y)
		low = minf(low, y)
		if prev.has(sd) and y < 0.025 and float(prev[sd + "y"]) < 0.025:
			var dv: Vector3 = c - (prev[sd] as Vector3)
			var v := Vector2(dv.x, dv.z).length() / DT
			if v > 0.9:
				s.slide += 1
				line += " %s rutscht %.1f" % [sd, v]
		prev[sd] = c
		prev[sd + "y"] = y
		var f: Dictionary = pl._feet.get(sd, {})
		line += " %s:%s w%.2f y%.3f" % [sd, "P" if f.get("on", false) else "-", float(f.get("w", 0.0)), y]
	if low > 0.06:
		s.float += 1
		line += " SCHWEBT %.3f" % low
	stats[key] = s
	if trace:
		print("%5d %s %s" % [t, key, line])
	return false
