extends Control
## Pausenmenue (Esc / Start): Schwierigkeit, Spielregeln, alle Regler in Gruppen und der Weg
## zurueck ins Hauptmenue. Das Spiel pausiert, solange es offen ist. Aus dem Startmenue
## heraus dient es als Einstellungsseite.

signal closed
signal to_title

## Welche Regler in welcher Gruppe stehen (linke und rechte Spalte).
const GROUPS := [
	["Zeitlupe", ["slow_serve", "slow_receive", "slow_set", "slow_attack", "slow_block"]],
	["Ton", ["whistle", "sfx", "crowd"]],
	["Hilfen und Gegner", ["receive_help", "stick_hold", "ai_defense", "ai_block", "faults"]],
	["Regeln", ["serve_time"]],
]

var cfg: GameSettings
var match_node = null
var from_title := false  # aus dem Startmenue geoeffnet
var _preset_buttons := {}
var _sliders := {}
var _value_labels := {}
var _help: Label
var _title: Label
var _score: Label
var _set_buttons := {}
var _libero_buttons := {}
var _replay_buttons := {}
var _cont: Button
var _title_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.06, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var panel := PanelContainer.new()
	var sb := UiTheme.box(UiTheme.BG, 16, Color(1, 1, 1, 0.06), 1)
	sb.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(1360, 0)
	panel.add_child(box)

	# Kopfzeile: Titel, Spielstand, Knoepfe
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	var tbox := VBoxContainer.new()
	tbox.add_theme_constant_override("separation", 0)
	_title = UiTheme.label("Pause", 38)
	tbox.add_child(_title)
	_score = UiTheme.label("", 18, UiTheme.MUTED)
	tbox.add_child(_score)
	tbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tbox)
	_cont = _button("Weiter spielen", 230, "Zurück ins Spiel (auch mit Esc / Start).")
	_cont.pressed.connect(close)
	head.add_child(_cont)
	_title_btn = _button("Hauptmenü", 190, "Beendet dieses Spiel und geht zurück ins Startmenü.")
	_title_btn.pressed.connect(_on_title)
	head.add_child(_title_btn)
	var quit := _button("Spiel beenden", 190, "Beendet das Spiel. Deine Einstellungen bleiben gespeichert.")
	quit.pressed.connect(func(): get_tree().quit())
	head.add_child(quit)
	box.add_child(head)

	# Schwierigkeit und Spielregeln
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	box.add_child(top)
	var diff := UiTheme.card()
	diff.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(diff)
	var dbox := VBoxContainer.new()
	dbox.add_theme_constant_override("separation", 10)
	diff.add_child(dbox)
	dbox.add_child(UiTheme.heading("Schwierigkeit"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for p in ["leicht", "normal", "profi"]:
		var b := _toggle(GameSettings.PRESET_TEXT[p], 130, "Stufe %s: setzt alle Regler auf passende Werte. Ändern kannst du sie danach einzeln." % GameSettings.PRESET_TEXT[p])
		b.pressed.connect(_on_preset.bind(p))
		row.add_child(b)
		_preset_buttons[p] = b
	dbox.add_child(row)
	dbox.add_child(UiTheme.label("Wiederholung starker Punkte", 16, UiTheme.MUTED))
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 10)
	for v in [true, false]:
		var b := _toggle("an" if v else "aus", 130, "Nach einem Ass, Blockpunkt, harten Angriff oder langen Ballwechsel kommt eine kurze Wiederholung in Zeitlupe (überspringen mit A / Leertaste).")
		b.pressed.connect(_on_replays.bind(v))
		rrow.add_child(b)
		_replay_buttons[v] = b
	dbox.add_child(rrow)

	var rules := UiTheme.card()
	rules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(rules)
	var rbox := VBoxContainer.new()
	rbox.add_theme_constant_override("separation", 10)
	rules.add_child(rbox)
	rbox.add_child(UiTheme.heading("Spiel (Länge gilt ab dem nächsten Spiel)"))
	var rule_row := HBoxContainer.new()
	rule_row.add_theme_constant_override("separation", 10)
	for n in [1, 2, 3]:
		var b := _toggle(["1 Satz", "Best of 3", "Best of 5"][n - 1], 150, "Wie viele Sätze ein Team gewinnen muss (1, 2 oder 3). Sätze gehen bis 25 mit 2 Punkten Vorsprung, ein Entscheidungssatz bis 15 mit Seitenwechsel bei 8.")
		b.pressed.connect(_on_sets.bind(n))
		rule_row.add_child(b)
		_set_buttons[n] = b
	rbox.add_child(rule_row)
	rbox.add_child(UiTheme.label("Libero-Wechsel", 16, UiTheme.MUTED))
	var lib_row := HBoxContainer.new()
	lib_row.add_theme_constant_override("separation", 10)
	for v in [false, true]:
		var b := _toggle("ich wechsle selbst" if not v else "automatisch", 220, "Selbst: Den Libero und alle Wechsel machst du über die Trainerbank (T / Y vor dem Aufschlag). Automatisch: Der Libero geht von allein für den Mittelblocker im Hinterfeld rein und raus.")
		b.pressed.connect(_on_libero.bind(v))
		lib_row.add_child(b)
		_libero_buttons[v] = b
	rbox.add_child(lib_row)

	# Regler in zwei Spalten
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	box.add_child(cols)
	for c in 2:
		var cardc := UiTheme.card()
		cardc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(cardc)
		var cbox := VBoxContainer.new()
		cbox.add_theme_constant_override("separation", 6)
		cardc.add_child(cbox)
		for g in [GROUPS[c * 2], GROUPS[c * 2 + 1]]:
			cbox.add_child(UiTheme.heading(g[0]))
			var grid := GridContainer.new()
			grid.columns = 3
			grid.add_theme_constant_override("h_separation", 14)
			grid.add_theme_constant_override("v_separation", 4)
			for key in g[1]:
				_add_slider(grid, _slider_def(key))
			cbox.add_child(grid)

	_help = UiTheme.label("", 18, UiTheme.ACCENT)
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.custom_minimum_size = Vector2(0, 48)
	box.add_child(_help)
	box.add_child(UiTheme.label("Steuerkreuz / linker Stick / Pfeiltasten zum Wählen, A / Enter wählt aus, links/rechts verstellt Regler", 15, UiTheme.MUTED))


func _slider_def(key: String) -> Array:
	for s in GameSettings.SLIDERS:
		if s[0] == key:
			return s
	return []


func _add_slider(grid: GridContainer, s: Array) -> void:
	var key: String = s[0]
	var l := UiTheme.label(s[1], 18)
	l.custom_minimum_size = Vector2(270, 0)
	grid.add_child(l)
	var sl := HSlider.new()
	sl.min_value = s[2]
	sl.max_value = s[3]
	sl.step = s[4]
	sl.custom_minimum_size = Vector2(250, 30)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.value_changed.connect(_on_slider.bind(key))
	sl.focus_entered.connect(_show_help.bind(s[6]))
	grid.add_child(sl)
	_sliders[key] = sl
	var vl := UiTheme.label("", 18, UiTheme.MUTED)
	vl.custom_minimum_size = Vector2(150, 0)
	grid.add_child(vl)
	_value_labels[key] = vl


func _button(t: String, w: int, help: String) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(w, 48)
	b.add_theme_font_size_override("font_size", 21)
	b.focus_entered.connect(_show_help.bind(help))
	return b


func _toggle(t: String, w: int, help: String) -> Button:
	var b := Button.new()
	b.text = t
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(w, 42)
	b.add_theme_font_size_override("font_size", 19)
	b.focus_entered.connect(_show_help.bind(help))
	return b


func _on_sets(n: int) -> void:
	cfg.sets_to_win = n
	_refresh()


func _on_libero(v: bool) -> void:
	cfg.libero_auto = v
	_refresh()


func _on_replays(v: bool) -> void:
	cfg.replays = v
	_refresh()


func _on_title() -> void:
	close()
	to_title.emit()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("menu"):
		if visible:
			close()
		elif not get_tree().paused and not from_title_blocked():
			open()


## Im Startmenue oeffnet Esc das Menue nicht (dort gibt es den Knopf "Einstellungen").
func from_title_blocked() -> bool:
	return match_node != null and match_node.attract


func open(title_mode := false) -> void:
	from_title = title_mode
	visible = true
	get_tree().paused = true
	_title.text = "Einstellungen" if from_title else "Pause"
	_cont.text = "Zurück" if from_title else "Weiter spielen"
	_title_btn.visible = not from_title
	_score.text = ""
	if match_node != null and not from_title:
		_score.text = "%s %d : %d %s   ·   Satz %d   ·   Sätze %d : %d" % [match_node.TEAM_NAMES[0], match_node.score[0],
			match_node.score[1], match_node.TEAM_NAMES[1], match_node.set_no, match_node.sets_won[0], match_node.sets_won[1]]
	_refresh()
	_cont.grab_focus()


func close() -> void:
	visible = false
	cfg.save()
	get_tree().paused = false
	closed.emit()


func _refresh() -> void:
	for key in _sliders:
		_sliders[key].set_value_no_signal(cfg.get_v(key))
		_update_value_label(key, _slider_def(key))
	for p in _preset_buttons:
		_preset_buttons[p].set_pressed_no_signal(cfg.preset == p)
	for n in _set_buttons:
		_set_buttons[n].set_pressed_no_signal(cfg.sets_to_win == n)
	for v in _libero_buttons:
		_libero_buttons[v].set_pressed_no_signal(cfg.libero_auto == v)
	for v in _replay_buttons:
		_replay_buttons[v].set_pressed_no_signal(cfg.replays == v)


func _update_value_label(key: String, s: Array) -> void:
	var v := cfg.get_v(key)
	var txt := "%d %s" % [int(v), s[5]]
	if key.begins_with("slow_"):
		txt = "aus" if v <= 0.0 else "%d %% langsamer" % int(v)
	elif s[5] == "%" and v <= 0.0 and key in GameSettings.AUDIO:
		txt = "aus"
	_value_labels[key].text = txt.strip_edges()


func _on_slider(v: float, key: String) -> void:
	cfg.set_value(key, v)
	_refresh()


func _on_preset(p: String) -> void:
	cfg.apply_preset(p)
	_refresh()


func _show_help(t: String) -> void:
	_help.text = t
