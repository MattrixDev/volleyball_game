class_name AnimLab
extends Node
## Animations-Labor (nur zum Testen, wird mit --lab-... Schaltern aus main.gd gestartet).
##
## 1. Pruefen (--lab-audit=datei.json): misst in jedem Physik-Takt an allen Spielern, was bei einer
##    Animation schiefgehen kann (Fuss im Boden, Schweben, rutschende Fuesse, Knie oder Ellbogen
##    falsch herum, Arm durch den Koerper, Beine durcheinander, ruckartige Gelenke, Teleport,
##    Spieler ineinander, Koerper im Netz, Hand weit weg vom Ball beim Kontakt) und schreibt
##    jedes Ereignis mit Takt, Spieler, Bewegung und Staerke in eine Datei.
## 2. Filmen (--lab-shots=shots.json --lab-out=ordner): spielt dasselbe Match (gleicher --seed)
##    noch einmal und rendert nur die Zeitfenster aus shots.json: Spielkamera plus zwei feste
##    Nahkameras auf den Spieler (Seite, schraeg vorn), mit Skelett-Linien. Ausserhalb der
##    Fenster ist das Rendern aus, damit das Match schnell bis zur Stelle laeuft.
## tools/lab/lab.sh setzt beides zusammen und macht Bildbogen und Videos daraus.

var match_node
var main_cam: Camera3D

# --- Pruefen
var audit_path := ""
var _events := []  # fertige Ereignisse
var _open := {}  # "spieler|art" -> laufendes Ereignis
var _prev := {}  # Spieler -> Werte aus dem letzten Takt
var _contacts := []
var _tick0 := -1
var _trace_id := ""  # --lab-trace=A3:4440:4470 druckt Gelenke eines Spielers
var _trace_f0 := 0
var _trace_f1 := 0
var _trace_joint := "sh_r"

# --- Filmen
var shots := []
var out_dir := ""
var frame_step := 2
var _shot_i := -1
var _shot_frame := 0
var _vp := []  # Nahkameras: [SubViewport, Camera3D, Label, Richtung]
var _dbg: MeshInstance3D
var _dbg_mesh: ImmediateMesh
var _main_label: Label
var _end_tick := -1
const DBG_LAYER := 1 << 19

const T_CLIP := -0.035  # Sohle tiefer als 3,5 cm im Boden
const T_FLOAT := 0.06  # am Boden, aber Sohle 6 cm in der Luft
const T_SLIDE := 0.9  # m/s, Fuss steht am Boden und rutscht
const T_POP := 0.42  # rad pro Takt (120 Hz): Gelenk springt
const T_TELEPORT := 0.14  # m pro Takt
const T_HAND_BALL := 0.22  # m Abstand Hand/Unterarm zum Ball beim Kontakt


func _ready() -> void:
	process_physics_priority = 1000  # nach dem Match: Posen dieses Takts sind fertig
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lab-audit="):
			audit_path = a.get_slice("=", 1)
		elif a.begins_with("--lab-shots="):
			var txt := FileAccess.get_file_as_string(a.get_slice("=", 1))
			shots = JSON.parse_string(txt) if txt != "" else []
		elif a.begins_with("--lab-out="):
			out_dir = a.get_slice("=", 1)
		elif a.begins_with("--lab-step="):
			frame_step = maxi(1, int(a.get_slice("=", 1)))
		elif a.begins_with("--lab-trace="):
			var tr := a.get_slice("=", 1).split(":")
			_trace_id = tr[0]
			_trace_f0 = int(tr[1])
			_trace_f1 = int(tr[2])
			if tr.size() > 3:
				_trace_joint = tr[3]
		elif a.begins_with("--lab-end="):
			_end_tick = int(a.get_slice("=", 1))
	if match_node.has_signal("contact"):
		match_node.contact.connect(_on_contact)
	if not shots.is_empty():
		shots.sort_custom(func(a, b): return a.f0 < b.f0)
		_end_tick = maxi(_end_tick, int(shots[-1].f1) + 2)
		DirAccess.make_dir_recursive_absolute(out_dir)
		_make_cams()
		RenderingServer.render_loop_enabled = false
		RenderingServer.frame_post_draw.connect(_on_drawn)


