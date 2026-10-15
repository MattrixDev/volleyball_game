extends Control
## Pausenmenue (Esc / Start): Schwierigkeit, Spielregeln, alle Regler in Gruppen und der Weg
## zurueck ins Hauptmenue. Das Spiel pausiert, solange es offen ist. Aus dem Startmenue
## heraus dient es als Einstellungsseite.

signal closed
signal to_title
## Seite Kamera: diese Ansicht soll im Spiel dahinter gezeigt werden ("" = keine Vorschau).
signal camera_preview(mode: String)
## Ein Regler wurde verstellt (fuer Tonproben).
signal setting_changed(key: String)

## Welche Regler in welcher Gruppe stehen (Seite "Spiel", linke und rechte Spalte).
const GROUPS := [
	["Zeitlupe", ["slow_serve", "slow_receive", "slow_set", "slow_attack", "slow_block"]],
	["Regeln", ["serve_time"]],
	["Hilfen und Gegner", ["receive_help", "input_lag", "stick_hold", "ai_defense", "ai_block", "faults"]],
]
const TABS := ["Spiel", "Ton", "Kamera"]

var cfg: GameSettings
var match_node = null
var from_title := false  # aus dem Startmenue geoeffnet
var _preset_buttons := {}
var _sliders := {}
var _value_labels := {}
var _help: Label
var _hint: Label
var _title: Label
var _score: Label
var _set_buttons := {}
var _libero_buttons := {}
var _replay_buttons := {}
var _cont: Button
var _title_btn: Button
var _shade: ColorRect
var _panel: PanelContainer
var _box: VBoxContainer
var _tab := 0
var _tab_btn: Array = []
var _pages: Array = []
var _adv_btn: Button
var _adv_box: Control
var _cam_group := 0
var _cam_btn: Array = []
var _cam_grids: Array = []
var _cam_reset: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_light_theme()
	visible = false
	_shade = ColorRect.new()
	_shade.color = Color(0.05, 0.06, 0.09, 0.55)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)

	_panel = PanelContainer.new()
	var sb := UiTheme.box(UiTheme.PAPER, 28)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 24
	sb.set_content_margin_all(26)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 14)
	_box.custom_minimum_size = Vector2(1360, 0)
	_panel.add_child(_box)
	var box := _box

	# Kopfzeile: Titel, Spielstand, Knoepfe
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	var tbox := VBoxContainer.new()
	tbox.add_theme_constant_override("separation", 0)
	_title = UiTheme.label("Pause", 38, UiTheme.INK)
	_title.add_theme_font_override("font", UiTheme.font_display)
	tbox.add_child(_title)
	_score = UiTheme.label("", 18, UiTheme.INK_MUTED)
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

	# Seitenwahl (LB / RB)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	tabs.add_child(_glyph("LB"))
	for i in TABS.size():
		var tb := Button.new()
		tb.text = TABS[i]
		tb.toggle_mode = true
		tb.focus_mode = Control.FOCUS_NONE
		tb.custom_minimum_size = Vector2(170, 44)
		tb.add_theme_font_size_override("font_size", 20)
		tb.pressed.connect(_show_tab.bind(i))
		tabs.add_child(tb)
		_tab_btn.append(tb)
	tabs.add_child(_glyph("RB"))
	box.add_child(tabs)

	_pages = [_game_page(), _sound_page(), _camera_page()]
	for pg in _pages:
		box.add_child(pg)

	_help = UiTheme.label("", 18, UiTheme.NAVY)
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.custom_minimum_size = Vector2(0, 48)
	box.add_child(_help)
	_hint = UiTheme.label("Steuerkreuz / linker Stick zum Wählen · A wählt aus · links/rechts verstellt Regler · LB / RB wechselt die Seite · B zurück", 15, UiTheme.INK_MUTED)
	box.add_child(_hint)
	_panel.resized.connect(_dock)


