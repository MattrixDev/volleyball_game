extends Control
## Mein Verein (heller Kachel-Stil wie das Startmenue): Verein gruenden, Team bauen,
## Kartensammlung mit Kartenshop und Aufgaben. Mit Controller (LB / RB wechselt die Seite,
## B geht zurueck), Tastatur (1 / 2, Esc) oder Maus bedienbar.

signal closed

const TABS := ["Team", "Sammlung", "Aufgaben"]
const CARD := Vector2(150, 212)
const CARD_SMALL := Vector2(124, 175)
## Feldaufstellung im Team-Bildschirm: Platz-Index (0 = Position 1) je Reihe, vorne zuerst.
const COURT_ROWS := [[3, 2, 1], [4, 5, 0]]
const FILTERS := ["Alle Karten", "Meine Karten", "Fehlende Karten"]
const ROLE_FILTER := ["", "S", "OH", "MB", "OP", "L"]

var _tab := 0
var _root: VBoxContainer
var _create: Control
var _header_name: Label
var _chip_rating: Label
var _chip_coins: Label
var _tab_btn: Array = []
var _pages: Array = []
var _msg: Label
var _overlay: Control  # Auswahl- oder Kaufdialog
var _overlay_back: Control  # wohin der Fokus nach dem Dialog geht
# Team
var _slot_cards: Array = []
var _team_info: Label
# Sammlung
var _filter := 0
var _role := 0
var _filter_btn: Button
var _role_btn: Button
var _grid: GridContainer
var _count_lab: Label
# Aufgaben
var _task_grid: GridContainer
# Verein gruenden
var _name_edit: LineEdit
var _name_idx := 0
var _color := 0
var _color_btns: Array = []
var _found_btn: Button


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
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 18)
	margin.add_child(_root)
	_root.add_child(_header())
	_root.add_child(_tabs())
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(stack)
	for f in [_team_page, _collection_page, _tasks_page]:
		var p: Control = f.call()
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.add_child(p)
		_pages.append(p)
	_root.add_child(_footer())
	_create = _create_page()
	add_child(_create)
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


func _chip(t: String, bg: Color, fg: Color) -> Array:
	var p := _panel(bg, 12, 0)
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	var l := _lab(t, 17, fg, UiTheme.font_semibold)
	p.add_child(l)
	return [p, l]


func _button(t: String, cb: Callable, w := 0.0) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(w, 46)
	b.add_theme_font_override("font", UiTheme.font_semibold)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(cb)
	return b


func _header() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(_lab("MEIN VEREIN", 13, UiTheme.INK_MUTED, UiTheme.font_semibold))
	_header_name = _lab("", 30, UiTheme.INK, UiTheme.font_display)
	v.add_child(_header_name)
	h.add_child(v)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	var a := _chip("", Color.WHITE, UiTheme.INK)
	a[0].size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chip_rating = a[1]
	h.add_child(a[0])
	var b := _chip("", UiTheme.ACCENT, UiTheme.INK)
	b[0].size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chip_coins = b[1]
	h.add_child(b[0])
	return h


func _tabs() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(_glyph("LB"))
	for i in TABS.size():
		var b := _button(TABS[i], _show_tab.bind(i), 170)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		h.add_child(b)
		_tab_btn.append(b)
	h.add_child(_glyph("RB"))
	return h


func _glyph(t: String) -> Control:
	var p := _panel(UiTheme.INK, 10, 0)
	p.custom_minimum_size = Vector2(40, 30)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := _lab(t, 12, Color.WHITE, UiTheme.font_semibold)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


func _footer() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.custom_minimum_size = Vector2(0, 30)
	for g in [["A", "Auswählen"], ["B", "Zurück"]]:
		var gl := _glyph(g[0])
		gl.custom_minimum_size = Vector2(30, 30)
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
	h.add_child(_msg)
	return h


func _say(t: String) -> void:
	_msg.text = t


# ------------------------------------------------------------------ Team