# ================================================================ Pruefen

func _physics_process(_delta: float) -> void:
	var tick := Engine.get_physics_frames()
	if _end_tick > 0 and tick >= _end_tick:
		_finish()
		return
	if not shots.is_empty():
		_update_shot(tick)
	if audit_path == "":
		return
	var rally: bool = match_node.phase == match_node.Phase.RALLY
	var replay: bool = match_node.phase == match_node.Phase.REPLAY
	if replay:
		_prev.clear()
		_check_replay(tick)
		return
	_rep_prev.clear()
	var all := []
	for t in 2:
		all.append_array(match_node.players[t])
	for p in all:
		_check_player(p, tick, rally)
	# Spieler ineinander (nur im Ballwechsel, Huefte zu Huefte waagerecht)
	if rally:
		for i in all.size():
			for k in range(i + 1, all.size()):
				var a: Vector3 = all[i].fig.j["hips"].global_position
				var b: Vector3 = all[k].fig.j["hips"].global_position
				var d := Vector2(a.x - b.x, a.z - b.z).length()
				_flag("%s+%s" % [_pid(all[i]), _pid(all[k])], "overlap", tick, 0.45 - d, d < 0.45, all[i])


## Replay: springt ein Gelenk von einem Bild zum naechsten, zuckt es sichtbar (Zeitlupe ist langsamer
## als das Spiel, da reichen schon kleine Spruenge).
var _rep_prev := {}
func _check_replay(tick: int) -> void:
	for t in 2:
		for p in match_node.players[t]:
			var id := _pid(p)
			var f: HumanFigure = p.fig
			var cur := {}
			var worst := 0.0
			var wj := ""
			for n in HumanFigure.JOINTS:
				var q: Quaternion = (f.j[n] as Node3D).quaternion
				cur[n] = q
				if _rep_prev.has(id):
					var a: float = q.angle_to(_rep_prev[id][n])
					if a > worst:
						worst = a
						wj = n
			_rep_prev[id] = cur
			_flag(id, "replay_pop", tick, worst, worst > 0.25, p, 1, wj)


