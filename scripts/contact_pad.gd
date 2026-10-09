extends Control
## Zeigt den Ball gross mit dem Trefferpunkt (rechter Stick) und daneben die Kraftanzeige.

var contact := Vector2.ZERO  # y + = oben
var charge := 0.0
var charging := false
var title := ""
var mode := "attack"  # attack oder serve

const RADIUS := 78.0
const OVERCHARGE := 1.25


func _ready() -> void:
	custom_minimum_size = Vector2(300, 250)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var c := Vector2(110, 130)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
	draw_string(font, Vector2(12, 26), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1))

	# Ball mit Zonen
	draw_circle(c, RADIUS, Color(1.0, 0.92, 0.45))
	draw_arc(c, RADIUS, 0, TAU, 64, Color(0.2, 0.2, 0.2), 3.0)
	var band := RADIUS * 0.35
	draw_line(c + Vector2(-RADIUS * 0.94, -band), c + Vector2(RADIUS * 0.94, -band), Color(0, 0, 0, 0.35), 2.0)
	draw_line(c + Vector2(-RADIUS * 0.94, band), c + Vector2(RADIUS * 0.94, band), Color(0, 0, 0, 0.35), 2.0)
	draw_arc(c, RADIUS * 0.85, 0, TAU, 64, Color(0, 0, 0, 0.18), 2.0)
	var top_txt := "Topspin"
	var mid_txt := "flach" if mode == "attack" else "Flatter"
	var low_txt := "Leger" if mode == "attack" else "kurz"
	_label(font, c + Vector2(0, -RADIUS * 0.6), top_txt)
	_label(font, c + Vector2(0, 5), mid_txt)
	_label(font, c + Vector2(0, RADIUS * 0.68), low_txt)

	# Trefferpunkt
	var p := c + Vector2(contact.x, -contact.y) * RADIUS * 0.92
	draw_circle(p, 10.0, Color(0.9, 0.1, 0.1))
	draw_arc(p, 13.0, 0, TAU, 24, Color(1, 1, 1), 2.0)

	# Kraftanzeige
	var bx := 220.0
	var by := 40.0
	var bh := 180.0
	var bw := 26.0
	var top_v := 1.5
	draw_rect(Rect2(bx, by, bw, bh), Color(0.1, 0.1, 0.1, 0.8))
	var sweet0 := by + bh * (1.0 - 1.0 / top_v)
	var sweet1 := by + bh * (1.0 - 0.75 / top_v)
	var over_y := by + bh * (1.0 - OVERCHARGE / top_v)
	draw_rect(Rect2(bx, sweet0, bw, sweet1 - sweet0), Color(0.2, 0.7, 0.3, 0.6))
	draw_rect(Rect2(bx, by, bw, over_y - by), Color(0.8, 0.15, 0.15, 0.5))
	var v := clampf(charge, 0.0, top_v)
	var fill_col := Color(1.0, 0.85, 0.1)
	if charge > OVERCHARGE:
		fill_col = Color(1.0, 0.3, 0.2)
	var h := bh * v / top_v
	var wobble := 0.0
	if charge > OVERCHARGE:
		wobble = sin(Time.get_ticks_msec() * 0.05) * 3.0
	if charging or charge > 0.0:
		draw_rect(Rect2(bx + 4 + wobble, by + bh - h, bw - 8, h), fill_col)
	draw_rect(Rect2(bx, by, bw, bh), Color(1, 1, 1, 0.8), false, 2.0)
	draw_string(font, Vector2(bx - 6, by + bh + 24), "Kraft", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1))


func _label(font: Font, pos: Vector2, txt: String) -> void:
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(font, pos + Vector2(-w / 2.0, 5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.1, 0.1, 0.1))
