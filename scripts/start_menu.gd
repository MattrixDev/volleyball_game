extends Control
## Startmenue im Kachel-Stil ("Bento"): grosse Kachel fuer das Spiel, Teamwahl, Mein Verein,
## darunter Einstellungen, Steuerung, Beenden und Beta-Feedback. Alles ist mit Controller,
## Steuerkreuz oder Tastatur bedienbar (A / Enter waehlt aus, links / rechts wechselt Teams).

signal play
signal settings
signal debug

## Beta: wohin "Feedback senden" fuehrt.
const FEEDBACK_URL := "https://github.com/MattrixDev/volleyball_game/issues/new"
const TIPS := [
	"Angriff: R2 halten, der Spieler läuft an und springt automatisch. Loslassen schlägt den Ball.",
	"Baggern mit A, Pritschen mit X: früh halten und im richtigen Moment loslassen.",
	"Zuspiel: Richtung am Steuerkreuz halten und loslassen. R2 dazu macht das Zuspiel schneller.",
	"Aufschlag: LB schlägt aus dem Stand auf, RB im Sprung. Das Ziel wählst du mit dem linken Stick.",
	"Trainerbank vor dem Aufschlag: Y oder T. Dort wechselst du Spieler und rufst die Auszeit.",
	"Mit F1 schaltest du die Laufhilfe an oder aus, mit F2 die Zeitlupe.",
	"Wuchtschlag: Lass R2 los, wenn der Kraftbalken im goldenen Streifen steht, und triff perfekt.",
]

var cfg: GameSettings
var _main: Control
var _controls: Control
var _play: Button
var _back: Button
var _time := 0.0
var _jerseys: Array = []
var _team_btn: Array = []  # je Seite: [Button, Farbfeld, Namenslabel]
var _pick := []  # gewaehlte Team-ids [eigenes, Gegner]
var _hero_title: Label
var _hero_sub: Label
var _tip: Label
var _tip_idx := 0
var _tip_t := 0.0
var _tip_hold := 0.0
var _club: Control
var _club_btn: Button
var _club_sub: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	var paper := ColorRect.new()
	paper.color = UiTheme.PAPER
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(paper)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 80)
	margin.add_theme_constant_override("margin_top", 44)
	margin.add_theme_constant_override("margin_bottom", 36)
	add_child(margin)
	_main = margin
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	margin.add_child(col)

	col.add_child(_top_bar())
	var row_a := HBoxContainer.new()
	row_a.add_theme_constant_override("separation", 22)
	row_a.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row_a.size_flags_stretch_ratio = 3.4
	col.add_child(row_a)
	_pick = [Teams.home, Teams.away]
	if Club.can_play() and not Teams.picked:
		_pick[0] = Club.ID
		if _pick[1] == Club.ID:
			_pick[1] = Teams.away
	row_a.add_child(_hero_tile(720.0))
	row_a.add_child(_teams_tile(360.0))
	row_a.add_child(_club_tile(312.0))

	var row_b := HBoxContainer.new()
	row_b.add_theme_constant_override("separation", 22)
	row_b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row_b.size_flags_stretch_ratio = 1.0
	col.add_child(row_b)
	row_b.add_child(_small_tile("gear", "Einstellungen", "Bild, Ton, Schwierigkeit", func(): settings.emit()))
	row_b.add_child(_small_tile("pad", "Steuerung", "Alle Tasten", _show_controls))
	row_b.add_child(_small_tile("ball", "Kurzes Match", "Ein Satz bis 15", _on_play.bind(true)))
	row_b.add_child(_small_tile("exit", "Beenden", "Zurück zum Desktop", func(): get_tree().quit()))
	row_b.add_child(_small_tile("chat", "Beta-Feedback", "Fehler melden, Ideen schicken", func(): OS.shell_open(FEEDBACK_URL), true))
	if DebugMode.ENABLED:
		row_b.add_child(_small_tile("debug", "Debug", "Übungen, Karten, Aufgaben", func(): debug.emit()))

	col.add_child(_tip_bar())
	col.add_child(_footer())
	_update_teams()
	_build_controls()
	_club = preload("res://scripts/club_menu.gd").new()
	_club.closed.connect(_on_club_closed)
	add_child(_club)