func _team_page() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	var court := _panel()
	court.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	court.size_flags_stretch_ratio = 1.25
	h.add_child(court)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 14)
	court.add_child(cv)
	var top := HBoxContainer.new()
	top.add_child(_lab("Startaufstellung", 22, UiTheme.INK, UiTheme.font_display))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(fill)
	top.add_child(_lab("Netz", 13, UiTheme.INK_MUTED, UiTheme.font_semibold))
	cv.add_child(top)
	_slot_cards.resize(Club.SLOTS)
	var rows := HBoxContainer.new()
	rows.add_theme_constant_override("separation", 24)
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_child(rows)
	var field := VBoxContainer.new()
	field.add_theme_constant_override("separation", 18)
	rows.add_child(field)
	for row in COURT_ROWS:
		var rh := HBoxContainer.new()
		rh.add_theme_constant_override("separation", 14)
		field.add_child(rh)
		for slot in row:
			rh.add_child(_slot_card(slot, CARD))
	var lib := VBoxContainer.new()
	lib.alignment = BoxContainer.ALIGNMENT_END
	rows.add_child(lib)
	lib.add_child(_lab("Libero", 13, UiTheme.INK_MUTED, UiTheme.font_semibold))
	lib.add_child(_slot_card(6, CARD))
	_team_info = _lab("", 15, UiTheme.INK_MUTED)
	_team_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(_team_info)

	var bench := _panel()
	bench.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(bench)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 14)
	bench.add_child(bv)
	bv.add_child(_lab("Bank", 22, UiTheme.INK, UiTheme.font_display))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 16)
	bv.add_child(g)
	for slot in range(7, Club.SLOTS):
		g.add_child(_slot_card(slot, CARD_SMALL))
	return h


func _slot_card(slot: int, sz: Vector2) -> PlayerCard:
	var c := PlayerCard.new("", sz)
	c.badge = str(slot + 1) if slot < 6 else ("L" if slot == 6 else "")
	c.empty_text = TeamRoster.ROLE_TEXT[Club.SLOT_ROLES[slot]] if slot < 7 else "frei"
	c.pressed.connect(_pick_for_slot.bind(slot))
	c.focus_entered.connect(func(): _say(_slot_hint(slot)))
	_slot_cards[slot] = c
	return c


func _slot_hint(slot: int) -> String:
	var id: String = Club.data.lineup[slot]
	var where := "Position " + Club.slot_name(slot) if slot < 6 else Club.slot_name(slot)
	if id == "":
		return "%s: frei. A wählt einen Spieler." % where
	var pd := Club.card(id)
	return "%s: %s, %s. A tauscht ihn aus." % [where, pd.full_name(), pd.summary()]


func _refresh_team() -> void:
	for slot in Club.SLOTS:
		(_slot_cards[slot] as PlayerCard).set_card(Club.data.lineup[slot])
	var miss := Club.missing()
	_team_info.text = ("Noch nicht spielbereit: " + miss) if miss != "" else \
		"Spielbereit. Im Startmenü wählst du deinen Verein als Team und spielst gegen jedes Ligateam."
	_team_info.add_theme_color_override("font_color", Color(0.7, 0.2, 0.15) if miss != "" else UiTheme.INK_MUTED)


## Auswahl fuer einen Platz: alle eigenen Karten, die dort passen (beste zuerst).
func _pick_for_slot(slot: int) -> void:
	var ids: Array = Club.data.owned.filter(func(i): return Club.fits(slot, i))
	ids.sort_custom(func(a, b): return Club.card(a).overall() > Club.card(b).overall())
	if slot >= 7:
		ids.push_front("")
	var title := "Spieler für " + ("Position " + Club.slot_name(slot) if slot < 6 else Club.slot_name(slot))
	_open_picker(title, ids, slot)


func _open_picker(title: String, ids: Array, slot: int) -> void:
	var box := _overlay_box(title, Vector2(1300, 720))
	var sc := ScrollContainer.new()
	sc.follow_focus = true
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(sc)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(m)
	var g := GridContainer.new()
	g.columns = 7
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 18)
	m.add_child(g)
	var first: Control = null
	var current: String = Club.data.lineup[slot]
	for id in ids:
		var c := PlayerCard.new(id, CARD)
		c.empty_text = "Platz leeren"
		var at: int = Club.data.lineup.find(id) if id != "" else -1
		if at >= 0 and at != slot:
			c.note = "steht auf " + ("Position %d" % (at + 1) if at < 6 else Club.slot_name(at))
			c.dim = true
		c.pressed.connect(func():
			Club.place(slot, id)
			_close_overlay()
			_refresh()
			_say(_slot_hint(slot)))
		c.focus_entered.connect(func():
			_say(("Platz leeren" if id == "" else Club.card(id).full_name() + " · " + Club.card(id).summary()) + \
				(("  ·  " + c.note) if c.note != "" else "")))
		g.add_child(c)
		if first == null or id == current:
			first = c
	if ids.is_empty():
		box.add_child(_lab("Du hast keine passende Karte. In der Sammlung kannst du Karten kaufen.", 17, UiTheme.INK_MUTED))
	_overlay_back = _slot_cards[slot]
	if first:
		first.grab_focus.call_deferred()


