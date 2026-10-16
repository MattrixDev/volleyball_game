extends CanvasLayer
## Anzeige: Spielstand, Hinweise, Leiste fuer Satzende/Auszeit, Wechsel-Einblendung, Wiederholung.

var _pill: PanelContainer
var _chip: Array = []   # Trikotfarbfeld je Team
var _name: Array = []   # Teamname je Team
var _num: Array = []    # Punkte je Team
var _serve: Array = []  # Aufschlagpunkt je Team
var _setdots: Array = []  # je Team: Array von Panels (gewonnene Saetze)
var _setchip: Label
var _dev: PanelContainer  # kleine Karte oben links: Stufe, Hilfen, Aufstellung
var _hint: Label
var _banner: PanelContainer
var _banner_title: Label
var _banner_sub: Label
var _subs: VBoxContainer
var _replay: Control
var _score_tw: Tween
var _attract := false
signal whistled
var _info: Label
var _pad: Control
var _lineup: Label
var _notice: Label
var _ref: RefereeView
var trainer: Control = null  # Trainerbank (von main.gd gesetzt)


func _ready() -> void:
	_build_pill()
	_notice = _label(18, HORIZONTAL_ALIGNMENT_CENTER)
	_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_notice.position.y = 132
	_style_chip(_notice, Color(UiTheme.INK, 0.86), Color.WHITE)
	_info = _label(13, HORIZONTAL_ALIGNMENT_LEFT)
	_lineup = _label(14, HORIZONTAL_ALIGNMENT_LEFT)
	_build_dev_card()
	_ref = RefereeView.new()
	add_child(_ref)
	_ref.anchor_left = 1.0
	_ref.anchor_right = 1.0
	_ref.offset_left = -224.0
	_ref.offset_right = -24.0
	_ref.offset_top = 70.0
	_ref.offset_bottom = 320.0
	_hint = _label(19, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position.y -= 56
	_style_chip(_hint, Color(UiTheme.INK, 0.82), Color.WHITE)
	_build_banner()
	_subs = VBoxContainer.new()
	_subs.add_theme_constant_override("separation", 6)
	_subs.anchor_top = 1.0
	_subs.anchor_bottom = 1.0
	_subs.offset_left = 16.0
	_subs.offset_bottom = -110.0
	_subs.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_subs.alignment = BoxContainer.ALIGNMENT_END
	add_child(_subs)
	_build_replay()
	_pad = preload("res://scripts/contact_pad.gd").new()
	add_child(_pad)
	_pad.anchor_left = 1.0
	_pad.anchor_right = 1.0
	_pad.anchor_top = 1.0
	_pad.anchor_bottom = 1.0
	_pad.offset_left = -330.0
	_pad.offset_right = -30.0
	_pad.offset_top = -360.0
	_pad.offset_bottom = -110.0
	_pad.visible = false


func _round(c: Color, r := 16) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(r)
	sb.anti_aliasing = true
	return sb


## Schmale Kapsel hinter einem Label (Hinweise, Regelmeldungen): kein Umriss mehr, eigener Grund.
func _style_chip(l: Label, bg: Color, fg: Color) -> void:
	l.label_settings.outline_size = 0
	l.label_settings.font_color = fg
	l.label_settings.font = UiTheme.font_semibold
	var sb := _round(bg, 18)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	l.add_theme_stylebox_override("normal", sb)


func _txt(t: String, size: int, color: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", font if font else UiTheme.font_semibold)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _dot(d: float, c: Color) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(d, d)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_theme_stylebox_override("panel", _round(c, int(d / 2.0)))
	return p


## Spielstand: weisse Kapsel mit Trikotfarbe, Name, gewonnenen Saetzen und Punkten beider Teams.
func _build_pill() -> void:
	_pill = PanelContainer.new()
	var sb := _round(Color.WHITE, 18)
	sb.shadow_size = 14
	sb.shadow_color = Color(0, 0, 0, 0.22)
	sb.shadow_offset = Vector2(0, 5)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	_pill.add_theme_stylebox_override("panel", sb)
	_pill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pill.position.y = 20
	add_child(_pill)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_pill.add_child(row)
	for t in [0, 1]:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 9)
		var chip := Panel.new()
		chip.custom_minimum_size = Vector2(28, 28)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_chip.append(chip)
		var nm := _txt("", 18, UiTheme.INK)
		_name.append(nm)
		var dots := HBoxContainer.new()
		dots.add_theme_constant_override("separation", 4)
		dots.alignment = BoxContainer.ALIGNMENT_CENTER
		var ds := []
		for i in 3:
			var d := _dot(7, Color(0.85, 0.84, 0.81))
			dots.add_child(d)
			ds.append(d)
		_setdots.append(ds)
		var num := _txt("0", 30, UiTheme.INK, UiTheme.font_display)
		num.custom_minimum_size = Vector2(46, 0)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.pivot_offset = Vector2(23, 20)
		_num.append(num)
		var sv := _dot(8, UiTheme.INK)
		_serve.append(sv)
		if t == 0:
			box.add_child(chip)
			box.add_child(nm)
			box.add_child(dots)
			box.add_child(sv)
			box.add_child(num)
			row.add_child(box)
			_setchip = _txt("SATZ 1", 12, UiTheme.INK_MUTED)
			_setchip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var csb := _round(Color(0.945, 0.937, 0.918), 9)
			csb.content_margin_left = 10
			csb.content_margin_right = 10
			csb.content_margin_top = 4
			csb.content_margin_bottom = 4
			_setchip.add_theme_stylebox_override("normal", csb)
			_setchip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(_setchip)
		else:
			box.add_child(num)
			box.add_child(sv)
			box.add_child(dots)
			box.add_child(nm)
			box.add_child(chip)
			row.add_child(box)


## Kleine Karte oben links mit Stufe, Hilfen und Aufstellung (fuer Tester).
func _build_dev_card() -> void:
	_dev = PanelContainer.new()
	var sb := _round(Color(UiTheme.INK, 0.72), 14)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_dev.add_theme_stylebox_override("panel", sb)
	_dev.position = Vector2(20, 20)
	add_child(_dev)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_dev.add_child(v)
	for l in [_info, _lineup]:
		remove_child(l)
		l.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		l.label_settings.outline_size = 0
		l.label_settings.font = UiTheme.font_medium
		l.label_settings.font_color = Color(1, 1, 1, 0.86)
		v.add_child(l)
	_info.label_settings.font_color = Color(1, 1, 1, 0.6)


func _label(size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.outline_size = maxi(4, size / 5)
	ls.outline_color = Color(0, 0, 0, 0.85)
	l.label_settings = ls
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(l)
	return l


func _build_banner() -> void:
	_banner = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTheme.INK, 0.94)
	sb.set_corner_radius_all(20)
	sb.anti_aliasing = true
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 8
	sb.content_margin_bottom = 9
	_banner.add_theme_stylebox_override("panel", sb)
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.offset_top = 84.0
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_banner.add_child(box)
	_banner_title = Label.new()
	_banner_title.add_theme_font_size_override("font_size", 20)
	_banner_title.add_theme_font_override("font", UiTheme.font_semibold)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_banner_title)
	_banner_sub = Label.new()
	_banner_sub.add_theme_font_size_override("font_size", 14)
	_banner_sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.66))
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_banner_sub)
	_banner.visible = false
	add_child(_banner)