func _check_player(p, tick: int, rally: bool) -> void:
	var f: HumanFigure = p.fig
	var J := {}
	for n in HumanFigure.JOINTS:
		J[n] = f.j[n].global_transform
	var id := _pid(p)
	var ground: bool = not p.airborne and p.dive_timer <= 0.0
	var pv: Dictionary = _prev.get(p, {})
	var cur := {}
	# Sohlen (wie HumanFigure.lowest_point)
	var sole := {}
	var low := INF
	for sd in ["l", "r"]:
		var an: Transform3D = J["an_" + sd]
		var h: Vector3 = an * Vector3(0, -0.097, 0.085)
		var t: Vector3 = an * Vector3(0, -0.097, -0.225)
		sole[sd] = (h + t) * 0.5
		low = minf(low, minf(h.y, t.y))
		cur["sole_" + sd] = sole[sd]
		cur["soley_" + sd] = minf(h.y, t.y)
	_flag(id, "floor_clip", tick, -low, low < T_CLIP, p)
	# Stelzen: beim Gehen (nicht Sprinten, nicht Springen) hebt ein Fuss hoeher als ein normaler Schritt
	var high := maxf(cur["soley_l"], cur["soley_r"])
	_flag(id, "high_step", tick, high, ground and p.jump_h <= 0.0 and p._run_amt < 0.6 and high > 0.11 and p.anim_kind in ["", "serve_hold"], p, 3)
	# Schweben: am Boden beide Fuesse in der Luft. Beim schnellen Laufen gibt es echte Flugphasen.
	_flag(id, "float", tick, low, ground and low > T_FLOAT and p.jump_h <= 0.0 and p._run_amt < 0.5, p)
	# Rutschende Fuesse: Fuss war und ist am Boden und bewegt sich waagerecht
	for sd in ["l", "r"]:
		var key: String = "sole_" + sd
		var slide := 0.0
		var moved: float = ((pv["pos"] as Vector3) - p.global_position).length() if pv.has("pos") else 1.0
		if pv.has(key) and ground and moved < T_TELEPORT and float(pv["soley_" + sd]) < 0.025 and float(cur["soley_" + sd]) < 0.025:
			var dv: Vector3 = (sole[sd] as Vector3) - (pv[key] as Vector3)
			slide = Vector2(dv.x, dv.z).length() * Engine.physics_ticks_per_second
		_flag(id, "foot_slide_" + sd, tick, slide, slide > T_SLIDE, p, 6)
	# Gelenke springen von einem Takt zum naechsten
	var worst := 0.0
	var worst_j := ""
	for n in HumanFigure.JOINTS:
		var q: Quaternion = f.j[n].quaternion
		cur["q_" + n] = q
		if pv.has("q_" + n):
			var ang := (pv["q_" + n] as Quaternion).angle_to(q)
			if ang > worst:
				worst = ang
				worst_j = n
	_flag(id, "pop", tick, worst, worst > T_POP, p, 1, worst_j)
	var yaw: float = f.rotation.y
	cur["yaw"] = yaw
	if pv.has("yaw"):
		var dy := absf(angle_difference(float(pv["yaw"]), yaw))
		_flag(id, "yaw_pop", tick, dy, dy > 0.3, p)
	cur["pos"] = p.global_position
	if pv.has("pos") and rally:
		var dp: float = ((pv["pos"] as Vector3) - p.global_position).length()
		_flag(id, "teleport", tick, dp, dp > T_TELEPORT, p)
	# Knie und Ellbogen: Unterschenkel/Unterarm im Raum des Oberschenkels/Oberarms.
	# Knie beugt nach hinten (+z), Ellbogen nach vorn (-z); umgekehrt = ueberstreckt, x = seitlich geknickt.
	# Schwellen nach den Meshy-Clips (die selbst bis knapp darunter gehen). Ellbogen nur grob: seine
	# Drehung enthaelt auch die Unterarm-Drehung, seitlich ist da nicht eindeutig.
	for sd in ["l", "r"]:
		var dk: Vector3 = (f.j["kn_" + sd] as Node3D).quaternion * Vector3.DOWN
		_flag(id, "knee_backward_" + sd, tick, -dk.z, dk.z < -0.25, p, 2)
		_flag(id, "knee_sideways_" + sd, tick, absf(dk.x), absf(dk.x) > 0.6, p, 2)
		var de: Vector3 = (f.j["el_" + sd] as Node3D).quaternion * Vector3.DOWN
		_flag(id, "elbow_backward_" + sd, tick, de.z, de.z > 0.5, p, 2)
	# Arme durch den Rumpf: Rumpf als Kapsel Huefte -> obere Brust
	var t0: Vector3 = J["hips"].origin
	var t1: Vector3 = J["chest"] * Vector3(0, 0.34, 0)
	for sd in ["l", "r"]:
		var e: Vector3 = J["el_" + sd].origin
		var hnd: Vector3 = J["wr_" + sd] * Vector3(0, -0.08, 0)
		var dmin := minf(_seg_seg(e.lerp(hnd, 0.5), hnd, t0, t1), _seg_seg(e, e, t0, t1))
		_flag(id, "arm_in_body_" + sd, tick, 0.085 - dmin, dmin < 0.085, p, 2)
	# Unterarme ineinander, Unterschenkel ineinander
	var fa := _seg_seg(J["el_l"].origin, J["wr_l"].origin, J["el_r"].origin, J["wr_r"].origin)
	_flag(id, "arms_cross", tick, 0.045 - fa, fa < 0.045, p, 2)
	var sh := _seg_seg(J["kn_l"].origin, J["an_l"].origin, J["kn_r"].origin, J["an_r"].origin)
	var th := _seg_seg(J["hip_l"].origin.lerp(J["kn_l"].origin, 0.3), J["kn_l"].origin, J["hip_r"].origin.lerp(J["kn_r"].origin, 0.3), J["kn_r"].origin)
	_flag(id, "legs_cross", tick, 0.075 - minf(sh, th), minf(sh, th) < 0.075, p, 2)
	# Koerper im Netz: Teil unter der Netzkante auf der falschen Seite
	var nx: float = p.net_x
	var worst_net := 0.0
	for n in ["head", "chest", "wr_l", "wr_r", "el_l", "el_r", "kn_l", "kn_r"]:
		var pos: Vector3 = J[n].origin
		if pos.y < 2.38 and pos.y > 0.2 and absf(pos.z) < 4.6:
			var over: float = (pos.x - nx) * p.side  # > 0 = eigene Seite
			worst_net = maxf(worst_net, -over)
	_flag(id, "net_clip", tick, worst_net, worst_net > 0.04 and rally, p)
	# Hechtsprung, Landung: als Marke merken (zum gezielten Filmen mit tools/lab/contacts.py)
	cur["dive"] = p.dive_timer > 0.0
	cur["air"] = p.airborne
	if cur.dive and not pv.get("dive", false):
		_contacts.append({"tick": tick, "kind": "dive", "player": id, "anim": p.anim_kind, "tech": p.anim_tech, "dist": 0.0, "part": ""})
	if pv.get("air", false) and not cur.air:
		_contacts.append({"tick": tick, "kind": "land", "player": id, "anim": p.anim_kind, "tech": p.anim_tech, "dist": 0.0, "part": ""})
	_prev[p] = cur
	if _trace_id == id and tick >= _trace_f0 and tick <= _trace_f1:
		var ft: Dictionary = p._feet
		var tj := _trace_joint
		var bb: Basis = f.global_basis.orthonormalized()
		var shp: Vector3 = f.j["sh_r"].global_position
		print("   on=%s kind=%s/%s el-sh(local)=%s wr-sh=%s rel=%.3f" % [p.contact_on, p.anim_kind, p.anim_tech, (bb.inverse() * (f.j["el_r"].global_position - shp)).snapped(Vector3.ONE * 0.01), (bb.inverse() * (f.j["wr_r"].global_position - shp)).snapped(Vector3.ONE * 0.01), p.now - p.anim_t])
		for hs in ["l", "r"]:
			var wb: Basis = f.j["wr_" + hs].global_basis.orthonormalized()
			var sg := 1.0 if hs == "r" else -1.0
			print("   hand_%s wr=%s fing=%s flex=%s thumb=%s fa=%s" % [hs, (bb.inverse() * (f.j["wr_" + hs].global_position - shp)).snapped(Vector3.ONE * 0.01), (bb.inverse() * -wb.y).snapped(Vector3.ONE * 0.01), (bb.inverse() * (wb.x * sg)).snapped(Vector3.ONE * 0.01), (bb.inverse() * wb.z).snapped(Vector3.ONE * 0.01), f.finger_state().slice(0 if hs == "l" else 15, 6 if hs == "l" else 21)])
		if p.dbg_tg.has("l"):
			print("   tg_l-sh=%s" % (bb.inverse() * ((p.dbg_tg["l"] as Vector3) - shp)).snapped(Vector3.ONE * 0.01))
		if p.dbg_tg.has("r"):
			print("   tg_r-sh=%s" % (bb.inverse() * ((p.dbg_tg["r"] as Vector3) - shp)).snapped(Vector3.ONE * 0.01))
		print("T%d %s %s=%s anim=%s phys=%s ikw=%s miss=%s sole=%s run=%.2f v=%.2f feet=%s" % [tick, id, tj, f.j[tj].quaternion, f._q.get(tj), f._pq.get(tj), f._ik_last.get("arm_r"), p._feet_miss, [snappedf(cur["soley_l"], 0.001), snappedf(cur["soley_r"], 0.001), snappedf(p._sole_t.get("l", 0.0), 0.001), snappedf(p._sole_t.get("r", 0.0), 0.001)], p._run_amt, p._vel.length(), {"l": [ft.get("l", {}).get("on"), snappedf(ft.get("l", {}).get("w", 0), 0.01)], "r": [ft.get("r", {}).get("on"), snappedf(ft.get("r", {}).get("w", 0), 0.01)]}])


