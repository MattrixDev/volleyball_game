class_name UiTheme
extends RefCounted
## Gemeinsames Aussehen fuer Startmenue, Pausenmenue und Trainerbank:
## dunkle Karten, runde Knoepfe, goldener Rahmen fuer die Auswahl (gut mit dem Controller).

const BG := Color(0.075, 0.086, 0.106, 0.97)
const CARD := Color(0.118, 0.133, 0.165, 1.0)
const ACCENT := Color(0.949, 0.702, 0.239)  # #F2B33D, das Gelb der Beta-Kachel
const BLUE := Color(0.22, 0.47, 0.95)
const TEXT := Color(0.95, 0.96, 0.98)
const MUTED := Color(0.62, 0.66, 0.72)
## Hell (Startmenue, Spielanzeige): warmes Grau, weisse Kacheln, fast schwarze Schrift.
const PAPER := Color(0.925, 0.918, 0.898)  # #ECEAE5
const TILE := Color.WHITE
const INK := Color(0.086, 0.098, 0.122)  # #16191F
const INK_MUTED := Color(0.478, 0.494, 0.525)  # #7A7E86
const NAVY := Color(0.141, 0.188, 0.31)  # #24304F

static var font_regular: Font = preload("res://assets/fonts/Inter-Regular.otf")
static var font_medium: Font = preload("res://assets/fonts/Inter-Medium.otf")
static var font_semibold: Font = preload("res://assets/fonts/Inter-SemiBold.otf")
static var font_display: Font = preload("res://assets/fonts/InterDisplay-ExtraBold.otf")

static var _theme: Theme
static var _light: Theme


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _make()
	return _theme


## Helles Theme (Pausenmenue): weisse Kacheln, Auswahl = dunkle Kachel, Fokus = dunkler Ring.
static func get_light_theme() -> Theme:
	if _light == null:
		_light = _make_light()
	return _light


static func _make_light() -> Theme:
	var t := Theme.new()
	t.default_font = font_medium
	t.default_font_size = 20
	var line := Color(INK, 0.08)
	t.set_stylebox("normal", "Button", box(TILE, 12, line, 1))
	t.set_stylebox("hover", "Button", box(Color(0.96, 0.955, 0.94), 12, line, 1))
	t.set_stylebox("pressed", "Button", box(INK, 12))
	t.set_stylebox("hover_pressed", "Button", box(INK.lightened(0.12), 12))
	t.set_stylebox("disabled", "Button", box(Color(0.93, 0.92, 0.9), 12))
	var focus := box(Color(0, 0, 0, 0), 14, INK, 3)
	focus.expand_margin_left = 2
	focus.expand_margin_right = 2
	focus.expand_margin_top = 2
	focus.expand_margin_bottom = 2
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_focus_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", INK_MUTED)
	t.set_color("font_color", "Label", INK)
	var rail := StyleBoxFlat.new()
	rail.bg_color = Color(0.85, 0.84, 0.81)
	rail.set_corner_radius_all(4)
	rail.content_margin_top = 4
	rail.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", rail)
	var fill := rail.duplicate()
	fill.bg_color = NAVY
	t.set_stylebox("grabber_area", "HSlider", fill)
	var fill_hl := rail.duplicate()
	fill_hl.bg_color = INK
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_hl)
	t.set_icon("grabber", "HSlider", _dot(18, NAVY))
	t.set_icon("grabber_highlight", "HSlider", _dot(22, ACCENT))
	var sfocus := StyleBoxFlat.new()
	sfocus.bg_color = Color(0, 0, 0, 0)
	sfocus.border_color = INK
	sfocus.set_border_width_all(2)
	sfocus.set_corner_radius_all(6)
	sfocus.expand_margin_left = 6
	sfocus.expand_margin_right = 6
	sfocus.expand_margin_top = 4
	sfocus.expand_margin_bottom = 4
	t.set_stylebox("focus", "HSlider", sfocus)
	return t


## Weisse Kachel mit grosser Rundung (heller Stil).
static func card_light() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(TILE, 18)
	sb.set_content_margin_all(18)
	p.add_theme_stylebox_override("panel", sb)
	return p


## Kleine graue Ueberschrift mit gelbem Punkt (heller Stil).
static func heading_light(t: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel", box(ACCENT, 5))
	row.add_child(dot)
	var l := label(t, 17, INK)
	l.add_theme_font_override("font", font_semibold)
	row.add_child(l)
	return row


static func box(c: Color, radius := 8, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.anti_aliasing = true
	return sb


static func _make() -> Theme:
	var t := Theme.new()
	t.default_font = font_medium
	t.default_font_size = 20
	t.set_stylebox("normal", "Button", box(Color(0.17, 0.19, 0.24), 12))
	t.set_stylebox("hover", "Button", box(Color(0.22, 0.25, 0.31), 12))
	t.set_stylebox("pressed", "Button", box(BLUE, 12))
	t.set_stylebox("hover_pressed", "Button", box(BLUE.lightened(0.1), 12))
	t.set_stylebox("disabled", "Button", box(Color(0.13, 0.145, 0.18), 12))
	var focus := box(Color(0, 0, 0, 0), 14, ACCENT, 3)
	focus.expand_margin_left = 2
	focus.expand_margin_right = 2
	focus.expand_margin_top = 2
	focus.expand_margin_bottom = 2
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	t.set_color("font_color", "Label", TEXT)
	# Regler: duenne Schiene, gefuellt bis zum Griff.
	var rail := StyleBoxFlat.new()
	rail.bg_color = Color(0.22, 0.25, 0.33)
	rail.set_corner_radius_all(4)
	rail.content_margin_top = 4
	rail.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", rail)
	var fill := rail.duplicate()
	fill.bg_color = BLUE
	t.set_stylebox("grabber_area", "HSlider", fill)
	var fill_hl := rail.duplicate()
	fill_hl.bg_color = ACCENT
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_hl)
	t.set_icon("grabber", "HSlider", _dot(18, Color.WHITE))
	t.set_icon("grabber_highlight", "HSlider", _dot(22, ACCENT))
	var sfocus := StyleBoxFlat.new()
	sfocus.bg_color = Color(0, 0, 0, 0)
	sfocus.border_color = ACCENT
	sfocus.set_border_width_all(2)
	sfocus.set_corner_radius_all(6)
	sfocus.expand_margin_left = 6
	sfocus.expand_margin_right = 6
	sfocus.expand_margin_top = 4
	sfocus.expand_margin_bottom = 4
	t.set_stylebox("focus", "HSlider", sfocus)
	t.set_stylebox("panel", "PanelContainer", box(BG, 18))
	return t


static func _dot(sz: int, c: Color) -> ImageTexture:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var r := sz / 2.0
	for y in sz:
		for x in sz:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			img.set_pixel(x, y, Color(c.r, c.g, c.b, clampf(r - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


static func label(t: String, size := 20, col := TEXT) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


## Ueberschrift einer Gruppe mit goldenem Strich davor.
static func heading(t: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var bar := ColorRect.new()
	bar.color = ACCENT
	bar.custom_minimum_size = Vector2(4, 22)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	row.add_child(label(t.to_upper(), 17, ACCENT))
	return row


static func card() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(CARD, 14)
	sb.set_content_margin_all(16)
	p.add_theme_stylebox_override("panel", sb)
	return p
