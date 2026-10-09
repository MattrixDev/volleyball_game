extends Control
## Einstellungsmenue (Esc / Start): Schwierigkeitsstufe und alle Regler fuer Zeitlupe,
## Annahme-Hilfe, Gegnerstaerke und Fehler. Das Spiel pausiert, solange es offen ist.

var cfg: GameSettings
var _preset_buttons := {}
var _sliders := {}
var _value_labels := {}
var _help: Label
var _first: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.12, 0.17, 0.97)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(820, 0)
	panel.add_child(box)

	box.add_child(_text("Einstellungen", 34))
	box.add_child(_text("Schwierigkeit: wähle eine Stufe oder stell die Regler selbst ein.", 18, Color(0.75, 0.78, 0.85)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for p in ["leicht", "normal", "profi"]:
		var b := Button.new()
		b.text = GameSettings.PRESET_TEXT[p]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 44)
		b.add_theme_font_size_override("font_size", 22)
		var on := StyleBoxFlat.new()
		on.bg_color = Color(0.2, 0.45, 0.9)
		on.set_corner_radius_all(6)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		b.pressed.connect(_on_preset.bind(p))
		b.focus_entered.connect(_show_help.bind("Stufe %s: setzt alle Regler auf passende Werte." % GameSettings.PRESET_TEXT[p]))
		row.add_child(b)
		_preset_buttons[p] = b
		if _first == null:
			_first = b
	box.add_child(row)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	for s in GameSettings.SLIDERS:
		var key: String = s[0]
		grid.add_child(_text(s[1], 20))
		var sl := HSlider.new()
		sl.min_value = s[2]
		sl.max_value = s[3]
		sl.step = s[4]
		sl.custom_minimum_size = Vector2(380, 30)
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.value_changed.connect(_on_slider.bind(key))
		sl.focus_entered.connect(_show_help.bind(s[6]))
		grid.add_child(sl)
		_sliders[key] = sl
		var vl := _text("", 20)
		vl.custom_minimum_size = Vector2(170, 0)
		grid.add_child(vl)
		_value_labels[key] = vl
	box.add_child(grid)

	_help = _text("", 18, Color(1.0, 0.85, 0.35))
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.custom_minimum_size = Vector2(0, 50)
	box.add_child(_help)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	var cont := Button.new()
	cont.text = "Weiter spielen"
	cont.custom_minimum_size = Vector2(220, 46)
	cont.add_theme_font_size_override("font_size", 22)
	cont.pressed.connect(close)
	cont.focus_entered.connect(_show_help.bind("Zurück ins Spiel (auch mit Esc / Start)."))
	row2.add_child(cont)
	var quit := Button.new()
	quit.text = "Spiel beenden"
	quit.custom_minimum_size = Vector2(220, 46)
	quit.add_theme_font_size_override("font_size", 22)
	quit.pressed.connect(func(): get_tree().quit())
	quit.focus_entered.connect(_show_help.bind("Beendet das Spiel. Deine Einstellungen bleiben gespeichert."))
	row2.add_child(quit)
	box.add_child(row2)
	box.add_child(_text("Steuerung im Menü: Steuerkreuz / linker Stick / Pfeiltasten, A / Enter wählt aus", 16, Color(0.6, 0.63, 0.7)))


func _text(t: String, size: int, col := Color(1, 1, 1)) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("menu"):
		if visible:
			close()
		else:
			open()


func open() -> void:
	visible = true
	get_tree().paused = true
	_refresh()
	_first.grab_focus()


func close() -> void:
	visible = false
	cfg.save()
	get_tree().paused = false


func _refresh() -> void:
	for s in GameSettings.SLIDERS:
		var key: String = s[0]
		_sliders[key].set_value_no_signal(cfg.get_v(key))
		_update_value_label(key, s)
	for p in _preset_buttons:
		_preset_buttons[p].set_pressed_no_signal(cfg.preset == p)


func _update_value_label(key: String, s: Array) -> void:
	var v := cfg.get_v(key)
	var txt := "%d %s" % [int(v), s[5]]
	if key.begins_with("slow_"):
		txt = "aus" if v <= 0.0 else "%d %% langsamer" % int(v)
	_value_labels[key].text = txt.strip_edges()


func _on_slider(v: float, key: String) -> void:
	cfg.set_value(key, v)
	_refresh()


func _on_preset(p: String) -> void:
	cfg.apply_preset(p)
	_refresh()


func _show_help(t: String) -> void:
	_help.text = t