# ------------------------------------------------------------------ Bausteine

func _font_label(t: String, size: int, color: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", font if font else UiTheme.font_medium)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _caption(t: String, color: Color) -> Label:
	var l := _font_label(t.to_upper(), 13, color, UiTheme.font_semibold)
	return l


func _round(c: Color, r := 18, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(r)
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.anti_aliasing = true
	return sb


## Eine anwaehlbare Kachel: weisser Grund, bei Auswahl dunkler Rahmen.
func _tile_button(bg: Color, ring: Color = UiTheme.INK) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, _round(bg))
	b.add_theme_stylebox_override("disabled", _round(bg.darkened(0.04)))
	var focus := _round(Color(0, 0, 0, 0), 18, ring, 4)
	focus.expand_margin_left = 3
	focus.expand_margin_right = 3
	focus.expand_margin_top = 3
	focus.expand_margin_bottom = 3
	b.add_theme_stylebox_override("focus", focus)
	return b


func _glyph(letter: String, bg: Color, fg: Color, size := 24) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _round(bg, size / 2))
	p.custom_minimum_size = Vector2(size, size)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _font_label(letter, int(size * 0.46), fg, UiTheme.font_semibold)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


func _top_bar() -> Control:
	var h := HBoxContainer.new()
	h.custom_minimum_size = Vector2(0, 40)
	var logo := _font_label("Volleyball", 30, UiTheme.INK, UiTheme.font_display)
	h.add_child(logo)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	var tag := _font_label("Hallenvolleyball 6 gegen 6 · FIVB-Regeln", 16, UiTheme.INK_MUTED)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(tag)
	return h


func _gradient_bottom() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0.05, 0.055, 0.08, 0.96))
	g.set_color(1, Color(0.05, 0.055, 0.08, 0.0))
	g.add_point(0.45, Color(0.05, 0.055, 0.08, 0.7))
	g.add_point(0.78, Color(0.05, 0.055, 0.08, 0.15))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 1)
	gt.fill_to = Vector2(0, 0)
	gt.width = 4
	gt.height = 256
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _hero_tile(width: float) -> Control:
	var b := _tile_button(Color(0.1, 0.11, 0.14))
	b.custom_minimum_size = Vector2(width * 0.5, 0)
	b.size_flags_stretch_ratio = width
	b.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	b.pressed.connect(_on_play.bind(false))
	_play = b
	var img := TextureRect.new()
	img.texture = load("res://assets/ui/menu_hero.jpg")
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(img)
	b.add_child(_gradient_bottom())
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 36)
	m.add_theme_constant_override("margin_top", 30)
	b.add_child(m)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_END
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	v.add_child(_caption("Schnelles Match", Color(1, 1, 1, 0.75)))
	_hero_title = _font_label("", 44, Color.WHITE, UiTheme.font_display)
	v.add_child(_hero_title)
	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(bottom)
	_hero_sub = _font_label("", 17, Color(1, 1, 1, 0.85))
	_hero_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(_hero_sub)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _round(Color.WHITE, 24))
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cm := MarginContainer.new()
	cm.add_theme_constant_override("margin_left", 10)
	cm.add_theme_constant_override("margin_right", 20)
	cm.add_theme_constant_override("margin_top", 9)
	cm.add_theme_constant_override("margin_bottom", 9)
	cm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(cm)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 10)
	ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cm.add_child(ch)
	ch.add_child(_glyph("A", UiTheme.INK, Color.WHITE))
	ch.add_child(_font_label("Los geht's", 16, UiTheme.INK, UiTheme.font_semibold))
	bottom.add_child(chip)
	return b


