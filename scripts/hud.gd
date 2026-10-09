extends CanvasLayer
## Anzeige: Spielstand, Hinweise, Leiste fuer Satzende/Auszeit, Wechsel-Einblendung, Wiederholung.

var _score: Label
var _hint: Label
var _banner: PanelContainer
var _banner_title: Label
var _banner_sub: Label
var _subs: VBoxContainer
var _replay: Control
var _score_tw: Tween
var _attract := false
var _info: Label
var _pad: Control
var _sets: Label
var _lineup: Label
var _notice: Label
var _ref: RefereeView
var trainer: Control = null  # Trainerbank (von main.gd gesetzt)


func _ready() -> void:
	_score = _label(40, HORIZONTAL_ALIGNMENT_CENTER)
	_score.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_score.position.y = 16
	_sets = _label(22, HORIZONTAL_ALIGNMENT_CENTER)
	_sets.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_sets.position.y = 66
	_notice = _label(22, HORIZONTAL_ALIGNMENT_CENTER)
	_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_notice.position.y = 104
	_notice.label_settings.font_color = Color(1.0, 0.8, 0.3)
	_lineup = _label(17, HORIZONTAL_ALIGNMENT_LEFT)
	_lineup.grow_horizontal = Control.GROW_DIRECTION_END
	_lineup.grow_vertical = Control.GROW_DIRECTION_END
	_lineup.position = Vector2(16, 120)
	_ref = RefereeView.new()
	add_child(_ref)
	_ref.anchor_left = 1.0
	_ref.anchor_right = 1.0
	_ref.offset_left = -224.0
	_ref.offset_right = -24.0
	_ref.offset_top = 70.0
	_ref.offset_bottom = 320.0
	_hint = _label(26, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position.y -= 60
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
	_info = _label(18, HORIZONTAL_ALIGNMENT_LEFT)
	_info.grow_horizontal = Control.GROW_DIRECTION_END
	_info.grow_vertical = Control.GROW_DIRECTION_END
	_info.position = Vector2(16, 84)
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
	sb.bg_color = Color(0.06, 0.08, 0.13, 0.82)
	sb.border_color = Color(1.0, 0.78, 0.25)
	sb.border_width_bottom = 3
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	_banner.add_theme_stylebox_override("panel", sb)
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.offset_top = 140.0
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_banner.add_child(box)
	_banner_title = Label.new()
	_banner_title.add_theme_font_size_override("font_size", 28)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_banner_title)
	_banner_sub = Label.new()
	_banner_sub.add_theme_font_size_override("font_size", 18)
	_banner_sub.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
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


## Nach jedem Punkt leuchtet der Spielstand kurz in der Farbe des Teams auf.
func flash_score(team: int) -> void:
	if _score_tw:
		_score_tw.kill()
	var c: Color = [Color(0.55, 0.75, 1.0), Color(1.0, 0.55, 0.5)][team]
	_score.pivot_offset = _score.size / 2.0
	_score.modulate = c.lightened(0.2)
	_score.scale = Vector2.ONE * 1.18
	_score_tw = create_tween().set_parallel(true)
	_score_tw.tween_property(_score, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_score_tw.tween_property(_score, "modulate", Color.WHITE, 1.2)


## Wechsel-Einblendung unten links: Team, rein (gruen), raus (rot). Verschwindet nach `secs`.
func show_sub(team: int, team_name: String, what: String, in_txt: String, out_txt: String, secs: float) -> void:
	if _attract:
		return
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.13, 0.85)
	sb.border_color = [Color(0.3, 0.55, 1.0), Color(1.0, 0.35, 0.3)][team]
	sb.border_width_left = 6
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	p.add_child(box)
	var head := Label.new()
	head.text = "%s  ·  %s" % [what, team_name]
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	box.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)
	for part in [["REIN", in_txt, Color(0.45, 1.0, 0.5)], ["RAUS", out_txt, Color(1.0, 0.45, 0.4)]]:
		var l := Label.new()
		l.text = "%s  %s" % [part[0], part[1]]
		l.add_theme_font_size_override("font_size", 19)
		l.add_theme_color_override("font_color", part[2])
		row.add_child(l)
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
		_lineup.visible = not on
		_info.visible = not on
		_ref.modulate.a = 0.0 if on else 1.0


## Startmenue: nur der Spielstand des Hintergrundspiels bleibt sichtbar.
func set_attract(on: bool) -> void:
	_attract = on
	for c in [_lineup, _info, _hint, _notice, _subs]:
		c.visible = not on
	_ref.modulate.a = 0.0 if on else 1.0
	_banner.visible = false


func whistle(long: bool) -> void:
	_ref.whistle(long)


func ref_signal(seq: Array) -> void:
	_ref.show_signals(seq)


func open_trainer() -> void:
	if trainer != null:
		trainer.open()


func update_view(m) -> void:
	var serve0 := "● " if m.serving_team == 0 else "   "
	var serve1 := " ●" if m.serving_team == 1 else "   "
	_score.text = "%s%s  %d : %d  %s%s" % [serve0, m.TEAM_NAMES[0], m.score[0], m.score[1], m.TEAM_NAMES[1], serve1]
	var goal := "bis %d" % m.set_target()
	_sets.text = "Satz %d  ·  Sätze %d : %d  ·  %s" % [m.set_no, m.sets_won[0], m.sets_won[1], goal]
	_notice.text = m.notice if m.clock < m.notice_until else ""
	_hint.text = m.hint()
	_info.text = "Stufe: %s (Esc / Start)   Laufhilfe: %s (F1)   Zeitlupe: %s (F2)   Zoom: %s (F3)" % [
		GameSettings.PRESET_TEXT[m.cfg.preset], "an" if m.assist else "aus", "an" if m.slowmo_on else "aus", "an" if m.zoom_on else "aus"]
	_lineup.text = _lineup_text(m)
	_ref.volume = m.cfg.get_v("whistle")
	var show := false
	if m.human_team >= 0 and not m.autoplay:
		if (m.phase == m.Phase.PRE_SERVE or m.phase == m.Phase.TOSS) and m.serving_team == m.human_team and not m.serve_done:
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
