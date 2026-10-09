extends CanvasLayer
## Anzeige: Spielstand, Hinweise, Meldungen nach jedem Punkt.

var _score: Label
var _hint: Label
var _msg: Label
var _info: Label


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
	_info.position = Vector2(16, 16)


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
	_msg.text = "VOLLEYBALL  ·  Prototyp Phase 0\n\n" \
		+ "Du spielst immer den Spieler mit dem gelben Ring.\n" \
		+ "Drücke A / Leertaste, wenn sich der Ring am Boden schließt.\n\n" \
		+ "Bewegen: linker Stick / WASD\n" \
		+ "Zuspiel: X / J Außen   Y / K Mitte   B / L Diagonal\n" \
		+ "Legen statt schlagen: RB / Umschalt\n" \
		+ "Laufhilfe an/aus: Select / F1\n\n" \
		+ "A / Leertaste: Spiel starten"
	_msg.label_settings.font_size = 30


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
	_info.text = "Laufhilfe: %s (F1)" % ("an" if m.assist else "aus")