func _teams_tile(width: float) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _round(Color.WHITE))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = width
	p.custom_minimum_size = Vector2(width * 0.5, 0)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 26)
	p.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	v.add_child(_caption("Teams", UiTheme.INK_MUTED))
	v.add_child(_font_label("Trikots und Gegner", 24, UiTheme.INK, UiTheme.font_display))
	var jr := HBoxContainer.new()
	jr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	jr.add_theme_constant_override("separation", 14)
	jr.custom_minimum_size = Vector2(0, 96)
	jr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(jr)
	for k in 2:
		var jc := Jersey.new()
		jc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		jc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		jc.number = [7, 11][k]
		jr.add_child(jc)
		_jerseys.append(jc)
	for k in 2:
		var side_lab := _caption(["Dein Team", "Gegner"][k], UiTheme.INK_MUTED)
		v.add_child(side_lab)
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 54)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(st, _round(Color(0.945, 0.937, 0.918), 12))
		var focus := _round(Color(0, 0, 0, 0), 12, UiTheme.INK, 3)
		focus.expand_margin_left = 2
		focus.expand_margin_right = 2
		focus.expand_margin_top = 2
		focus.expand_margin_bottom = 2
		b.add_theme_stylebox_override("focus", focus)
		b.pressed.connect(_cycle.bind(k, 1))
		b.gui_input.connect(func(ev: InputEvent):
			if ev.is_action_pressed("ui_left"):
				_cycle(k, -1)
				b.accept_event()
			elif ev.is_action_pressed("ui_right"):
				_cycle(k, 1)
				b.accept_event())
		var h := HBoxContainer.new()
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 12
		h.offset_right = -14
		h.add_theme_constant_override("separation", 10)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(h)
		var sw := Panel.new()
		sw.custom_minimum_size = Vector2(26, 26)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(sw)
		var nm := _font_label("", 17, UiTheme.INK, UiTheme.font_semibold)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nm.clip_text = true
		h.add_child(nm)
		h.add_child(_font_label("◀ ▶", 12, UiTheme.INK_MUTED))
		v.add_child(b)
		_team_btn.append([b, sw, nm])
	return p


## Mein Verein: Spielerkarten sammeln und das eigene Team bauen.
func _club_tile(width: float) -> Control:
	var b := _tile_button(UiTheme.NAVY)
	b.custom_minimum_size = Vector2(width * 0.5, 0)
	b.size_flags_stretch_ratio = width
	b.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	b.pressed.connect(_open_club)
	_club_btn = b
	var pl := TextureRect.new()
	pl.texture = load("res://assets/ui/menu_block.png")
	pl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pl.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pl.anchor_left = 0.42
	pl.anchor_right = 1.0
	pl.anchor_top = 0.3
	pl.anchor_bottom = 1.0
	pl.offset_right = -6
	pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(pl)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 28)
	b.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	v.add_child(_caption("Mein Verein", Color(1, 1, 1, 0.7)))
	var t := _font_label("Karten sammeln,\nTeam bauen", 24, Color.WHITE, UiTheme.font_display)
	v.add_child(t)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _round(UiTheme.ACCENT, 7))
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cm := MarginContainer.new()
	cm.add_theme_constant_override("margin_left", 10)
	cm.add_theme_constant_override("margin_right", 10)
	cm.add_theme_constant_override("margin_top", 4)
	cm.add_theme_constant_override("margin_bottom", 4)
	cm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(cm)
	_club_sub = _font_label("", 12, UiTheme.INK, UiTheme.font_semibold)
	cm.add_child(_club_sub)
	v.add_child(chip)
	_update_club_tile()
	return b


func _update_club_tile() -> void:
	if _club_sub:
		_club_sub.text = "%s Münzen" % Club.fmt(Club.data.coins) if Club.exists() else "Neu"


## Nach dem Debug-Menue: Verein kann geloescht oder neu sein.
func refresh_after_debug() -> void:
	if _pick[0] == Club.ID and not Club.can_play():
		_pick[0] = Teams.next_id(Club.ID, _pick[1])
	_update_teams()
	_update_club_tile()


