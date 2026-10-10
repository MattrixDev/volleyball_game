extends Control
## Startmenue: Spielen, Einstellungen, Steuerung, Beenden. Im Hintergrund laeuft ein
## Spiel KI gegen KI, damit die Halle schon lebt.

signal play
signal settings

var cfg: GameSettings
var _main: Control
var _controls: Control
var _play: Button
var _back: Button
var _sub: Label
var _time := 0.0
var _logo: Label
var _team_btn: Array = []  # [Button eigenes Team, Button Gegner]
var _pick := []  # gewaehlte Team-ids [eigenes, Gegner]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	# Links dunkel, nach rechts durchsichtig: das Hintergrundspiel bleibt sichtbar.
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.04, 0.08, 0.93))
	g.set_color(1, Color(0.03, 0.04, 0.08, 0.0))
	g.add_point(0.45, Color(0.03, 0.04, 0.08, 0.8))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 14)
	_main.anchor_top = 0.5
	_main.anchor_bottom = 0.5
	_main.offset_left = 110.0
	_main.offset_top = -300.0
	_main.offset_bottom = 300.0
	_main.offset_right = 700.0
	add_child(_main)

	_logo = UiTheme.label("VOLLEYBALL", 84, Color.WHITE)
	_logo.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.6))
	_logo.add_theme_constant_override("outline_size", 10)
	_main.add_child(_logo)
	var stripe := ColorRect.new()
	stripe.color = UiTheme.ACCENT
	stripe.custom_minimum_size = Vector2(260, 5)
	stripe.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_main.add_child(stripe)
	_main.add_child(UiTheme.label("Hallenvolleyball 6 gegen 6  ·  FIVB-Regeln", 22, UiTheme.MUTED))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	_main.add_child(gap)

	_play = _big("Spielen")
	_play.pressed.connect(_on_play)
	_main.add_child(_play)
	_sub = UiTheme.label("", 17, UiTheme.MUTED)
	_main.add_child(_sub)
	# Teamauswahl: A / Enter oder links / rechts wechselt das Team
	_pick = [Teams.home, Teams.away]
	for k in 2:
		var b := _big("")
		b.custom_minimum_size = Vector2(520, 50)
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(_cycle.bind(k, 1))
		b.gui_input.connect(func(ev: InputEvent):
			if ev.is_action_pressed("ui_left"):
				_cycle(k, -1)
				b.accept_event()
			elif ev.is_action_pressed("ui_right"):
				_cycle(k, 1)
				b.accept_event())
		var sw := ColorRect.new()  # Trikotfarbe als kleines Feld rechts im Knopf
		sw.custom_minimum_size = Vector2(40, 26)
		sw.position = Vector2(462, 12)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(sw)
		_main.add_child(b)
		_team_btn.append([b, sw])
	_update_teams()
	var s := _big("Einstellungen")
	s.pressed.connect(func(): settings.emit())
	_main.add_child(s)
	var c := _big("Steuerung")
	c.pressed.connect(_show_controls)
	_main.add_child(c)
	var q := _big("Beenden")
	q.pressed.connect(func(): get_tree().quit())
	_main.add_child(q)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 14)
	_main.add_child(gap2)
	_main.add_child(UiTheme.label("A / Enter wählt aus  ·  Steuerkreuz / Pfeiltasten wechseln", 16, UiTheme.MUTED))

	_build_controls()


func _cycle(k: int, step: int) -> void:
	_pick[k] = Teams.next_id(_pick[k], _pick[1 - k], step)
	_update_teams()


func _update_teams() -> void:
	for k in 2:
		var t := Teams.by_id(_pick[k])
		var b: Button = _team_btn[k][0]
		b.text = "%s:  ◀ %s ▶" % [["Dein Team", "Gegner"][k], t.name]
		(_team_btn[k][1] as ColorRect).color = t.jersey
	_update_sub()


