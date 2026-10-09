class_name RefereeView
extends Control
## Schiedsrichter-Anzeige: zeigt das passende Handzeichen als Strichfigur mit Text und spielt
## den Pfiff. Zeichen kommen als Liste [Name, Text, Sekunden] und laufen nacheinander ab.

## Arm = [Ellbogen, Hand] relativ zur Schulter (Pixel). l = Arm links im Bild, r = rechts.
const POSES := {
	"serve_0": {"l": [Vector2(-34, 0), Vector2(-72, 0)], "r": [Vector2(12, 34), Vector2(14, 70)]},
	"serve_1": {"l": [Vector2(-12, 34), Vector2(-14, 70)], "r": [Vector2(34, 0), Vector2(72, 0)]},
	"in": {"l": [Vector2(-12, 34), Vector2(-14, 70)], "r": [Vector2(26, 26), Vector2(44, 62)]},
	"out": {"l": [Vector2(-40, 2), Vector2(-40, -48)], "r": [Vector2(40, 2), Vector2(40, -48)]},
	"net": {"l": [Vector2(-12, 34), Vector2(-14, 70)], "r": [Vector2(34, 10), Vector2(62, 22)]},
	"double": {"l": [Vector2(-12, 34), Vector2(-14, 70)], "r": [Vector2(34, -6), Vector2(36, -54)]},
	"held": {"l": [Vector2(-12, 34), Vector2(-14, 70)], "r": [Vector2(30, 26), Vector2(52, -2)]},
	"fault": {"l": [Vector2(-12, 34), Vector2(-14, 70)], "r": [Vector2(22, -28), Vector2(26, -64)]},
	"timeout": {"l": [Vector2(-14, 26), Vector2(-14, -22)], "r": [Vector2(30, -6), Vector2(-14, -26)]},
	"sub": {"l": [Vector2(-26, 24), Vector2(12, 0)], "r": [Vector2(26, 24), Vector2(-12, 0)]},
	"sidechange": {"l": [Vector2(-30, 14), Vector2(-22, -38)], "r": [Vector2(30, 14), Vector2(22, -38)]},
	"setend": {"l": [Vector2(-24, 22), Vector2(30, 6)], "r": [Vector2(24, 22), Vector2(-30, 6)]},
}
const SHOULDER := Vector2(100, 92)

var _seq: Array = []
var _until := 0.0
var _pose := ""
var _caption: Label
var _whistle_short: AudioStreamWAV
var _whistle_long: AudioStreamWAV
var _player: AudioStreamPlayer
var _time := 0.0
var volume := 35.0  # 0 bis 100, aus den Einstellungen


func _ready() -> void:
	custom_minimum_size = Vector2(200, 250)
	size = Vector2(200, 250)
	visible = false
	_caption = Label.new()
	_caption.position = Vector2(0, 192)
	_caption.size = Vector2(200, 56)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_size_override("font_size", 17)
	_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_caption.add_theme_constant_override("outline_size", 5)
	add_child(_caption)
	_whistle_short = _make_whistle(0.16)
	_whistle_long = _make_whistle(0.32)
	_player = AudioStreamPlayer.new()
	add_child(_player)


## Neue Zeichenfolge starten (leere Liste = ausblenden).
func show_signals(seq: Array) -> void:
	_seq = seq.duplicate()
	_until = 0.0
	if _seq.is_empty():
		_pose = ""
		visible = false
	else:
		_next()


func _next() -> void:
	if _seq.is_empty():
		_pose = ""
		visible = false
		return
	var s: Array = _seq.pop_front()
	_pose = s[0]
	_caption.text = s[1]
	_until = _time + float(s[2])
	visible = true
	queue_redraw()


func whistle(long: bool) -> void:
	if volume <= 0.0:
		return
	_player.volume_db = linear_to_db(volume / 100.0 * 0.35)
	_player.stream = _whistle_long if long else _whistle_short
	_player.play()


func _process(delta: float) -> void:
	_time += delta / maxf(Engine.time_scale, 0.01)
	if _pose != "" and _time >= _until:
		_next()
	if visible:
		queue_redraw()


func _draw() -> void:
	if _pose == "":
		return
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.07, 0.12, 0.72)
	bg.set_corner_radius_all(14)
	draw_style_box(bg, Rect2(Vector2.ZERO, size))
	var skin := Color(0.93, 0.76, 0.62)
	var shirt := Color(0.95, 0.95, 0.95)
	# Beine und Koerper
	draw_line(SHOULDER + Vector2(0, 40), SHOULDER + Vector2(-16, 92), Color(0.15, 0.15, 0.2), 8.0)
	draw_line(SHOULDER + Vector2(0, 40), SHOULDER + Vector2(16, 92), Color(0.15, 0.15, 0.2), 8.0)
	draw_line(SHOULDER, SHOULDER + Vector2(0, 42), shirt, 22.0)
	draw_circle(SHOULDER + Vector2(0, -24), 14.0, skin)
	var pose: Dictionary = POSES.get(_pose, POSES["fault"])
	if _pose == "net":
		draw_rect(Rect2(SHOULDER + Vector2(56, -20), Vector2(5, 90)), Color(0.9, 0.9, 0.9, 0.9))
		for i in 6:
			draw_line(SHOULDER + Vector2(56, -20 + i * 15), SHOULDER + Vector2(88, -20 + i * 15), Color(0.7, 0.7, 0.7, 0.6), 2.0)
	for k in ["l", "r"]:
		var a: Array = pose[k]
		var e: Vector2 = SHOULDER + (a[0] as Vector2)
		var h: Vector2 = SHOULDER + (a[1] as Vector2)
		var sh := SHOULDER + Vector2(-9 if k == "l" else 9, 0)
		draw_line(sh, e, shirt, 8.0)
		draw_line(e, h, skin, 7.0)
		draw_circle(h, 6.0, skin)
	match _pose:
		"double":
			var h2: Vector2 = SHOULDER + (pose["r"][1] as Vector2)
			draw_line(h2, h2 + Vector2(-5, -16), skin, 4.0)
			draw_line(h2, h2 + Vector2(5, -16), skin, 4.0)
		"held":
			draw_arc(SHOULDER + Vector2(48, 6), 20.0, -2.4, -0.6, 12, Color(1, 0.85, 0.3), 3.0)
		"sub", "sidechange":
			var ph := fmod(_time * 3.0, TAU)
			draw_arc(SHOULDER + Vector2(0, 8), 34.0, ph, ph + 2.4, 16, Color(1, 0.85, 0.3), 3.0)
			draw_arc(SHOULDER + Vector2(0, 8), 34.0, ph + PI, ph + PI + 2.4, 16, Color(1, 0.85, 0.3), 3.0)
		"timeout":
			draw_line(SHOULDER + Vector2(-34, -26), SHOULDER + Vector2(6, -26), Color(1, 0.85, 0.3), 3.0)


## Pfeifton selbst erzeugen: ein weicher, tiefer Ton (2 kHz, kaum Triller) mit sanftem Ein- und Ausblenden.
func _make_whistle(seconds: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(seconds * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / rate
		var f := 1950.0 + 40.0 * sin(TAU * 14.0 * t)
		phase += TAU * f / rate
		var env := minf(t / 0.05, 1.0) * minf((seconds - t) / 0.1, 1.0)
		var v := sin(phase) * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 16000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