func _open_club() -> void:
	_main.visible = false
	_club.open()


## Zurueck aus Mein Verein: ist das Team spielbereit, wird es gleich als eigenes Team gewaehlt.
func _on_club_closed() -> void:
	_main.visible = true
	if Club.can_play():
		_pick[0] = Club.ID
		if _pick[1] == Club.ID:
			_pick[1] = Teams.next_id(_pick[1], Club.ID)
	_update_teams()
	_update_club_tile()
	_club_btn.grab_focus()


func _small_tile(icon: String, title: String, desc: String, action: Callable, yellow := false) -> Button:
	var b := _tile_button(UiTheme.ACCENT if yellow else Color.WHITE)
	b.custom_minimum_size = Vector2(120, 0)
	if action.is_valid():
		b.pressed.connect(action)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 24)
	m.add_theme_constant_override("margin_top", 20)
	m.add_theme_constant_override("margin_bottom", 18)
	b.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	var ic := TextureRect.new()
	ic.texture = load("res://assets/ui/icon_%s.png" % icon)
	ic.custom_minimum_size = Vector2(26, 26)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ic)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sp)
	var fg := UiTheme.INK
	var muted := Color(0.086, 0.098, 0.122, 0.62) if yellow else UiTheme.INK_MUTED
	if b.disabled == false and not action.is_valid():
		fg = Color(UiTheme.INK, 0.5)
	v.add_child(_font_label(title, 20, fg, UiTheme.font_semibold))
	var d := _font_label(desc, 13, muted)
	d.clip_text = true
	v.add_child(d)
	return b


func _tip_bar() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _round(Color.WHITE, 14))
	p.custom_minimum_size = Vector2(0, 52)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 24)
	m.add_theme_constant_override("margin_right", 24)
	p.add_child(m)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	m.add_child(h)
	var cap := _caption("Tipp", UiTheme.INK_MUTED)
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(cap)
	_tip = _font_label(TIPS[0], 16, Color(UiTheme.INK, 0.8))
	_tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tip.clip_text = true
	h.add_child(_tip)
	return p


func _footer() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.custom_minimum_size = Vector2(0, 28)
	for g in [["A", "Auswählen"], ["B", "Zurück"]]:
		h.add_child(_glyph(g[0], UiTheme.INK, Color.WHITE))
		var l := _font_label(g[1], 15, UiTheme.INK_MUTED)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(l)
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(14, 0)
		h.add_child(sp)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(fill)
	h.add_child(_font_label("BETA", 13, UiTheme.INK_MUTED, UiTheme.font_semibold))
	return h


# ------------------------------------------------------------------ Verhalten

func _say(t: String) -> void:
	_tip.text = t
	_tip_hold = 4.0


func _cycle(k: int, step: int) -> void:
	_pick[k] = Teams.next_id(_pick[k], _pick[1 - k], step, k == 0)
	_update_teams()


func _update_teams() -> void:
	for k in 2:
		var t := Teams.by_id(_pick[k])
		(_team_btn[k][2] as Label).text = t.name
		var sw: Panel = _team_btn[k][1]
		sw.add_theme_stylebox_override("panel", _round(t.jersey, 8, Color(0, 0, 0, 0.18), 1))
		(_jerseys[k] as Jersey).team = t
		(_jerseys[k] as Jersey).queue_redraw()
	_update_sub()


func _update_sub() -> void:
	if _hero_title == null:
		return
	_hero_title.text = "%s gegen\n%s" % [Teams.by_id(_pick[0]).name, Teams.by_id(_pick[1]).name]
	if cfg:
		_hero_sub.text = "%s  ·  Stufe %s" % [["1 Satz", "Best of 3", "Best of 5"][cfg.sets_to_win - 1], GameSettings.PRESET_TEXT[cfg.preset]]


