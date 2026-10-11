class_name HitFx
extends Node3D
## Dezente Treffer-Effekte: Staubwolke und Abdruck am Boden, kurzer Lichtblitz am Ball.
## Laufen in Spielzeit, werden also in der Zeitlupe mit langsamer.

var _dust_mat: StandardMaterial3D
var _flash_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _spark_mat: StandardMaterial3D
var _glow: ImageTexture


func _ready() -> void:
	_glow = _radial_texture()
	_dust_mat = StandardMaterial3D.new()
	_dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_dust_mat.vertex_color_use_as_albedo = true
	_dust_mat.albedo_texture = _glow
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flash_mat.no_depth_test = true
	_flash_mat.albedo_texture = _glow
	_spark_mat = _flash_mat.duplicate()
	_spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_spark_mat.vertex_color_use_as_albedo = true
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(1, 1, 1, 0.5)


## Weicher runder Fleck (weiss in der Mitte, aussen durchsichtig) fuer Staub und Blitz.
func _radial_texture() -> ImageTexture:
	var sz := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y in sz:
		for x in sz:
			var d := Vector2(x - sz / 2.0 + 0.5, y - sz / 2.0 + 0.5).length() / (sz / 2.0)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


## Ball schlaegt auf: Staub und ein kurzer Abdruck. strength 0..1 (harter Angriff = 1).
func dust(pos: Vector3, strength: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = int(lerpf(8.0, 26.0, strength))
	p.lifetime = lerpf(0.45, 0.8, strength)
	var q := QuadMesh.new()
	q.size = Vector2(0.28, 0.28)
	q.material = _dust_mat
	p.mesh = q
	p.direction = Vector3.UP
	p.spread = 80.0
	p.gravity = Vector3(0, -2.5, 0)
	p.initial_velocity_min = lerpf(0.5, 1.2, strength)
	p.initial_velocity_max = lerpf(1.2, 3.0, strength)
	p.damping_min = 2.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = lerpf(1.2, 2.2, strength)
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 1.3))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.92, 0.85, 0.75, 0.55))
	grad.set_color(1, Color(0.92, 0.85, 0.75, 0.0))
	p.color_ramp = grad
	add_child(p)
	p.position = Vector3(pos.x, 0.05, pos.z)
	p.emitting = true
	_free_later(p, p.lifetime + 0.3)
	# Abdruck: flacher Ring, der sich ausbreitet und verblasst.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.16
	tm.outer_radius = 0.2
	ring.mesh = tm
	ring.material_override = _ring_mat.duplicate()
	ring.scale = Vector3(1, 0.05, 1)
	add_child(ring)
	ring.position = Vector3(pos.x, 0.02, pos.z)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	var grow := lerpf(2.5, 5.0, strength)
	tw.tween_property(ring, "scale", Vector3(grow, 0.05, grow), 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(ring.material_override, "albedo_color:a", 0.0, 0.45)
	tw.chain().tween_callback(ring.queue_free)


## Harter Kontakt (Angriff, Sprungaufschlag, Block): kurzer heller Blitz am Ball.
func flash(pos: Vector3, strength: float, tint := Color(1.0, 0.95, 0.8)) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mi.mesh = q
	var m: StandardMaterial3D = _flash_mat.duplicate()
	m.albedo_color = Color(tint.r, tint.g, tint.b, lerpf(0.5, 0.95, strength))
	mi.material_override = m
	add_child(mi)
	mi.position = pos
	var s0 := lerpf(0.25, 0.45, strength)
	var s1 := lerpf(0.8, 1.6, strength)
	mi.scale = Vector3.ONE * s0
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * s1, 0.14).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.16)
	tw.chain().tween_callback(mi.queue_free)
	if strength > 0.6:
		_sparks(pos, strength, tint)


func _sparks(pos: Vector3, strength: float, tint: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = int(lerpf(6.0, 12.0, strength))
	p.lifetime = 0.25
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	q.material = _spark_mat
	p.mesh = q
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 4.5
	var grad := Gradient.new()
	grad.set_color(0, Color(tint.r, tint.g, tint.b, 0.9))
	grad.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
	p.color_ramp = grad
	add_child(p)
	p.position = pos
	p.emitting = true
	_free_later(p, 0.6)


func _free_later(n: Node, secs: float) -> void:
	get_tree().create_timer(secs, false).timeout.connect(n.queue_free)
