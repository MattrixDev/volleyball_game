extends CanvasLayer
## Anzeige: Spielstand, Hinweise, Meldungen nach jedem Punkt.

var _score: Label
var _hint: Label
var _msg: Label
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
	_msg = _label(48, HORIZONTAL_ALIGNMENT_CENTER)
	_msg.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
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


func show_intro() -> void:
	_msg.text = "VOLLEYBALL  ·  Phase 1c Ganzes Match\n\n" \
		+ "Du spielst immer den Spieler mit dem gelben Ring.\n\n" \
		+ "Baggern: A / Leertaste      Pritschen: X / Q\n" \
		+ "Schlagen (Aufschlag, Angriff): R2 / E halten und loslassen\n" \
		+ "Trefferpunkt am Ball: rechter Stick / Maus (oder I J K L)\n" \
		+ "Laufen, Zuspiel-Richtung, Aufschlagziel, Block: linker Stick / WASD\n" \
		+ "Aufschlag Stand/Sprung: LB/RB oder 1/2      Block springen: R2 / E\n\n" \
		+ "Einstellungen und Schwierigkeit: Esc / Start\n" \
		+ "Laufhilfe F1 / Select   Zeitlupe an/aus F2   Zoom F3\n" \
		+ "Trainerbank (Libero, Wechsel, Auszeit) vor dem Aufschlag: T / Y\n\n" \
		+ "A / Leertaste: Spiel starten"
	_msg.label_settings.font_size = 28


func show_message(text: String) -> void:
	_msg.text = text
	_msg.label_settings.font_size = 48


func clear_message() -> void:
	_msg.text = ""


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
