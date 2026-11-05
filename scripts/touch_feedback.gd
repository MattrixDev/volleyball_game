class_name TouchFeedback
extends Node
## Feedback zum Timing ohne Text (Zwischenziel A, 05.11.2026): nach jedem eigenen Kontakt sagen
## Controller, Ton und ein kurzer Ring am Boden, wie gut er war.
##   perfekt:  kurzes, knackiges Rumble, heller Zusatzton, weisser Ring, der aufgeht
##   gut:      weiches Rumble, sonst nichts Besonderes
##   schwach / daneben: dumpfes, doppeltes Rumble, tiefer Ton, orangeroter Ring
## Fuer Koenner zeigt ein kleiner Timing-Strich unter dem Spieler eine halbe Sekunde lang, ob
## der Kontakt frueh (links) oder spaet (rechts) war. Abschaltbar unter Hilfen ("Timing-Strich").

const Q_PERFECT := 0
const Q_GOOD := 1
const Q_WEAK := 2
const STRIP_SECS := 0.7

var match_node
var sfx: SoundBank
var camera: Camera3D
var rumble: Callable  # func(weak, strong, secs)

var _layer: CanvasLayer
var _strip: Control
var _strip_until := 0.0
var _strip_x := 0.0  # -1 = viel zu frueh, 0 = genau, 1 = viel zu spaet
var _strip_col := Color.WHITE
var _strip_pl: Node3D = null
var _rings: Array = []


func setup(m, bank: SoundBank, cam: Camera3D, rumble_fn: Callable) -> void:
	match_node = m
	sfx = bank
	camera = cam
	rumble = rumble_fn
	m.touch_result.connect(_on_touch)
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)
	_strip = Control.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.size = Vector2(84, 14)
	_strip.draw.connect(_draw_strip)
	_strip.visible = false
	_layer.add_child(_strip)


func _quiet() -> bool:
	return match_node == null or match_node.autoplay or match_node.attract or match_node.human_team < 0


func _on_touch(kind: String, team: int, human: bool, q: int, e: float, _speed: float, _speed_in: float) -> void:
	if not human or team != match_node.human_team or _quiet():
		return
	var pl: Node3D = match_node.server() if kind == "serve" else (match_node.opp.player if match_node.opp != null else null)
	match q:
		Q_PERFECT:
			rumble.call(0.0, 0.85, 0.07)
			sfx.play("set", 0.35, 1.45)  # heller, sauberer Zusatzton
		Q_GOOD:
			rumble.call(0.3, 0.0, 0.06)
		_:
			rumble.call(0.75, 0.15, 0.1)
			get_tree().create_timer(0.14, true, false, true).timeout.connect(func(): rumble.call(0.6, 0.0, 0.1))
			sfx.play("bump", 0.45, 0.72)  # dumpf
	if pl != null:
		_ring(pl.global_position, q)
		if match_node.cfg.assisted("timing_bar"):
			var w: Array = match_node.windows(kind)
			var span: float = maxf(float(w[2]), 0.05)
			_strip_x = clampf(e / span, -1.0, 1.0) if q != Q_PERFECT else 0.0
			_strip_col = [Color(1, 1, 1), Color(0.6, 0.95, 0.6), Color(1.0, 0.62, 0.3), Color(1.0, 0.35, 0.3)][clampi(q, 0, 3)]
			_strip_pl = pl
			_strip_until = _now() + STRIP_SECS


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Ring am Boden, der kurz aufgeht und verblasst (kein Leuchten, keine Spur).
func _ring(pos: Vector3, q: int) -> void:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.56
	torus.rings = 32
	torus.ring_segments = 4
	mi.mesh = torus
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var c: Color = Color(1, 1, 1, 0.9) if q == Q_PERFECT else (Color(1.0, 0.95, 0.6, 0.5) if q == Q_GOOD else Color(1.0, 0.45, 0.2, 0.75))
	mat.albedo_color = c
	mi.material_override = mat
	mi.scale = Vector3(1, 0.1, 1)
	match_node.add_child(mi)
	mi.global_position = Vector3(pos.x, 0.03, pos.z)
	var grow := 1.7 if q == Q_PERFECT else 1.3
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(grow, 0.1, grow), 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.45).set_delay(0.1)
	tw.chain().tween_callback(mi.queue_free)


func _process(_delta: float) -> void:
	if _strip == null:
		return
	var left := _strip_until - _now()
	var show := left > 0.0 and is_instance_valid(_strip_pl) and camera != null \
			and not camera.is_position_behind(_strip_pl.global_position)
	_strip.visible = show
	if not show:
		return
	var sp := camera.unproject_position(_strip_pl.global_position)
	_strip.position = sp + Vector2(-_strip.size.x * 0.5, 18.0)
	_strip.modulate.a = clampf(left / 0.25, 0.0, 1.0)
	_strip.queue_redraw()


func _draw_strip() -> void:
	var w := _strip.size.x
	var h := 6.0
	var y := (_strip.size.y - h) * 0.5
	_strip.draw_rect(Rect2(0, y, w, h), Color(0.05, 0.06, 0.08, 0.55))
	_strip.draw_rect(Rect2(w * 0.5 - 1.0, y - 2.0, 2.0, h + 4.0), Color(1, 1, 1, 0.8))
	var x := w * 0.5 + _strip_x * (w * 0.5 - 4.0)
	_strip.draw_rect(Rect2(x - 3.0, y - 3.0, 6.0, h + 6.0), _strip_col)
