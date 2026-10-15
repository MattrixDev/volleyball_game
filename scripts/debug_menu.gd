extends Control
## Debug-Menue (heller Kachel-Stil): Uebungen starten und einstellen, Mein Verein abkuerzen
## (Muenzen, alle Karten, Aufgaben erledigen, Verein zuruecksetzen). Mit Controller (LB / RB
## wechselt die Seite, links / rechts aendert eine Einstellung, B geht zurueck), Tastatur oder Maus.

signal start(id: String)
signal closed
signal to_title

const TABS := ["Übungen", "Verein und Karten"]

var _tab := 0
var _in_game := false
var _tab_btn: Array = []
var _pages: Array = []
var _drill_btns: Array = []
var _opt_btns := {}  # Schluessel -> Button
var _msg: Label
var _club_info: Label
var _task_box: VBoxContainer
var _title_btn: Button
var _back_btn: Button
var _club_first: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_light_theme()
	var paper := ColorRect.new()
	paper.color = UiTheme.PAPER
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(paper)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 80)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)
	root.add_child(_header())
	root.add_child(_tabs())
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(stack)
	for f in [_drills_page, _club_page]:
		var p: Control = f.call()
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.add_child(p)
		_pages.append(p)
	root.add_child(_footer())
	# Mit dem Steuerkreuz: hoch / runter springt zwischen Einstellungen und Uebungen hin und her
	# (links / rechts aendert die Einstellung).
	var ob: Array = _opt_btns.values()
	(ob[0] as Button).focus_neighbor_top = (_drill_btns[-1] as Button).get_path()
	(ob[-1] as Button).focus_neighbor_bottom = (_drill_btns[0] as Button).get_path()
	visible = false


# ------------------------------------------------------------------ Bausteine

func _lab(t: String, size: int, color: Color = UiTheme.INK, font: Font = null) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", font if font else UiTheme.font_medium)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel(c: Color = Color.WHITE, r := 18, pad := 22) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiTheme.box(c, r)
	sb.set_content_margin_all(pad)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _button(t: String, cb: Callable, w := 0.0) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(w, 46)
	b.add_theme_font_override("font", UiTheme.font_semibold)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(cb)
	return b


func _glyph(t: String) -> Control:
	var p := _panel(UiTheme.INK, 10, 0)
	p.custom_minimum_size = Vector2(40, 30)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := _lab(t, 12, Color.WHITE, UiTheme.font_semibold)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


func _header() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(_lab("DEBUG-MODUS", 13, UiTheme.INK_MUTED, UiTheme.font_semibold))
	v.add_child(_lab("Alles testen", 30, UiTheme.INK, UiTheme.font_display))
	h.add_child(v)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	_title_btn = _button("Hauptmenü", func(): _leave(true), 170)
	_title_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_title_btn)
	_back_btn = _button("Zurück", func(): _leave(false), 170)
	_back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_back_btn)
	return h


func _tabs() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(_glyph("LB"))
	for i in TABS.size():
		var b := _button(TABS[i], _show_tab.bind(i), 210)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		h.add_child(b)
		_tab_btn.append(b)
	h.add_child(_glyph("RB"))
	return h


func _footer() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.custom_minimum_size = Vector2(0, 30)
	for g in [["A", "Auswählen"], ["◀ ▶", "Einstellung ändern"], ["B", "Zurück"]]:
		var gl := _glyph(g[0])
		gl.custom_minimum_size = Vector2(maxf(30, 14 * g[0].length() + 16), 30)
		h.add_child(gl)
		var l := _lab(g[1], 15, UiTheme.INK_MUTED)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(l)
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(14, 0)
		h.add_child(sp)
	_msg = _lab("", 16, UiTheme.INK, UiTheme.font_semibold)
	_msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_msg.clip_text = true
	h.add_child(_msg)
	return h


func _say(t: String) -> void:
	_msg.text = t


# ------------------------------------------------------------------ Uebungen

func _drills_page() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	var left := _panel()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.7
	h.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 14)
	left.add_child(lv)
	lv.add_child(_lab("Übung wählen", 22, UiTheme.INK, UiTheme.font_display))
	lv.add_child(_lab("Startet sofort und wiederholt sich ohne Punkte. Im Spiel: Y / T öffnet dieses Menü.", 15, UiTheme.INK_MUTED))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 12)
	g.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(g)
	for d in DebugMode.DRILLS:
		g.add_child(_drill_tile(d))

	var right := _panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right.add_child(rv)
	rv.add_child(_lab("Einstellungen", 22, UiTheme.INK, UiTheme.font_display))
	for o in DebugMode.OPTIONS:
		rv.add_child(_lab(o[1].to_upper(), 12, UiTheme.INK_MUTED, UiTheme.font_semibold))
		var key: String = o[0]
		var b := _button("", _cycle.bind(key, 1))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.gui_input.connect(func(ev: InputEvent):
			if ev.is_action_pressed("ui_left"):
				_cycle(key, -1)
				b.accept_event()
			elif ev.is_action_pressed("ui_right"):
				_cycle(key, 1)
				b.accept_event())
		rv.add_child(b)
		_opt_btns[key] = b
	rv.add_child(_lab("Teams: wie im Startmenü gewählt.", 13, UiTheme.INK_MUTED))
	_refresh_options()
	return h


func _drill_tile(d: Dictionary) -> Button:
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(150, 130)
	var sb := UiTheme.box(Color(0.965, 0.96, 0.945), 14)
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(func(): start.emit(d.id))
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	b.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	var t := _lab(d.title, 19, UiTheme.INK, UiTheme.font_semibold)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	var ds := _lab(d.desc, 14, UiTheme.INK_MUTED)
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(ds)
	_drill_btns.append(b)
	return b