# ------------------------------------------------------------------ Sammlung

func _collection_page() -> Control:
	var p := _panel()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	h.add_child(_lab("Kartensammlung", 22, UiTheme.INK, UiTheme.font_display))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	_count_lab = _lab("", 15, UiTheme.INK_MUTED)
	_count_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_count_lab)
	_filter_btn = _button("", func():
		_filter = (_filter + 1) % FILTERS.size()
		_fill_grid(), 210)
	h.add_child(_filter_btn)
	_role_btn = _button("", func():
		_role = (_role + 1) % ROLE_FILTER.size()
		_fill_grid(), 230)
	h.add_child(_role_btn)
	var sc := ScrollContainer.new()
	sc.follow_focus = true
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(m)
	_grid = GridContainer.new()
	_grid.columns = 8
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 18)
	m.add_child(_grid)
	return p


func _fill_grid() -> void:
	_filter_btn.text = FILTERS[_filter] + "  ▸"
	var rf: String = ROLE_FILTER[_role]
	_role_btn.text = ("Alle Positionen" if rf == "" else TeamRoster.ROLE_TEXT[rf]) + "  ▸"
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var ids: Array = Club.all_ids().filter(func(i):
		var own := Club.owns(i)
		if (_filter == 1 and not own) or (_filter == 2 and own):
			return false
		return rf == "" or Club.card(i).role == rf)
	ids.sort_custom(func(a, b):
		var oa := Club.owns(a)
		var ob := Club.owns(b)
		if oa != ob:
			return oa
		return Club.card(a).overall() > Club.card(b).overall())
	for id in ids:
		var c := PlayerCard.new(id, CARD)
		if not Club.owns(id):
			c.locked = true
			var ch := Club.challenge_for(id)
			c.note = "Aufgabe" if ch != {} and not Club.is_done(ch.id) else "%s Münzen" % Club.fmt(Club.price(Club.card(id)))
		c.pressed.connect(_on_collection_card.bind(id, c))
		c.focus_entered.connect(func(): _say(_card_hint(id)))
		_grid.add_child(c)
	_count_lab.text = "%d von %d Karten" % [Club.data.owned.size(), Club.all_ids().size()]


func _card_hint(id: String) -> String:
	var pd := Club.card(id)
	var t := "%s (%s) · %s" % [pd.full_name(), Club.origin(id).name, pd.summary()]
	if Club.owns(id):
		var at: int = Club.data.lineup.find(id)
		return t + ("  ·  im Team" if at >= 0 else "  ·  in deiner Sammlung")
	var ch := Club.challenge_for(id)
	if ch != {} and not Club.is_done(ch.id):
		return t + "  ·  Aufgabe: " + ch.text
	return t + "  ·  Preis: %s Münzen" % Club.fmt(Club.price(pd))


