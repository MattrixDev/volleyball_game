extends Node
## Test: Fluss messen (--flow=Sekunden). Pro Bild (Echtzeit) werden sichtbare Spieler-, Ball- und
## Kamerabewegungen auf Spruenge, harte Stopps und Zeitsprünge geprueft.
var m
var cam: Camera3D
var dur := 60.0
var t := 0.0
var prev := {}
var ev := {}
var phase_time := {}
var idle := [0.0, 0.0]  # [Spielerzeit im Ballwechsel stehend, gesamt]
var ts_changes := 0
var last_ts := 1.0
var ball_prev := Vector3.INF
var ball_v := Vector3.ZERO
var cam_prev := Vector3.INF
var cam_v := Vector3.ZERO
var log_lines := []
var starts := []
var last_mode := ""

func _ready() -> void:
	process_priority = 2000
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--flow="):
			dur = float(a.get_slice("=", 1))

func _e(k: String, info := "") -> void:
	ev[k] = ev.get(k, 0) + 1
	if info != "" and log_lines.size() < 400:
		log_lines.append("%.2f %s %s" % [m.clock, k, info])

func _process(delta: float) -> void:
	if m == null:
		m = get_parent().match_node
		cam = get_parent().camera
		m.slowmo_on = "--flow-slow" in OS.get_cmdline_user_args()
		return
	var rd := delta / maxf(Engine.time_scale, 0.01)
	t += rd
	var ph: String = m.Phase.keys()[m.phase]
	phase_time[ph] = phase_time.get(ph, 0.0) + rd
	if absf(Engine.time_scale - last_ts) > 0.001:
		ts_changes += 1
		if Engine.time_scale < 0.5 and last_ts >= 0.5:
			_e("zeit_stopp", "ts=%.2f" % Engine.time_scale)
	last_ts = Engine.time_scale
	# Ball (sichtbar)
	var bp: Vector3 = m.ball.get_global_transform_interpolated().origin
	if ball_prev != Vector3.INF and rd > 0.0:
		var v := (bp - ball_prev) / rd
		if (v - ball_v).length() > 60.0 and m.phase == m.Phase.RALLY:
			_e("ball_sprung", "dv=%.1f" % (v - ball_v).length())
		if v.length() > 45.0:
			_e("ball_teleport", "v=%.1f %s" % [v.length(), ph])
		ball_v = v
	ball_prev = bp
	# Kamera
	var cp: Vector3 = get_parent()._cam_pos
	if cam_prev != Vector3.INF and rd > 0.0:
		var v2 := (cp - cam_prev) / rd
		if (v2 - cam_v).length() / rd > 25.0:
			ev["kamera_ruck_" + m.cam_mode] = ev.get("kamera_ruck_" + m.cam_mode, 0) + 1
		if m.cam_mode != last_mode:
			_e("kamera_wechsel", "%s -> %s" % [last_mode, m.cam_mode])
			last_mode = m.cam_mode
		cam_v = v2
	cam_prev = cp
	# Spieler (sichtbarer Koerper: Huefte)
	for tm in 2:
		for pl in m.players[tm]:
			var hip: Vector3 = pl.fig.get_global_transform_interpolated().origin
			var yaw: float = pl.fig.rotation.y
			var key: int = pl.get_instance_id()
			if prev.has(key) and rd > 0.0:
				var pv: Array = prev[key]
				var v := (hip - (pv[0] as Vector3)) / rd
				var vf := Vector2(v.x, v.z)
				var af := (vf - (pv[1] as Vector2)).length() / rd
				if m.phase == m.Phase.RALLY or m.phase == m.Phase.TOSS:
					idle[1] += rd
					if vf.length() < 0.25:
						idle[0] += rd
					if af > 20.0:
						ev["spieler_ruck"] = ev.get("spieler_ruck", 0) + 1
					if af > 60.0:
						var why: String = ("dringend" if pl.urgent else "normal") + ("_luft" if pl.airborne else "") + ("_hecht" if pl.dive_timer > 0.0 else "") + ("_kontakt" if pl.contact_on else "")
						ev["ruck60_" + why] = ev.get("ruck60_" + why, 0) + 1
					if (pv[1] as Vector2).length() < 0.3 and vf.length() >= 0.3:
						starts.append(m.clock)
					if vf.length() > 9.5:
						_e("spieler_teleport", "%s#%d v=%.1f" % [pl.role, pl.number, vf.length()])
					var yr := absf(wrapf(yaw - float(pv[2]), -PI, PI)) / rd
					if yr > 12.0:
						_e("dreh_ruck", "%s#%d %.0f rad/s" % [pl.role, pl.number, yr])
					# harter Stopp: von Lauf auf Stand in einem Bild
					if (pv[1] as Vector2).length() > 3.0 and vf.length() < 0.6:
						_e("harter_stopp", "%s#%d" % [pl.role, pl.number])
				if vf.length() > 15.0 and m.phase != m.Phase.REPLAY:
					_e("versetzt_%s" % ph)
				prev[key] = [hip, vf, yaw]
			else:
				prev[key] = [hip, Vector2.ZERO, yaw]
	if t > dur:
		print("FLOW Phasenzeit: ", phase_time)
		print("FLOW Ereignisse: ", ev)
		print("FLOW Stillstand im Ballwechsel: %.0f %%" % (100.0 * idle[0] / maxf(idle[1], 0.01)))
		print("FLOW Tempowechsel-Bilder: ", ts_changes)
		# Gleichzeitige Starts: wie viele Spieler starten innerhalb von 0,05 s gemeinsam
		starts.sort()
		var groups := 0
		var big := 0
		var i := 0
		while i < starts.size():
			var k := i
			while k + 1 < starts.size() and starts[k + 1] - starts[i] < 0.05:
				k += 1
			groups += 1
			if k - i + 1 >= 5:
				big += 1
			i = k + 1
		print("FLOW Starts: %d, Gruppen: %d, davon >=5 Spieler gleichzeitig: %d" % [starts.size(), groups, big])
		var f := FileAccess.open("user://flow_log.txt", FileAccess.WRITE)
		for l in log_lines:
			f.store_line(l)
		get_tree().quit()