func _on_contact(kind: String, pos: Vector3, _strength: float) -> void:
	var p = match_node.last_toucher
	var tick := Engine.get_physics_frames()
	if kind == "block":
		# Kontakt am Block: der naechste Spieler am Netz (last_toucher ist noch der Angreifer)
		var best := INF
		for t in 2:
			for q in match_node.players[t]:
				var dq: float = q.fig.j["chest"].global_position.distance_to(pos)
				if dq < best:
					best = dq
					p = q
	if audit_path == "":
		print("LAB-C %d %s" % [tick, kind])  # zum Vergleich mit audit.json: gleiches Match?
	if p == null or audit_path == "" or match_node.phase == match_node.Phase.REPLAY:
		return
	if kind in ["floor", "net", "antenna", "bounce", "out"]:
		return
	var f: HumanFigure = p.fig
	var d := INF
	var part := ""
	for sd in ["l", "r"]:
		var hnd: Vector3 = f.j["wr_" + sd].global_transform * Vector3(0, -0.08, 0)
		var dh := hnd.distance_to(pos) - 0.105
		if dh < d:
			d = dh
			part = "hand_" + sd
		var df := _seg_point(f.j["el_" + sd].global_position, f.j["wr_" + sd].global_position, pos) - 0.105 - 0.04
		if df < d:
			d = df
			part = "forearm_" + sd
	var c := {"tick": tick, "kind": kind, "player": _pid(p), "anim": p.anim_kind, "tech": p.anim_tech, "dist": snappedf(d, 0.001), "part": part, "rel": snappedf(p.now - p.anim_t, 0.001), "pt": snappedf(pos.distance_to(p.contact_pt), 0.001)}
	_contacts.append(c)
	if d > T_HAND_BALL:
		_events.append({"type": "contact_far", "player": _pid(p), "team": p.team, "num": p.number, "f0": tick, "f1": tick, "peak_f": tick, "peak": snappedf(d, 0.001), "anim": p.anim_kind, "tech": p.anim_tech, "joint": part, "ctx": kind})


