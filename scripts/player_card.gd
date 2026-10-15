## Eine Spielerkarte (Bronze, Silber, Gold) zum Anwaehlen: Wertung, Position, Trikot des Teams,
## Name, Groesse, die acht Staerken und die Spielstile. Gesperrte Karten sind blass und zeigen,
## wie man sie bekommt. Ohne Karte (id leer) zeigt sie einen freien Platz.
class_name PlayerCard
extends Button

const TIER_TOP := [Color(0.72, 0.52, 0.36), Color(0.82, 0.83, 0.85), Color(0.89, 0.76, 0.42)]
const TIER_BOTTOM := [Color(0.55, 0.38, 0.25), Color(0.62, 0.64, 0.68), Color(0.7, 0.55, 0.22)]
const TIER_INK := [Color(0.18, 0.1, 0.05), Color(0.12, 0.13, 0.16), Color(0.2, 0.13, 0.02)]
const TIER_NAME := ["Bronze", "Silber", "Gold"]
const SPLIT := 0.52  # Grenze zwischen hellem Kopf und dunklem Werteteil (Anteil der Hoehe)
const ROLE_SHORT := {"S": "ZUS", "OH": "AUS", "MB": "MIT", "OP": "DIA", "L": "LIB"}
const STATS := [["jump", "SPR"], ["power", "KRA"], ["serve", "AUF"], ["receive", "ANN"],
	["defense", "ABW"], ["setting", "ZSP"], ["block", "BLO"], ["speed", "TEM"]]

var id := ""
var locked := false
var note := ""  ## kleine Zeile unten auf gesperrten Karten (Preis oder Aufgabe)
var empty_text := "frei"  ## Text fuer einen freien Platz
var badge := ""  ## kleines Schild oben (z. B. "1" fuer Position 1)
var dim := false  ## blass (passt hier nicht)


func _init(p_id := "", min_size := Vector2(176, 248)) -> void:
	id = p_id
	custom_minimum_size = min_size
	focus_mode = Control.FOCUS_ALL
	flat = true
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func set_card(p_id: String) -> void:
	id = p_id
	queue_redraw()


func _box(c: Color, r: float, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(r))
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.anti_aliasing = true
	return sb