## Wiederholung: schmale schwarze Balken oben und unten wie im Fernsehen, Schild oben links.
func _build_replay() -> void:
	_replay = Control.new()
	_replay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_replay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.8)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		if top:
			bar.offset_bottom = 54.0
		else:
			bar.anchor_top = 1.0
			bar.anchor_bottom = 1.0
			bar.offset_top = -54.0
		_replay.add_child(bar)
	var tag := Label.new()
	tag.text = "●  WIEDERHOLUNG"
	tag.add_theme_font_size_override("font_size", 24)
	tag.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	tag.position = Vector2(24, 12)
	_replay.add_child(tag)
	_replay.visible = false
	add_child(_replay)
	move_child(_replay, 0)


## Schmale Leiste unter dem Spielstand (Satzende, Matchende, Auszeit, Seitenwechsel).
func show_banner(title: String, sub := "") -> void:
	if _attract:
		return
	_banner_title.text = title
	_banner_sub.text = sub
	_banner_sub.visible = sub != ""
	_banner.visible = true
	_banner.modulate.a = 0.0
	_banner.reset_size()
	create_tween().tween_property(_banner, "modulate:a", 1.0, 0.2)


func clear_message() -> void:
	_banner.visible = false


## Nach jedem Punkt springt die Zahl des Teams kurz auf (in der Teamfarbe).
func flash_score(team: int) -> void:
	if _score_tw:
		_score_tw.kill()
	var n: Label = _num[team]
	n.scale = Vector2.ONE * 1.3
	n.add_theme_color_override("font_color", UiTheme.INK.lerp(Teams.playing()[team].jersey, 0.8))
	_score_tw = create_tween().set_parallel(true)
	_score_tw.tween_property(n, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_score_tw.tween_method(func(k: float): n.add_theme_color_override("font_color", n.get_theme_color("font_color").lerp(UiTheme.INK, k)), 0.0, 1.0, 1.2)


## Wechsel-Einblendung unten links: Team, rein (gruen), raus (rot). Verschwindet nach `secs`.
func show_sub(team: int, team_name: String, what: String, in_txt: String, out_txt: String, secs: float) -> void:
	if _attract:
		return
	var p := PanelContainer.new()
	var sb := _round(Color.WHITE, 14)
	sb.shadow_size = 10
	sb.shadow_color = Color(0, 0, 0, 0.2)
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 10
	sb.content_margin_right = 18
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(34, 34)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_theme_stylebox_override("panel", _round(Teams.playing()[team].jersey, 10))
	h.add_child(chip)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	h.add_child(box)
	box.add_child(_txt("%s  ·  %s" % [what, team_name], 13, UiTheme.INK_MUTED, UiTheme.font_medium))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	row.add_child(_txt(out_txt, 17, UiTheme.INK_MUTED, UiTheme.font_medium))
	row.add_child(_txt("→", 17, UiTheme.INK_MUTED, UiTheme.font_medium))
	row.add_child(_txt(in_txt, 17, UiTheme.INK))
	_subs.add_child(p)
	while _subs.get_child_count() > 4:
		var old := _subs.get_child(0)
		_subs.remove_child(old)
		old.queue_free()
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.tween_interval(secs)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


func show_replay(on: bool) -> void:
	_replay.visible = on
	if not _attract:
		_dev.visible = not on
		_ref.modulate.a = 0.0 if on else 1.0


## Startmenue: nur der Spielstand des Hintergrundspiels bleibt sichtbar.
func set_attract(on: bool) -> void:
	_attract = on
	for c in [_dev, _hint, _notice, _subs, _pill]:
		c.visible = not on
	_ref.modulate.a = 0.0 if on else 1.0
	_banner.visible = false


## Pfiff zum Anhoeren im Einstellungsmenue (Lautstaerke schon eingerechnet).
func whistle_preview(vol: float) -> void:
	_ref.volume = vol
	_ref.whistle(false)


func whistle(long: bool) -> void:
	_ref.whistle(long)
	whistled.emit()


## Aktuelles Handzeichen (fuer den 3D-Schiedsrichter).
func ref_pose_name() -> String:
	return _ref._pose


func ref_signal(seq: Array) -> void:
	_ref.show_signals(seq)


func open_trainer() -> void:
	if trainer != null:
		trainer.open()


func update_view(m) -> void:
	var goal := "BIS %d" % m.set_target()
	_setchip.text = "SATZ %d  ·  %s" % [m.set_no, goal]
	for t in 2:
		var ts: TeamStyle = Teams.playing()[t]
		(_chip[t] as Panel).add_theme_stylebox_override("panel", _round(ts.jersey, 9))
		(_name[t] as Label).text = String(ts.name.split(" ")[-1])
		(_num[t] as Label).text = str(m.score[t])
		(_serve[t] as Panel).modulate.a = 1.0 if m.serving_team == t else 0.0
		var ds: Array = _setdots[t]
		for i in ds.size():
			(ds[i] as Panel).visible = i < m.cfg.sets_to_win
			(ds[i] as Panel).add_theme_stylebox_override("panel", _round(UiTheme.INK if i < m.sets_won[t] else Color(0.85, 0.84, 0.81), 4))
	_notice.text = m.notice if m.clock < m.notice_until else ""
	_hint.text = m.hint()
	if not _attract:
		_notice.visible = _notice.text != ""
		_hint.visible = _hint.text != ""
	_info.text = "Stufe %s  ·  Laufhilfe %s  ·  Zeitlupe %s  ·  Zoom %s" % [
		GameSettings.PRESET_TEXT[m.cfg.preset], "an" if m.assist else "aus", "an" if m.slowmo_on else "aus", "an" if m.zoom_on else "aus"]
	_lineup.text = _lineup_text(m)
	_ref.volume = m.cfg.get_v("whistle") * m.cfg.unit("fx_vol")
	var show := false
	if m.human_team >= 0 and not m.autoplay:
		if (m.phase == m.Phase.PRE_SERVE or m.phase == m.Phase.TOSS) and m.human_serves() and not m.serve_done:
			show = true
			_pad.mode = "serve"
			_pad.title = "Aufschlag: " + m.serve_style_text(m.serve_kind, m.serve_contact)
		elif m.phase == m.Phase.RALLY and m.opp != null and not m.opp.done and m.opp.human and m.opp.kind == "attack":
			show = true
			_pad.mode = "attack"
			var names := {"spike": "Angriff", "topspin": "Topspin", "tip": "Leger", "cut": "Cut Shot", "blockout": "Block-Out"}
			var info: Dictionary = m.attack_shot(m.opp.team, m.opp.point, m.rs, 0.8)
			_pad.title = "Angriff: " + names.get(info.style, "Angriff")
	_pad.visible = show
	if show:
		_pad.contact = m.rs
		_pad.charge = m.charge if m.charging else 0.0
		_pad.charging = m.charging


## Aufstellung des eigenen Teams: vorn links nach rechts (4 3 2), hinten (5 6 1).
func _lineup_text(m) -> String:
	var t: int = m.human_team if m.human_team >= 0 else 0
	var r: TeamRoster = m.rosters[t]
	var front := ""
	var back := ""
	for slot in [4, 3, 2]:
		front += _cell(r, slot)
	for slot in [5, 6, 1]:
		back += _cell(r, slot)
	var o: TeamRoster = m.rosters[1 - t]
	return "%s  ·  Aufstellung\nvorn   %s\nhinten %s\nAuszeiten %d  ·  Wechsel %d/%d%s\n%s: Auszeiten %d" % [
		m.TEAM_NAMES[t], front, back, r.timeouts_left, r.subs_used, TeamRoster.SUBS_PER_SET,
		"  ·  Libero im Spiel" if r.libero_on >= 0 else "", m.TEAM_NAMES[1 - t], o.timeouts_left]


func _cell(r: TeamRoster, slot: int) -> String:
	var mm: Dictionary = r.m(r.lineup[slot - 1])
	return "%d: %s%-3d  " % [slot, TeamRoster.ROLE_TAG[mm.role], mm.number]