## Spielen: sind andere Teams gewaehlt, wird die Halle mit den neuen Trikots neu aufgebaut.
func _on_play(quick := false) -> void:
	Teams.quick = quick
	Teams.picked = true
	if _pick[0] == Club.ID and not Club.can_play():
		_say("Dein Verein ist noch nicht spielbereit: " + Club.missing())
		return
	# Mein Verein wird immer frisch aufgebaut (die Aufstellung kann sich geaendert haben).
	if _pick[0] != Teams.home or _pick[1] != Teams.away or _pick[0] == Club.ID:
		Teams.home = _pick[0]
		Teams.away = _pick[1]
		Teams.autostart = true
		get_tree().paused = false
		get_tree().reload_current_scene()
		return
	play.emit()


func _build_controls() -> void:
	_controls = PanelContainer.new()
	var sb := UiTheme.box(UiTheme.BG, 18, Color(1, 1, 1, 0.06), 1)
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
		["Baggern (halten, im richtigen Moment loslassen)", "A", "Leertaste"],
		["Pritschen (halten, loslassen), Commit-Block", "X", "Q"],
		["Zuspiel: Richtung halten, zum Zuspielen loslassen", "Steuerkreuz", "–"],
		["Schlagen (halten, beim Treffpunkt loslassen), Blocksprung", "R2", "E"],
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
	box.add_child(UiTheme.label("Taste früh halten und loslassen, wenn sich der schrumpfende Ring mit dem weißen Ring deckt.\nMit Laufhilfe wird der weiße Ring grün, wenn Pritschen sicher geht, und orange, wenn du besser baggerst.\nWuchtschlag: Lass R2 los, wenn der Kraftbalken im goldenen Streifen steht, und triff perfekt (Angriff und Aufschlag).", 17, UiTheme.MUTED))
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
	_update_club_tile()
	focus()


func focus() -> void:
	_update_sub()
	if _controls.visible:
		_back.grab_focus()
	else:
		_play.grab_focus()


func _process(delta: float) -> void:
	if not visible:
		return
	_tip_t += delta
	if _tip_hold > 0.0:
		_tip_hold -= delta
		_tip_t = 0.0
	elif _tip_t > 9.0:
		_tip_t = 0.0
		_tip_idx = (_tip_idx + 1) % TIPS.size()
		_tip.text = TIPS[_tip_idx]


## Kleines Trikot in den Teamfarben (Form wie im Entwurf).
class Jersey extends Control:
	var team: TeamStyle
	var number := 7

	func _draw() -> void:
		if team == null:
			return
		var sc := minf(size.x / 118.0, size.y / 132.0)
		var off := Vector2((size.x - 118.0 * sc) / 2.0, (size.y - 132.0 * sc) / 2.0)
		var pts := PackedVector2Array()
		var base := [Vector2(38, 26), Vector2(24, 30), Vector2(10, 48), Vector2(22, 58), Vector2(30, 50), Vector2(30, 112),
			Vector2(88, 112), Vector2(88, 50), Vector2(96, 58), Vector2(108, 48), Vector2(94, 30), Vector2(80, 26)]
		for q in base:
			pts.append(off + q * sc)
		for i in range(1, 8):  # Halsausschnitt als Kurve von (80,26) ueber (59,40) nach (38,26)
			var tt := i / 8.0
			var a := Vector2(80, 26).lerp(Vector2(59, 40), tt)
			var b := Vector2(59, 40).lerp(Vector2(38, 26), tt)
			pts.append(off + a.lerp(b, tt) * sc)
		draw_colored_polygon(pts, team.jersey)
		for strip in [[30, 60, 36, 112], [82, 60, 88, 112]]:
			draw_rect(Rect2(off + Vector2(strip[0], strip[1]) * sc, Vector2(strip[2] - strip[0], strip[3] - strip[1]) * sc), team.panel)
		var f := UiTheme.font_display
		var fs := int(34.0 * sc)
		var txt := str(number)
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, off + Vector2(59.0 * sc - w / 2.0, 90.0 * sc), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, team.number)