## Ein Ereignis beginnen, verlaengern oder abschliessen. min_len: so viele Takte am Stueck, sonst verworfen.
func _flag(id: String, type: String, tick: int, value: float, on: bool, p, min_len := 1, extra := "") -> void:
	var key := id + "|" + type
	if on:
		var e: Dictionary = _open.get(key, {})
		if e.is_empty():
			e = {"type": type, "player": id, "team": p.team, "num": p.number, "f0": tick, "f1": tick, "peak_f": tick, "peak": value, "anim": p.anim_kind, "tech": p.anim_tech, "joint": extra, "ctx": _ctx(p), "min_len": min_len}
			_open[key] = e
		e.f1 = tick
		if value > e.peak:
			e.peak = value
			e.peak_f = tick
			e.anim = p.anim_kind
			e.ctx = _ctx(p)
			if extra != "":
				e.joint = extra
	elif _open.has(key):
		var e: Dictionary = _open[key]
		_open.erase(key)
		if e.f1 - e.f0 + 1 >= e.min_len:
			e.erase("min_len")
			e.peak = snappedf(e.peak, 0.001)
			_events.append(e)


func _ctx(p) -> String:
	var s := []
	if p.airborne:
		s.append("air")
	if p.dive_timer > 0.0:
		s.append("dive")
	if p.block_pose:
		s.append("block")
	if p.prep != "":
		s.append("prep:" + p.prep)
	s.append("rel%.2f" % (p.now - p.anim_t))
	s.append("run%.2f" % p._run_amt)
	return " ".join(s)


func _pid(p) -> String:
	return "%s%d" % ["A" if p.team == 0 else "B", p.number]


func _finish() -> void:
	if audit_path != "":
		for key in _open.keys():
			_flag(key.get_slice("|", 0), key.get_slice("|", 1), Engine.get_physics_frames(), 0.0, false, null)
		var f := FileAccess.open(audit_path, FileAccess.WRITE)
		f.store_string(JSON.stringify({"ticks": Engine.get_physics_frames(), "events": _events, "contacts": _contacts}, " "))
		f.close()
		print("LAB: %d Ereignisse, %d Kontakte -> %s" % [_events.size(), _contacts.size(), audit_path])
	get_tree().quit()


# ================================================================ Filmen

