extends CanvasLayer
## Anzeige: Spielstand, Hinweise, Meldungen nach jedem Punkt.

var _score: Label
var _hint: Label
var _msg: Label
var _info: Label
var _pad: Control


func _ready() -> void:
	_score = _label(40, HORIZONTAL_ALIGNMENT_CENTER)
	_score.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_score.position.y = 16
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
	_msg.text = "VOLLEYBALL  ·  Phase 1b Balancing\n\n" \
		+ "Du spielst immer den Spieler mit dem gelben Ring.\n\n" \
		+ "Baggern: A / Leertaste      Pritschen: X / Q\n" \
		+ "Schlagen (Aufschlag, Angriff): R2 / E halten und loslassen\n" \
		+ "Trefferpunkt am Ball: rechter Stick / Maus (oder I J K L)\n" \
		+ "Laufen, Zuspiel-Richtung, Aufschlagziel, Block: linker Stick / WASD\n" \
		+ "Aufschlag Stand/Sprung: LB/RB oder 1/2      Block springen: R2 / E\n\n" \
		+ "Einstellungen und Schwierigkeit: Esc / Start\n" \
		+ "Laufhilfe F1 / Select   Zeitlupe an/aus F2   Zoom F3\n\n" \
		+ "A / Leertaste: Spiel starten"
	_msg.label_settings.font_size = 28


func show_message(text: String) -> void:
	_msg.text = text
	_msg.label_settings.font_size = 48


func clear_message() -> void:
	_msg.text = ""


func update_view(m) -> void:
	var serve0 := "● " if m.serving_team == 0 else "   "
	var serve1 := " ●" if m.serving_team == 1 else "   "
	_score.text = "%s%s  %d : %d  %s%s" % [serve0, m.TEAM_NAMES[0], m.score[0], m.score[1], m.TEAM_NAMES[1], serve1]
	_hint.text = m.hint()
	_info.text = "Stufe: %s (Esc / Start)   Laufhilfe: %s (F1)   Zeitlupe: %s (F2)   Zoom: %s (F3)" % [
		GameSettings.PRESET_TEXT[m.cfg.preset], "an" if m.assist else "aus", "an" if m.slowmo_on else "aus", "an" if m.zoom_on else "aus"]
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
