extends Control
## Skill-Gap-Anzeige: der Name der Technik kurz nach dem Kontakt (z. B. "Roll-Shot · Anlauf von
## außen") und beim ersten Mal ein kleiner Tastenhinweis, wenn eine neue Technik gerade geht.
## Jeder Hinweis erscheint hoechstens SHOW_TIMES-mal und nicht mehr, sobald du die Technik
## selbst gespielt hast. Gemerkt wird das in user://hinweise.cfg.

const PATH := "user://hinweise.cfg"
const SHOW_TIMES := 3
const HINT_SECS := 3.6
const NAME_SECS := 1.5

var match_node
var _counts := {}  # Technik -> wie oft der Hinweis kam (SHOW_TIMES = gelernt)
var _name: Label
var _hint_box: PanelContainer
var _hint: Label
var _name_until := 0.0
var _hint_until := 0.0
var _name_keys: Array = []
var _name_t := -10.0
var _offer: Array = []  # in diesem Bild angebotene Techniken


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load()
	_name = Label.new()
	_name.add_theme_font_override("font", UiTheme.font_display)
	_name.add_theme_font_size_override("font_size", 40)
	_name.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	_name.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.09, 0.9))
	_name.add_theme_constant_override("outline_size", 10)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_name.position.y = 150
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name)
	_hint_box = PanelContainer.new()
	var sb := UiTheme.box(Color(0.086, 0.098, 0.122, 0.88), 14)
	sb.set_content_margin_all(12)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	_hint_box.add_theme_stylebox_override("panel", sb)
	_hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint = UiTheme.label("", 21, Color.WHITE)
	_hint_box.add_child(_hint)
	add_child(_hint_box)
	_name.visible = false
	_hint_box.visible = false
	match_node.technique_done.connect(_on_done)
	match_node.technique_available.connect(_on_available)


func _quiet() -> bool:
	return match_node.autoplay or match_node.attract or match_node.human_team < 0


func _on_done(pl, key: String) -> void:
	if _quiet() or pl == null or pl.team != match_node.human_team:
		return
	var txt := TechNames.text(key)
	if txt == "":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _name_t > 0.6:
		_name_keys = []
	_name_t = now
	if not _name_keys.has(txt):
		_name_keys.append(txt)
	_name.text = " · ".join(_name_keys)
	_name.reset_size()
	_name.position.x = (get_viewport_rect().size.x - _name.size.x) * 0.5
	_name.modulate.a = 1.0
	_name.visible = true
	_name_until = now + NAME_SECS
	# Selbst gespielt: der Hinweis dazu ist nicht mehr noetig.
	if int(_counts.get(key, 0)) < SHOW_TIMES:
		_counts[key] = SHOW_TIMES
		_save()


func _on_available(key: String) -> void:
	if _quiet() or TechNames.hint(key) == "":
		return
	if _offer.is_empty():
		_pick_offer.call_deferred()
	_offer.append(key)


## Aus allem, was gerade geht, den Hinweis zeigen, der am seltensten kam.
func _pick_offer() -> void:
	var best := ""
	var best_n := SHOW_TIMES
	for k in _offer:
		var n := int(_counts.get(k, 0))
		if n < best_n:
			best_n = n
			best = k
	_offer = []
	var now := Time.get_ticks_msec() / 1000.0
	if best == "" or now < _hint_until:
		return
	_counts[best] = best_n + 1
	_save()
	_hint.text = "Neu: " + TechNames.hint(best)
	_hint_box.reset_size()
	var vp := get_viewport_rect().size
	_hint_box.position = Vector2((vp.x - _hint_box.size.x) * 0.5, vp.y * 0.72)
	_hint_box.modulate.a = 1.0
	_hint_box.visible = true
	_hint_until = now + HINT_SECS


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _name.visible:
		_name.modulate.a = clampf((_name_until - now) / 0.4, 0.0, 1.0)
		_name.visible = now < _name_until
	if _hint_box.visible:
		_hint_box.modulate.a = clampf((_hint_until - now) / 0.5, 0.0, 1.0)
		_hint_box.visible = now < _hint_until


## Alle Hinweise wieder von vorn zeigen (Debug-Menue oder Tests).
func reset_hints() -> void:
	_counts = {}
	_save()


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for k in cf.get_section_keys("gesehen") if cf.has_section("gesehen") else []:
		_counts[k] = int(cf.get_value("gesehen", k, 0))


func _save() -> void:
	var cf := ConfigFile.new()
	for k in _counts:
		cf.set_value("gesehen", k, _counts[k])
	cf.save(PATH)