func _make_cams() -> void:
	for dir in ["side", "front"]:
		var vp := SubViewport.new()
		vp.size = Vector2i(540, 540)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.world_3d = get_viewport().world_3d
		add_child(vp)
		var cam := Camera3D.new()
		cam.fov = 38.0
		cam.near = 2.2  # Spieler und Pfosten zwischen Kamera und Ziel werden weggeschnitten
		cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		vp.add_child(cam)
		var cl := CanvasLayer.new()
		vp.add_child(cl)
		var lb := Label.new()
		lb.position = Vector2(8, 6)
		lb.add_theme_font_size_override("font_size", 15)
		lb.add_theme_color_override("font_color", Color(1, 1, 0.6))
		lb.add_theme_color_override("font_outline_color", Color.BLACK)
		lb.add_theme_constant_override("outline_size", 4)
		cl.add_child(lb)
		_vp.append([vp, cam, lb, dir])
	if main_cam:
		main_cam.cull_mask &= ~DBG_LAYER
	# Skelett-Linien nur in den Nahkameras
	_dbg_mesh = ImmediateMesh.new()
	_dbg = MeshInstance3D.new()
	_dbg.mesh = _dbg_mesh
	_dbg.layers = DBG_LAYER
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	_dbg.material_override = m
	_dbg.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_dbg)
	var cl := CanvasLayer.new()
	add_child(cl)
	_main_label = Label.new()
	_main_label.position = Vector2(10, 40)
	_main_label.add_theme_font_size_override("font_size", 16)
	_main_label.add_theme_color_override("font_color", Color(1, 1, 0.6))
	_main_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_main_label.add_theme_constant_override("outline_size", 4)
	cl.add_child(_main_label)


func _shot_player(s: Dictionary):
	for p in match_node.players[int(s.team)]:
		if p.number == int(s.num):
			return p
	return null


func _update_shot(tick: int) -> void:
	# naechstes Fenster suchen
	var want := -1
	for i in shots.size():
		if tick >= int(shots[i].f0) and tick <= int(shots[i].f1):
			want = i
			break
	if want != _shot_i:
		_shot_i = want
		_shot_frame = 0
		if want >= 0:
			var p = _shot_player(shots[want])
			if p:
				# Kameras fest zur Blickrichtung am Anfang des Fensters (drehen nicht mit)
				var fwd: Vector3 = -p.fig.global_transform.basis.z
				fwd.y = 0.0
				fwd = fwd.normalized()
				shots[want]["_fwd"] = fwd
				shots[want]["_c"] = p.global_position
	if _shot_i < 0:
		return
	var s: Dictionary = shots[_shot_i]
	var pl = _shot_player(s)
	if pl == null:
		return
	var fwd: Vector3 = s["_fwd"]
	var rgt := fwd.cross(Vector3.UP)
	var c: Vector3 = (s["_c"] as Vector3).lerp(pl.global_position, 0.25)
	s["_c"] = c
	var hy: float = pl.fig.j["hips"].global_position.y
	var look := Vector3(c.x, maxf(1.0, hy + 0.15), c.z)
	for v in _vp:
		var cam: Camera3D = v[1]
		var off: Vector3 = rgt * 3.6 if v[3] == "side" else (fwd * 2.6 - rgt * 2.6)
		if s.get("cam", "") == "hands":
			# Nahaufnahme der Haende (Pritschen, Ballkontakt)
			look = (pl.fig.j["wr_l"].global_position + pl.fig.j["wr_r"].global_position) * 0.5
			var hf: Vector3 = -pl.fig.global_transform.basis.z
			hf.y = 0.0
			hf = hf.normalized()
			var hr := hf.cross(Vector3.UP)
			off = hr * 1.1 + hf * 0.3 if v[3] == "side" else hf * 1.15
			if v[3] == "side" and s.get("back", false):
				off = -hf * 0.85 - Vector3.UP * 0.3  # von hinten unten (ueber den Kopf zu den Haenden)
			cam.near = 0.3 if v[3] != "side" or not s.get("back", false) else 0.05
		cam.position = look + off + Vector3(0, 0.25, 0)
		cam.look_at(look)
		(v[2] as Label).text = "%s  %s  #%d  %s\nTakt %d  %s %s" % [s.get("label", ""), "AB"[int(s.team)], int(s.num), v[3], tick, pl.anim_kind, _ctx(pl)]
	_main_label.text = "%s  Takt %d" % [s.get("label", ""), tick]
	_draw_skel(pl)