func _glyph(t: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.INK, 10))
	p.custom_minimum_size = Vector2(46, 32)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := UiTheme.label(t, 13, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## Seite Spiel: Schwierigkeit, Regeln, Zeitlupe, Hilfen und Gegner.
func _game_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	# Schwierigkeit und Spielregeln
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	page.add_child(top)
	var diff := UiTheme.card_light()
	diff.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(diff)
	var dbox := VBoxContainer.new()
	dbox.add_theme_constant_override("separation", 10)
	diff.add_child(dbox)
	dbox.add_child(UiTheme.heading_light("Schwierigkeit"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for p in ["leicht", "normal", "profi"]:
		var b := _toggle(GameSettings.PRESET_TEXT[p], 130, "Stufe %s: setzt alle Regler auf passende Werte. Ändern kannst du sie danach einzeln." % GameSettings.PRESET_TEXT[p])
		b.pressed.connect(_on_preset.bind(p))
		row.add_child(b)
		_preset_buttons[p] = b
	dbox.add_child(row)
	dbox.add_child(UiTheme.label("Wiederholung starker Punkte", 16, UiTheme.INK_MUTED))
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 10)
	for v in [true, false]:
		var b := _toggle("an" if v else "aus", 130, "Nach einem Ass, Blockpunkt, harten Angriff oder langen Ballwechsel kommt eine kurze Wiederholung in Zeitlupe (überspringen mit A / Leertaste).")
		b.pressed.connect(_on_replays.bind(v))
		rrow.add_child(b)
		_replay_buttons[v] = b
	dbox.add_child(rrow)

	var rules := UiTheme.card_light()
	rules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(rules)
	var rbox := VBoxContainer.new()
	rbox.add_theme_constant_override("separation", 10)
	rules.add_child(rbox)
	rbox.add_child(UiTheme.heading_light("Spiel (Länge gilt ab dem nächsten Spiel)"))
	var rule_row := HBoxContainer.new()
	rule_row.add_theme_constant_override("separation", 10)
	for n in [1, 2, 3]:
		var b := _toggle(["1 Satz", "Best of 3", "Best of 5"][n - 1], 150, "Wie viele Sätze ein Team gewinnen muss (1, 2 oder 3). Sätze gehen bis 25 mit 2 Punkten Vorsprung, ein Entscheidungssatz bis 15 mit Seitenwechsel bei 8.")
		b.pressed.connect(_on_sets.bind(n))
		rule_row.add_child(b)
		_set_buttons[n] = b
	rbox.add_child(rule_row)
	rbox.add_child(UiTheme.label("Libero-Wechsel", 16, UiTheme.INK_MUTED))
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
	page.add_child(cols)
	for c in 2:
		var cardc := UiTheme.card_light()
		cardc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(cardc)
		var cbox := VBoxContainer.new()
		cbox.add_theme_constant_override("separation", 6)
		cardc.add_child(cbox)
		var groups: Array = [GROUPS[0], GROUPS[1]] if c == 0 else [GROUPS[2]]
		var first := true
		for g in groups:
			if not first:
				var sp := Control.new()
				sp.custom_minimum_size = Vector2(0, 12)
				cbox.add_child(sp)
			first = false
			cbox.add_child(UiTheme.heading_light(g[0]))
			var grid := GridContainer.new()
			grid.columns = 3
			grid.add_theme_constant_override("h_separation", 14)
			grid.add_theme_constant_override("v_separation", 4)
			for key in g[1]:
				_add_slider(grid, _slider_def(key))
			cbox.add_child(grid)
	return page


## Seite Ton: Gesamt-, Effekt- und Musiklautstaerke, dahinter "Erweitert" mit allen Einzelreglern.
func _sound_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	var card := UiTheme.card_light()
	page.add_child(card)
	var cbox := VBoxContainer.new()
	cbox.add_theme_constant_override("separation", 8)
	card.add_child(cbox)
	cbox.add_child(UiTheme.heading_light("Lautstärke"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	for key in GameSettings.AUDIO_SIMPLE:
		_add_slider(grid, _slider_def(key))
	cbox.add_child(grid)
	_adv_btn = _toggle("Erweitert: jedes Geräusch einzeln", 420, "Zeigt die Regler für Pfiff, Ball, Schlag und Aufschlag, Block, Schuhe und Publikum. Sie gelten im Verhältnis zur Effektlautstärke.")
	_adv_btn.pressed.connect(_on_advanced)
	cbox.add_child(_adv_btn)
	var adv := VBoxContainer.new()
	adv.add_theme_constant_override("separation", 6)
	var agrid := GridContainer.new()
	agrid.columns = 3
	agrid.add_theme_constant_override("h_separation", 14)
	agrid.add_theme_constant_override("v_separation", 4)
	for key in GameSettings.AUDIO_ADVANCED:
		_add_slider(agrid, _slider_def(key))
	adv.add_child(agrid)
	_adv_box = adv
	adv.visible = false
	cbox.add_child(adv)
	return page


## Seite Kamera: je Spielablauf Entfernung, Hoehe, Neigung und Sichtfeld, dazu Allgemeines.
## Das Spiel dahinter zeigt dabei die gewaehlte Ansicht.
func _camera_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	page.add_child(row)
	var names: Array = []
	for m in GameSettings.CAM_MODES:
		names.append(m[1])
	names.append("Allgemein")
	for i in names.size():
		var b := _toggle(names[i], 190, "Ansicht %s einstellen. Das Spiel dahinter zeigt sie dir." % names[i] if i < GameSettings.CAM_MODES.size() else "Für alle Ansichten: Ball folgen, Reaktion, Kamerawackeln, Heranrücken beim Wuchtschlag.")
		b.pressed.connect(_on_cam_group.bind(i))
		row.add_child(b)
		_cam_btn.append(b)
	_cam_reset = _button("Zurücksetzen", 210, "Setzt diese Ansicht auf die Standardwerte.")
	_cam_reset.pressed.connect(_on_cam_reset)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	row.add_child(_cam_reset)
	var card := UiTheme.card_light()
	page.add_child(card)
	var gbox := VBoxContainer.new()
	card.add_child(gbox)
	for i in names.size():
		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 6)
		if i < GameSettings.CAM_MODES.size():
			for p in GameSettings.CAM_PARAMS:
				_add_slider(grid, _slider_def("cam_%s_%s" % [GameSettings.CAM_MODES[i][0], p[0]]))
		else:
			for g in GameSettings.CAM_GLOBAL:
				_add_slider(grid, _slider_def(g[0]))
		gbox.add_child(grid)
		_cam_grids.append(grid)
	return page


func _slider_def(key: String) -> Array:
	for s in GameSettings.all_sliders():
		if s[0] == key:
			return s
	return []


func _add_slider(grid: GridContainer, s: Array) -> void:
	var key: String = s[0]
	var l := UiTheme.label(s[1], 18, UiTheme.INK)
	l.custom_minimum_size = Vector2(270, 0)
	l.clip_text = true
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
	var vl := UiTheme.label("", 18, UiTheme.INK_MUTED)
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


## B am Controller schliesst das Menue (Esc und Start macht _process, daher nur Controller hier).
## LB / RB wechseln die Seite.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventJoypadButton and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("serve_prev") or event.is_action_pressed("serve_next"):
		_show_tab(posmod(_tab + (1 if event.is_action_pressed("serve_next") else -1), TABS.size()))
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_PAGEUP or event.keycode == KEY_PAGEDOWN):
		_show_tab(posmod(_tab + (1 if event.keycode == KEY_PAGEDOWN else -1), TABS.size()))
		get_viewport().set_input_as_handled()


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
	_show_tab(0)


func close() -> void:
	visible = false
	camera_preview.emit("")
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
	for i in _cam_btn.size():
		_cam_btn[i].set_pressed_no_signal(i == _cam_group)
	for i in _cam_grids.size():
		_cam_grids[i].visible = i == _cam_group
	for i in _tab_btn.size():
		_tab_btn[i].set_pressed_no_signal(i == _tab)
	_adv_box.visible = _adv_btn.button_pressed


func _update_value_label(key: String, s: Array) -> void:
	var v := cfg.get_v(key)
	var txt := "%d %s" % [int(v), s[5]]
	if s[5] == "°":
		txt = "%+d °" % int(v) if int(v) != 0 else "0 °"
	if key.begins_with("slow_"):
		txt = "aus" if v <= 0.0 else "%d %% langsamer" % int(v)
	elif s[5] == "%" and v <= 0.0 and key in GameSettings.AUDIO:
		txt = "aus"
	_value_labels[key].text = txt.strip_edges()


func _on_slider(v: float, key: String) -> void:
	cfg.set_value(key, v)
	_refresh()
	setting_changed.emit(key)


func _on_preset(p: String) -> void:
	cfg.apply_preset(p)
	_refresh()


func _show_help(t: String) -> void:
	_help.text = t


## Seite wechseln. Auf der Kameraseite sitzt das Menue unten und das Spiel dahinter bleibt sichtbar.
func _show_tab(i: int) -> void:
	_tab = i
	for k in _pages.size():
		_pages[k].visible = k == i
	_shade.color.a = 0.0 if i == 2 else 0.55
	_title.get_parent().visible = i != 2  # Kameraseite: Kopf schmal halten, mehr Spiel im Bild
	_refresh()
	camera_preview.emit(GameSettings.CAM_MODES[_cam_group][0] if i == 2 and _cam_group < GameSettings.CAM_MODES.size() else ("view" if i == 2 else ""))
	_panel.reset_size()
	_dock.call_deferred()
	_focus_first.call_deferred()


func _focus_first() -> void:
	if not visible:
		return
	if _tab == 2:
		_cam_btn[_cam_group].grab_focus()
	elif _tab == 1:
		_sliders["master"].grab_focus()
	else:
		_cont.grab_focus()


func _dock() -> void:
	var vp := get_viewport_rect().size
	var sz := _panel.size
	_panel.position = Vector2((vp.x - sz.x) * 0.5, vp.y - sz.y - 18.0 if _tab == 2 else (vp.y - sz.y) * 0.5)


func _on_advanced() -> void:
	_refresh()
	_panel.reset_size()
	_dock.call_deferred()


func _on_cam_group(i: int) -> void:
	_cam_group = i
	_refresh()
	camera_preview.emit(GameSettings.CAM_MODES[i][0] if i < GameSettings.CAM_MODES.size() else "view")
	_panel.reset_size()
	_dock.call_deferred()


func _on_cam_reset() -> void:
	if _cam_group < GameSettings.CAM_MODES.size():
		cfg.reset_camera("cam_%s_" % GameSettings.CAM_MODES[_cam_group][0])
	else:
		for g in GameSettings.CAM_GLOBAL:
			cfg.values[g[0]] = GameSettings.CAM_DEFAULTS[g[0]]
	_refresh()