func _cycle(key: String, step: int) -> void:
	DebugMode.cycle_option(key, step)
	_refresh_options()


func _refresh_options() -> void:
	for o in DebugMode.OPTIONS:
		var b: Button = _opt_btns.get(o[0])
		if b:
			b.text = "◀  %s  ▶" % DebugMode.option_text(o[0])


# ------------------------------------------------------------------ Verein und Karten

func _club_page() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	var left := _panel()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 12)
	left.add_child(lv)
	lv.add_child(_lab("Mein Verein", 22, UiTheme.INK, UiTheme.font_display))
	_club_info = _lab("", 16, UiTheme.INK)
	_club_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(_club_info)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	lv.add_child(g)
	var acts := [["+1.000 Münzen", "c1"], ["+10.000 Münzen", "c10"], ["+100.000 Münzen", "c100"], ["Münzen auf 0", "c0"],
		["Alle Karten bekommen", "cards"], ["Karten zurücksetzen", "cards_reset"],
		["Alle Aufgaben erledigen", "tasks"], ["Alle Aufgaben öffnen", "tasks_reset"],
		["Verein gründen", "found"], ["Verein löschen", "delete"]]
	for a in acts:
		var b := _button(a[0], _club_action.bind(a[1]))
		if _club_first == null:
			_club_first = b
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(b)
	lv.add_child(_lab("Karten kaufen geht wie immer im Kartenshop unter Mein Verein, mit den Münzen von hier.", 13, UiTheme.INK_MUTED))

	var right := _panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.4
	h.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	right.add_child(rv)
	rv.add_child(_lab("Aufgaben einzeln", 22, UiTheme.INK, UiTheme.font_display))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(sc)
	_task_box = VBoxContainer.new()
	_task_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_task_box.add_theme_constant_override("separation", 6)
	sc.add_child(_task_box)
	return h


func _club_action(key: String) -> void:
	match key:
		"c1", "c10", "c100":
			var n: int = {"c1": 1000, "c10": 10000, "c100": 100000}[key]
			DebugMode.club_add_coins(n)
			_done("%s Münzen dazu." % Club.fmt(n))
		"c0":
			DebugMode.club_set_coins(0)
			_done("Münzen auf 0 gesetzt.")
		"cards":
			DebugMode.club_all_cards()
			_done("Alle Karten sind jetzt in deiner Sammlung.")
		"cards_reset":
			DebugMode.club_reset_cards()
			_done("Nur noch Nachwuchs und Karten aus erledigten Aufgaben.")
		"tasks":
			DebugMode.club_complete_all()
			_done("Alle Aufgaben erledigt, ihre Karten sind da.")
		"tasks_reset":
			DebugMode.club_reopen_all()
			_done("Alle Aufgaben sind wieder offen (Siege auf 0).")
		"found":
			DebugMode.club_found()
			_done("Verein ist da.")
		"delete":
			DebugMode.club_delete()
			_done("Verein gelöscht. Mein Verein beginnt wieder mit der Gründung.")


func _toggle_task(cid: String) -> void:
	if Club.is_done(cid):
		DebugMode.club_reopen(cid)
		_done("Aufgabe wieder offen.")
	else:
		_done(DebugMode.club_complete(cid))


func _done(t: String) -> void:
	_say(t)
	_refresh_club()


func _refresh_club() -> void:
	if not Club.exists():
		_club_info.text = "Noch kein Verein gegründet."
	else:
		var done := 0
		for c in Club.challenges():
			if Club.is_done(c.id):
				done += 1
		_club_info.text = "%s  ·  %s Münzen\nKarten: %d von %d  ·  Aufgaben: %d von %d erledigt  ·  Siege: %d" % [
			Club.data.name, Club.fmt(int(Club.data.coins)), Club.data.owned.size(), Club.all_ids().size(),
			done, Club.challenges().size(), int(Club.data.get("wins", 0))]
	var had_focus := -1
	var kids := _task_box.get_children()
	for i in kids.size():
		var b := kids[i].get_child(1) as Button
		if b and b.has_focus():
			had_focus = i
		kids[i].queue_free()
	var row_i := 0
	for c in Club.challenges():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var pd := Club.card(c.card)
		var l := _lab("%s\nKarte: %s (%d)" % [c.text, pd.full_name(), pd.overall()], 14, UiTheme.INK)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var on := Club.is_done(c.id)
		var cid: String = c.id
		var b := _button("Wieder öffnen" if on else "Erledigen", _toggle_task.bind(cid), 170)
		row.add_child(b)
		_task_box.add_child(row)
		if row_i == had_focus:
			b.grab_focus.call_deferred()
		row_i += 1


# ------------------------------------------------------------------ Verhalten

func open(in_game: bool) -> void:
	_in_game = in_game
	visible = true
	_title_btn.visible = in_game
	_back_btn.text = "Weiter" if in_game else "Zurück"
	_say("")
	_refresh_options()
	_show_tab(_tab)


func _show_tab(i: int) -> void:
	_tab = i
	for k in _pages.size():
		_pages[k].visible = k == i
		(_tab_btn[k] as Button).button_pressed = k == i
	if i == 1:
		_refresh_club()
		_club_first.grab_focus.call_deferred()
	else:
		(_drill_btns[0] as Button).grab_focus.call_deferred()


func _leave(title: bool) -> void:
	visible = false
	if title:
		to_title.emit()
	else:
		closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_leave(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("serve_prev"):
		_show_tab(posmod(_tab - 1, TABS.size()))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("serve_next"):
		_show_tab(posmod(_tab + 1, TABS.size()))
		get_viewport().set_input_as_handled()