func _on_collection_card(id: String, from: Control) -> void:
	if Club.owns(id):
		_say(_card_hint(id) + ". Ins Team stellst du ihn unter „Team“.")
		return
	var pd := Club.card(id)
	var ch := Club.challenge_for(id)
	var box := _overlay_box(pd.full_name(), Vector2(720, 470))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 26)
	box.add_child(h)
	var big := PlayerCard.new(id, Vector2(220, 311))
	big.focus_mode = Control.FOCUS_NONE
	h.add_child(big)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(_lab("%s · %s" % [TeamRoster.ROLE_TEXT[pd.role], Club.origin(id).name], 17, UiTheme.INK_MUTED))
	v.add_child(_lab("%s · Wertung %d" % [PlayerCard.TIER_NAME[Club.tier(pd)], pd.overall()], 20, UiTheme.INK, UiTheme.font_semibold))
	var first: Button
	if ch != {} and not Club.is_done(ch.id):
		var l := _lab("Diese Karte bekommst du nur über eine Aufgabe:\n" + ch.text, 18)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
		first = _button("Verstanden", _close_overlay, 240)
		v.add_child(first)
	else:
		var p := Club.price(pd)
		var l := _lab("Preis: %s Münzen\nDu hast: %s Münzen" % [Club.fmt(p), Club.fmt(Club.data.coins)], 18)
		v.add_child(l)
		first = _button("Kaufen für %s Münzen" % Club.fmt(p), func():
			var err := Club.buy(id)
			_close_overlay()
			_refresh()
			_say("%s ist jetzt in deiner Sammlung." % pd.full_name() if err == "" else err), 300)
		first.disabled = Club.data.coins < p
		v.add_child(first)
		if first.disabled:
			v.add_child(_lab("Dir fehlen noch %s Münzen. Münzen gibt es für jedes Spiel." % Club.fmt(p - Club.data.coins), 15, UiTheme.INK_MUTED))
		var cancel := _button("Abbrechen", _close_overlay, 300)
		v.add_child(cancel)
		if first.disabled:
			first = cancel
	_overlay_back = from
	first.grab_focus.call_deferred()


# ------------------------------------------------------------------ Aufgaben

func _tasks_page() -> Control:
	var p := _panel()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	v.add_child(_lab("Aufgaben", 22, UiTheme.INK, UiTheme.font_display))
	v.add_child(_lab("Jede Aufgabe schaltet eine bestimmte Karte frei. Sie zählen nur, wenn du mit deinem Verein spielst.", 15, UiTheme.INK_MUTED))
	var sc := ScrollContainer.new()
	sc.follow_focus = true
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 6)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(m)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 12)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(g)
	_task_grid = g
	return p


func _fill_tasks() -> void:
	var g := _task_grid
	for c in g.get_children():
		g.remove_child(c)
		c.queue_free()
	for ch in Club.challenges():
		var done := Club.is_done(ch.id)
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 120)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := UiTheme.box(Color(0.965, 0.96, 0.945) if not done else Color(0.9, 0.95, 0.9), 14)
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(st, sb)
		var h := HBoxContainer.new()
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 18
		h.offset_right = -12
		h.add_theme_constant_override("separation", 14)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(h)
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(v)
		var t := _lab(ch.text, 18, UiTheme.INK, UiTheme.font_semibold)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(t)
		var pd := Club.card(ch.card)
		var state := "Geschafft" if done else ("Stand: %d von %d" % [Club.progress(ch), ch.need] if ch.need > 1 else "Offen")
		v.add_child(_lab("%s  ·  Belohnung: %s (%s, %d)" % [state, pd.full_name(), TeamRoster.ROLE_TEXT[pd.role], pd.overall()],
			14, Color(0.2, 0.5, 0.25) if done else UiTheme.INK_MUTED))
		var mini := PlayerCard.new(ch.card, Vector2(72, 102))
		mini.focus_mode = Control.FOCUS_NONE
		mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mini.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(mini)
		b.focus_entered.connect(func(): _say(_card_hint(ch.card)))
		g.add_child(b)


# ------------------------------------------------------------------ Dialoge

func _overlay_box(title: String, sz: Vector2) -> VBoxContainer:
	_close_overlay()
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.07, 0.09, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_overlay = dim
	var p := _panel(UiTheme.PAPER, 22, 26)
	p.custom_minimum_size = sz
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	dim.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	p.add_child(v)
	v.add_child(_lab(title, 26, UiTheme.INK, UiTheme.font_display))
	return v


func _close_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null
		if is_instance_valid(_overlay_back):
			_overlay_back.grab_focus.call_deferred()


# ------------------------------------------------------------------ Verein gruenden