func _draw_skel(p) -> void:
	_dbg_mesh.clear_surfaces()
	var f: HumanFigure = p.fig
	var bones := [["hips", "chest"], ["chest", "head"], ["chest", "sh_l"], ["sh_l", "el_l"], ["el_l", "wr_l"], ["chest", "sh_r"], ["sh_r", "el_r"], ["el_r", "wr_r"], ["hips", "hip_l"], ["hip_l", "kn_l"], ["kn_l", "an_l"], ["hips", "hip_r"], ["hip_r", "kn_r"], ["kn_r", "an_r"]]
	_dbg_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for b in bones:
		var col := Color(1, 0.3, 0.2) if b[1].ends_with("_l") else (Color(0.2, 0.8, 1) if b[1].ends_with("_r") else Color(1, 1, 0.3))
		_dbg_mesh.surface_set_color(col)
		_dbg_mesh.surface_add_vertex(f.j[b[0]].global_position)
		_dbg_mesh.surface_set_color(col)
		_dbg_mesh.surface_add_vertex(f.j[b[1]].global_position)
	# Finger (Daumen magenta, Zeigefinger gruen), nur mit --lab-fingers
	if f.has_fingers and OS.get_cmdline_user_args().has("--lab-fingers"):
		var sk: Skeleton3D = f._skel
		var tw := sk.global_transform
		for sd in ["l", "r"]:
			for fn in ["th", "ix"]:
				var col := Color(1, 0, 1) if fn == "th" else Color(0, 1, 0)
				var a := tw * sk.get_bone_global_pose(sk.find_bone(fn + "1_" + sd)).origin
				var bt := sk.get_bone_global_pose(sk.find_bone(fn + "2_" + sd))
				var b2 := tw * bt.origin
				var c2: Dictionary = f._fg[fn + "2_" + sd]
				var tip := tw * (bt * ((c2.dir as Vector3) * float(c2.len)))
				for seg in [[a, b2], [b2, tip]]:
					_dbg_mesh.surface_set_color(col)
					_dbg_mesh.surface_add_vertex(seg[0])
					_dbg_mesh.surface_set_color(col)
					_dbg_mesh.surface_add_vertex(seg[1])
	# Sohlen
	for sd in ["l", "r"]:
		var an: Transform3D = f.j["an_" + sd].global_transform
		_dbg_mesh.surface_set_color(Color(0.3, 1, 0.3))
		_dbg_mesh.surface_add_vertex(an * Vector3(0, -0.097, 0.085))
		_dbg_mesh.surface_set_color(Color(0.3, 1, 0.3))
		_dbg_mesh.surface_add_vertex(an * Vector3(0, -0.097, -0.225))
	_dbg_mesh.surface_end()


## Gerendert wird nur jedes frame_step-te Bild im Fenster (Software-Rendern ist langsam).
func _process(_delta: float) -> void:
	if shots.is_empty():
		return
	if _shot_i < 0:
		RenderingServer.render_loop_enabled = false
		return
	_shot_frame += 1
	RenderingServer.render_loop_enabled = _shot_frame % frame_step == 0


func _on_drawn() -> void:
	if _shot_i < 0 or _shot_frame < frame_step * 2:
		return  # das erste Bild nach dem Einschalten ist noch alt
	var base := "%s/s%02d_%04d" % [out_dir, _shot_i, _shot_frame]
	get_viewport().get_texture().get_image().save_jpg(base + "_main.jpg", 0.9)
	for v in _vp:
		(v[0] as SubViewport).get_texture().get_image().save_jpg(base + "_" + v[3] + ".jpg", 0.9)


## Abstand zweier Strecken (genaehert durch Abtasten, reicht fuer Gliedmassen).
static func _seg_seg(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3) -> float:
	var best := INF
	for i in 9:
		var pa := a0.lerp(a1, i / 8.0)
		best = minf(best, _seg_point(b0, b1, pa))
	for i in 9:
		var pb := b0.lerp(b1, i / 8.0)
		best = minf(best, _seg_point(a0, a1, pb))
	return best


static func _seg_point(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 1e-9 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return (a + ab * t).distance_to(p)
