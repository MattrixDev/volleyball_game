class_name ReactiveNet
extends Node3D
## Netzanlage aus Mattis' Meshy-Modell (assets/models/net_meshy.glb, gebaut mit
## tools/blender/build_net_meshy.py). Fliegt der Ball ins Netz, beult es per Shader aus
## (assets/shaders/net.gdshader) und schwingt nach. Bis zu 4 Treffer gleichzeitig.

const MODEL := preload("res://assets/models/net_meshy.glb")
const SHADER := preload("res://assets/shaders/net.gdshader")

var _mat: ShaderMaterial
var _hits: Array[Vector4] = []
var _next := 0
var _t := 0.0


func _ready() -> void:
	for k in 4:
		_hits.append(Vector4(0, 0, -100, 0))
	var src: Node3D = MODEL.instantiate()
	add_child(src)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	for mi in src.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var sm := m.mesh.surface_get_material(0) as StandardMaterial3D
		if sm:
			_mat.set_shader_parameter("albedo_tex", sm.albedo_texture)
			_mat.set_shader_parameter("normal_tex", sm.normal_texture)
			_mat.set_shader_parameter("mr_tex", sm.roughness_texture)
		m.material_override = _mat
		# Ausbeulen geht ueber die Modellgrenzen hinaus: groessere Box gegen Wegschneiden
		m.custom_aabb = m.mesh.get_aabb().grow(0.8)
	_mat.set_shader_parameter("hits", _hits)


## Ball trifft das Netz bei pos (Netzebene), staerke 0..1, richtung +1/-1 (Welt-x).
func hit(pos: Vector3, strength: float, direction: float) -> void:
	_hits[_next] = Vector4(pos.z, pos.y, _t, direction * lerpf(0.08, 0.38, clampf(strength, 0.0, 1.0)))
	_next = (_next + 1) % _hits.size()
	_mat.set_shader_parameter("hits", _hits)


func _process(delta: float) -> void:
	_t += delta
	_mat.set_shader_parameter("now", _t)