func _text(t: String, pos: Vector2, fs: int, c: Color, font: Font, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string(font, pos, t, align, w, fs, c)


func _draw() -> void:
	var s := size
	var k := s.x / 176.0  # alles skaliert mit der Kartenbreite
	var r := 14.0 * k
	var focused := has_focus() or is_hovered()
	if focused:
		var ring := _box(Color(0, 0, 0, 0), r + 4, UiTheme.INK, int(maxf(3.0, 3.0 * k)))
		draw_style_box(ring, Rect2(Vector2(-5, -5), s + Vector2(10, 10)))
	var pd: PlayerData = Club.card(id) if id != "" else null
	if pd == null:
		draw_style_box(_box(Color(1, 1, 1, 0.55), r, Color(UiTheme.INK, 0.18), 2), Rect2(Vector2.ZERO, s))
		var f := UiTheme.font_semibold
		_text(empty_text, Vector2(0, s.y * 0.5 + 6 * k), int(15 * k), UiTheme.INK_MUTED, f, HORIZONTAL_ALIGNMENT_CENTER, s.x)
		if badge != "":
			_text(badge, Vector2(12 * k, 24 * k), int(14 * k), UiTheme.INK_MUTED, f)
		return
	var tier := Club.tier(pd)
	var ink: Color = TIER_INK[tier]
	# Grund: zwei Toene (oben heller), matt, mit feiner Kante.
	draw_style_box(_box(TIER_BOTTOM[tier], r), Rect2(Vector2.ZERO, s))
	var top := _box(TIER_TOP[tier], r)
	top.corner_radius_bottom_left = 0
	top.corner_radius_bottom_right = 0
	draw_style_box(top, Rect2(Vector2.ZERO, Vector2(s.x, s.y * SPLIT)))
	draw_style_box(_box(Color(0, 0, 0, 0), r, Color(1, 1, 1, 0.35), 1), Rect2(Vector2(2, 2), s - Vector2(4, 4)))
	var fd := UiTheme.font_display
	var fsb := UiTheme.font_semibold
	var fm := UiTheme.font_medium
	# Wertung und Position oben links.
	_text(str(pd.overall()), Vector2(14 * k, 44 * k), int(38 * k), ink, fd)
	_text(ROLE_SHORT.get(pd.role, pd.role), Vector2(15 * k, 64 * k), int(14 * k), ink, fsb)
	if pd.left_handed:
		_text("Links", Vector2(15 * k, 82 * k), int(11 * k), Color(ink, 0.75), fm)
	# Trikot des Teams mit Rueckennummer oben rechts.
	var team := Club.origin(id)
	if team:
		_jersey(Rect2(Vector2(s.x - 86 * k, 12 * k), Vector2(74 * k, 84 * k)), team, pd.number)
	if badge != "":
		var bw := 26.0 * k
		draw_style_box(_box(UiTheme.INK, bw / 2), Rect2(Vector2(s.x * 0.5 - bw / 2, -10 * k), Vector2(bw, bw)))
		_text(badge, Vector2(s.x * 0.5 - bw / 2, -10 * k + bw * 0.7), int(13 * k), Color.WHITE, fsb, HORIZONTAL_ALIGNMENT_CENTER, bw)
	# Name.
	var name_y := s.y * SPLIT - 30 * k
	_text(pd.first_name, Vector2(0, name_y), int(12 * k), Color(ink, 0.8), fm, HORIZONTAL_ALIGNMENT_CENTER, s.x)
	var ln := pd.last_name
	var lfs := int(19 * k)
	while lfs > 10 and fd.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x > s.x - 16 * k:
		lfs -= 1
	_text(ln, Vector2(0, name_y + 21 * k), lfs, ink, fd, HORIZONTAL_ALIGNMENT_CENTER, s.x)
	# Untere Haelfte: Groesse, acht Staerken in zwei Spalten, Spielstile.
	var lo := Color(1, 1, 1, 0.95)
	var y0 := s.y * SPLIT + 18 * k
	_text(("%.2f m" % pd.height_m).replace(".", ","), Vector2(0, y0), int(13 * k), lo, fsb, HORIZONTAL_ALIGNMENT_CENTER, s.x)
	for i in STATS.size():
		var col := i / 4
		var row := i % 4
		var x := (16 + col * 80) * k
		var y := y0 + (19 + row * 16) * k
		var v := int(pd.get(STATS[i][0]))
		_text(str(v), Vector2(x, y), int(14 * k), lo, fd)
		_text(STATS[i][1], Vector2(x + 26 * k, y), int(12 * k), Color(lo, 0.8), fm)
	if pd.traits.size() > 0:
		var tr: Array = []
		for t in pd.traits:
			if t != "linkshaender":
				tr.append(PlayerData.TRAITS.get(t, t))
		if not tr.is_empty():
			var tt := " · ".join(tr)
			var tfs := int(11 * k)
			while tfs > 7 and fsb.get_string_size(tt, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x > s.x - 12 * k:
				tfs -= 1
			_text(tt, Vector2(0, s.y - 10 * k), tfs, lo, fsb, HORIZONTAL_ALIGNMENT_CENTER, s.x)
	if locked or dim:
		draw_style_box(_box(Color(UiTheme.PAPER, 0.62 if locked else 0.5), r), Rect2(Vector2.ZERO, s))
	if locked and note != "":
		var nh := 30.0 * k
		draw_style_box(_box(UiTheme.INK, 9 * k), Rect2(Vector2(10 * k, s.y * 0.5 - nh / 2), Vector2(s.x - 20 * k, nh)))
		var nfs := int(13 * k)
		while nfs > 7 and fsb.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x > s.x - 30 * k:
			nfs -= 1
		_text(note, Vector2(10 * k, s.y * 0.5 + nfs * 0.36), nfs, Color.WHITE, fsb, HORIZONTAL_ALIGNMENT_CENTER, s.x - 20 * k)


## Kleines Trikot in den Teamfarben (gleiche Form wie im Startmenue).
func _jersey(rect: Rect2, team: TeamStyle, number: int) -> void:
	var sc := minf(rect.size.x / 118.0, rect.size.y / 132.0)
	var off := rect.position + Vector2((rect.size.x - 118.0 * sc) / 2.0, (rect.size.y - 132.0 * sc) / 2.0)
	var pts := PackedVector2Array()
	var base := [Vector2(38, 26), Vector2(24, 30), Vector2(10, 48), Vector2(22, 58), Vector2(30, 50), Vector2(30, 112),
		Vector2(88, 112), Vector2(88, 50), Vector2(96, 58), Vector2(108, 48), Vector2(94, 30), Vector2(80, 26)]
	for q in base:
		pts.append(off + q * sc)
	for i in range(1, 8):
		var tt := i / 8.0
		var a := Vector2(80, 26).lerp(Vector2(59, 40), tt)
		var b := Vector2(59, 40).lerp(Vector2(38, 26), tt)
		pts.append(off + a.lerp(b, tt) * sc)
	var lib := Club.card(id) != null and Club.card(id).role == "L"
	draw_colored_polygon(pts, team.libero_jersey if lib else team.jersey)
	for strip in [[30, 60, 36, 112], [82, 60, 88, 112]]:
		draw_rect(Rect2(off + Vector2(strip[0], strip[1]) * sc, Vector2(strip[2] - strip[0], strip[3] - strip[1]) * sc),
			team.libero_panel if lib else team.panel)
	var f := UiTheme.font_display
	var fs := int(34.0 * sc)
	var txt := str(number)
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, off + Vector2(59.0 * sc - w / 2.0, 90.0 * sc), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		team.libero_number if lib else team.number)
