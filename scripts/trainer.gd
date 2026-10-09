extends Control
## Trainerbank (T / Y): Auszeit nehmen, Libero ein- und auswechseln, Spieler wechseln.
## Nur vor dem Aufschlag und in der Auszeit moeglich. Das Spiel pausiert, solange sie offen ist.

var match_node
var _box: VBoxContainer
var _out_id := -1  # gewaehlter Spieler, der raus soll
var _msg := ""
var _msg_color := Color(1.0, 0.85, 0.35)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.12, 0.17, 0.97)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	_box.custom_minimum_size = Vector2(760, 0)
	panel.add_child(_box)


func _process(_delta: float) -> void:
	if not Input.is_action_just_pressed("trainer"):
		return
	if visible:
		close()
	elif not get_tree().paused:
		if match_node.can_use_trainer():
			open()
		elif match_node.phase == match_node.Phase.POINT_PAUSE and match_node.human_team >= 0:
			match_node.trainer_wanted = true
			match_node._notice("Trainerbank öffnet sich gleich vor dem Aufschlag")
		else:
			match_node._notice("Trainerbank: nur vor dem Aufschlag (Auszeit, Libero, Wechsel)")


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	if visible or not match_node.can_use_trainer():
		return
	_out_id = -1
	_msg = ""
	visible = true
	get_tree().paused = true
	_rebuild()


func close() -> void:
	visible = false
	await get_tree().process_frame
	if not visible:
		get_tree().paused = false


func _text(t: String, size: int, col := Color(1, 1, 1)) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(t: String, cb: Callable, enabled := true) -> Button:
	var b := Button.new()
	b.text = t
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 20)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(cb)
	return b


func _rebuild() -> void:
	for c in _box.get_children():
		c.queue_free()
	var t: int = match_node.human_team
	var r: TeamRoster = match_node.rosters[t]
	_box.add_child(_text("Trainerbank · %s" % match_node.TEAM_NAMES[t], 32))
	var first: Button = null

	# Auszeit
	var to := _button("Auszeit nehmen  (noch %d in diesem Satz)" % r.timeouts_left, _on_timeout, r.timeouts_left > 0 and match_node.phase == match_node.Phase.PRE_SERVE)
	_box.add_child(to)
	first = to

	# Libero
	_box.add_child(_text("Libero", 22, Color(0.75, 0.78, 0.85)))
	if r.libero_on >= 0:
		var slot := r.slot_of(r.libero_on)
		_box.add_child(_button("Libero %s raus  →  %s kommt zurück (Position %d)" % [r.m(r.libero_on).name, r.m(r.libero_for).name, slot], _on_libero_out))
	else:
		var any := false
		for slot in [6, 5]:
			if r.can_libero_enter(slot):
				any = true
				for lid in r.libero_ids():
					_box.add_child(_button("Libero %s (#%d) rein  →  für %s (Position %d)" % [r.m(lid).name, r.m(lid).number, r.m(r.lineup[slot - 1]).name, slot], _on_libero_in.bind(slot, lid)))
		if not any:
			_box.add_child(_text("Im Moment steht kein Spieler im Hinterfeld, den der Libero ersetzen kann (nicht auf Position 1).", 18, Color(0.6, 0.63, 0.7)))

	# Wechsel
	_box.add_child(_text("Wechsel  (%d von %d genutzt)" % [r.subs_used, TeamRoster.SUBS_PER_SET], 22, Color(0.75, 0.78, 0.85)))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	var left := VBoxContainer.new()
	var right := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_text("Auf dem Feld – wer soll raus?", 18, Color(0.6, 0.63, 0.7)))
	for slot in [1, 2, 3, 4, 5, 6]:
		var id: int = r.lineup[slot - 1]
		var mm: Dictionary = r.m(id)
		var label := "P%d  %s #%d %s" % [slot, TeamRoster.ROLE_TAG[mm.role], mm.number, mm.name]
		if id == _out_id:
			label = "▶ " + label
		left.add_child(_button(label, _on_pick_out.bind(id), mm.role != "L"))
	right.add_child(_text("Auswechselbank – wer soll rein?", 18, Color(0.6, 0.63, 0.7)))
	for id in r.bench():
		var mm: Dictionary = r.m(id)
		if mm.role == "L":
			continue
		var label := "%s #%d %s" % [TeamRoster.ROLE_TAG[mm.role], mm.number, mm.name]
		var enabled := _out_id >= 0 and r.sub_error(_out_id, id) == ""
		right.add_child(_button(label, _on_sub_in.bind(id), enabled))
	cols.add_child(left)
	cols.add_child(right)
	_box.add_child(cols)

	if _msg != "":
		_box.add_child(_text(_msg, 19, _msg_color))
	_box.add_child(_text("Ein Wechsel pro Spieler: Wer raus ist, darf nur für seinen Ersatz zurück. Zurück ins Spiel: T / Y oder B.", 16, Color(0.6, 0.63, 0.7)))
	_box.add_child(_button("Weiter spielen", close))
	first.call_deferred("grab_focus")


func _on_timeout() -> void:
	var err: String = match_node.call_timeout(match_node.human_team)
	if err != "":
		_msg = err
		_rebuild()
	else:
		_msg = "Auszeit läuft. Du kannst jetzt noch wechseln."
		_rebuild()


func _on_libero_in(slot: int, lid: int) -> void:
	_msg = match_node.libero_enter(match_node.human_team, slot, lid)
	_msg_color = Color(1.0, 0.5, 0.4)
	if _msg == "":
		_msg = "Libero ist im Spiel."
		_msg_color = Color(0.5, 1.0, 0.6)
	_rebuild()


func _on_libero_out() -> void:
	_msg = match_node.libero_leave(match_node.human_team)
	_msg_color = Color(1.0, 0.5, 0.4)
	if _msg == "":
		_msg = "Libero ist raus."
		_msg_color = Color(0.5, 1.0, 0.6)
	_rebuild()


func _on_pick_out(id: int) -> void:
	_out_id = id
	_msg = ""
	_rebuild()


func _on_sub_in(id: int) -> void:
	var err: String = match_node.substitute(match_node.human_team, _out_id, id)
	if err != "":
		_msg = err
		_msg_color = Color(1.0, 0.5, 0.4)
	else:
		_msg = "Wechsel erledigt."
		_msg_color = Color(0.5, 1.0, 0.6)
		_out_id = -1
	_rebuild()