## Spielen: sind andere Teams gewaehlt, wird die Halle mit den neuen Trikots neu aufgebaut.
func _on_play() -> void:
	if _pick[0] != Teams.home or _pick[1] != Teams.away:
		Teams.home = _pick[0]
		Teams.away = _pick[1]
		Teams.autostart = true
		get_tree().paused = false
		get_tree().reload_current_scene()
		return
	play.emit()


func _big(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(380, 58)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_size_override("font_size", 26)
	return b


func _build_controls() -> void:
	_controls = PanelContainer.new()
	var sb := UiTheme.box(UiTheme.BG, 16, Color(1, 1, 1, 0.06), 1)
	sb.set_content_margin_all(28)
	_controls.add_theme_stylebox_override("panel", sb)
	_controls.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_controls.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_controls.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_controls)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(980, 0)
	_controls.add_child(box)
	box.add_child(UiTheme.label("Steuerung", 36))
	box.add_child(UiTheme.label("Du spielst immer den Spieler mit dem gelben Ring.", 18, UiTheme.MUTED))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 6)
	var rows := [
		["", "Gamepad", "Tastatur"],
		["Laufen, Zuspiel-Richtung, Aufschlagziel, Block", "linker Stick", "WASD / Pfeiltasten"],
		["Baggern", "A", "Leertaste"],
		["Pritschen, Commit-Block", "X", "Q"],
		["Schlagen (halten, loslassen), Blocksprung", "R2", "E"],
		["Trefferpunkt am Ball, zweiter Blocker", "rechter Stick", "Maus oder I J K L"],
		["Aufschlag Stand / Sprung", "LB / RB", "1 / 2"],
		["Trainerbank (vor dem Aufschlag)", "Y", "T"],
		["Pause und Einstellungen", "Start", "Esc"],
		["Laufhilfe / Zeitlupe / Zoom an oder aus", "Select / – / –", "F1 / F2 / F3"],
		["Wiederholung überspringen", "A", "Leertaste"],
	]
	for i in rows.size():
		for j in 3:
			var col := UiTheme.ACCENT if i == 0 else (UiTheme.TEXT if j == 0 else UiTheme.MUTED)
			grid.add_child(UiTheme.label(rows[i][j], 19 if i > 0 else 17, col))
	box.add_child(grid)
	box.add_child(UiTheme.label("Annahme und Zuspiel: drücken, wenn sich der schrumpfende Ring mit dem weißen Ring deckt.\nMit Laufhilfe wird der weiße Ring grün, wenn Pritschen sicher geht, und orange, wenn du besser baggerst.", 17, UiTheme.MUTED))
	_back = Button.new()
	_back.text = "Zurück"
	_back.custom_minimum_size = Vector2(200, 48)
	_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_back.pressed.connect(_hide_controls)
	box.add_child(_back)
	_controls.visible = false


func _show_controls() -> void:
	_main.visible = false
	_controls.visible = true
	_back.grab_focus()


func _hide_controls() -> void:
	_controls.visible = false
	_main.visible = true
	_play.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and _controls.visible and event.is_action_pressed("ui_cancel"):
		_hide_controls()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	_hide_controls()
	focus()


func _update_sub() -> void:
	if cfg:
		_sub.text = "%s gegen %s  ·  %s  ·  Stufe %s" % [Teams.by_id(_pick[0]).name, Teams.by_id(_pick[1]).name,
			["1 Satz", "Best of 3", "Best of 5"][cfg.sets_to_win - 1], GameSettings.PRESET_TEXT[cfg.preset]]


func focus() -> void:
	_update_sub()
	if _controls.visible:
		_back.grab_focus()
	else:
		_play.grab_focus()


func _process(delta: float) -> void:
	_time += delta
	if _logo:
		_logo.modulate = Color(1, 1, 1).lerp(Color(1.0, 0.92, 0.7), 0.5 + 0.5 * sin(_time * 1.5))