func _create_page() -> Control:
	var wrap := Control.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTheme.PAPER
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(bg)
	var p := _panel(Color.WHITE, 22, 36)
	p.custom_minimum_size = Vector2(900, 0)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	wrap.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	p.add_child(v)
	v.add_child(_lab("MEIN VEREIN", 13, UiTheme.INK_MUTED, UiTheme.font_semibold))
	v.add_child(_lab("Gründe deinen Verein", 34, UiTheme.INK, UiTheme.font_display))
	var intro := _lab("Du startest mit 14 Nachwuchs-Karten. Mit jedem Spiel verdienst du Münzen für den Kartenshop, " +
		"und jede Aufgabe schaltet einen bestimmten Ligaspieler frei. Nichts ist Zufall.", 17, UiTheme.INK_MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(intro)
	v.add_child(_lab("NAME", 13, UiTheme.INK_MUTED, UiTheme.font_semibold))
	var nh := HBoxContainer.new()
	nh.add_theme_constant_override("separation", 10)
	v.add_child(nh)
	_name_edit = LineEdit.new()
	_name_edit.text = Club.NAME_IDEAS[0]
	_name_edit.max_length = 24
	_name_edit.custom_minimum_size = Vector2(0, 50)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.add_theme_font_size_override("font_size", 20)
	_name_edit.add_theme_stylebox_override("normal", UiTheme.box(Color(0.945, 0.937, 0.918), 12))
	var nf := UiTheme.box(Color(0.945, 0.937, 0.918), 12, UiTheme.INK, 3)
	_name_edit.add_theme_stylebox_override("focus", nf)
	_name_edit.add_theme_color_override("font_color", UiTheme.INK)
	for sb in [_name_edit.get_theme_stylebox("normal"), nf]:
		sb.content_margin_left = 16
	nh.add_child(_name_edit)
	nh.add_child(_button("Anderer Vorschlag", func():
		_name_idx = (_name_idx + 1) % Club.NAME_IDEAS.size()
		_name_edit.text = Club.NAME_IDEAS[_name_idx], 240))
	v.add_child(_lab("VEREINSFARBE", 13, UiTheme.INK_MUTED, UiTheme.font_semibold))
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 12)
	v.add_child(ch)
	for i in Club.COLORS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(84, 60)
		b.tooltip_text = Club.COLORS[i][0]
		b.pressed.connect(func():
			_color = i
			_update_colors())
		b.focus_entered.connect(func(): _say("Vereinsfarbe: " + Club.COLORS[i][0]))
		ch.add_child(b)
		_color_btns.append(b)
	_found_btn = _button("Verein gründen", func():
		Club.create(_name_edit.text, _color)
		_create.visible = false
		_show_tab(0)
		_say("Willkommen! Deine 14 Nachwuchs-Karten stehen schon im Team."), 0)
	_found_btn.custom_minimum_size = Vector2(0, 54)
	v.add_child(_found_btn)
	_update_colors()
	return wrap


func _update_colors() -> void:
	for i in _color_btns.size():
		var c: Array = Club.COLORS[i]
		var sel := i == _color
		var sb := UiTheme.box(c[1], 12, UiTheme.INK if sel else Color(0, 0, 0, 0.12), 5 if sel else 1)
		if sel:
			sb.expand_margin_left = 4
			sb.expand_margin_right = 4
			sb.expand_margin_top = 4
			sb.expand_margin_bottom = 4
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			_color_btns[i].add_theme_stylebox_override(st, sb)


# ------------------------------------------------------------------ Ablauf

func open() -> void:
	visible = true
	_close_overlay()
	_say("")
	if not Club.exists():
		_create.visible = true
		_found_btn.grab_focus.call_deferred()
		return
	_create.visible = false
	_show_tab(_tab)


func close() -> void:
	_close_overlay()
	visible = false
	closed.emit()


func _show_tab(i: int) -> void:
	_tab = i
	for k in _pages.size():
		_pages[k].visible = k == i
		(_tab_btn[k] as Button).button_pressed = k == i
	_refresh()
	var target: Control = null
	match i:
		0: target = _slot_cards[0]
		1:
			if _grid.get_child_count() > 0:
				target = _grid.get_child(0)
		2:
			if _task_grid.get_child_count() > 0:
				target = _task_grid.get_child(0)
	if target:
		target.grab_focus.call_deferred()


func _refresh() -> void:
	if not Club.exists():
		return
	_header_name.text = Club.data.name
	_chip_rating.text = "Teamwertung %d" % Club.team_overall()
	_chip_coins.text = "%s Münzen" % Club.fmt(Club.data.coins)
	match _tab:
		0: _refresh_team()
		1: _fill_grid()
		2: _fill_tasks()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if _overlay:
			_close_overlay()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif _overlay == null and not _create.visible:
		if event.is_action_pressed("serve_prev"):
			_show_tab(posmod(_tab - 1, TABS.size()))
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("serve_next"):
			_show_tab(posmod(_tab + 1, TABS.size()))
			get_viewport().set_input_as_handled()
