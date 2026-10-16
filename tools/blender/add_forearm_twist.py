"""Unterarm-Drehknochen fuer die Spielfigur (nach add_finger_bones.py ausfuehren).

Aufruf:  python add_forearm_twist.py <player.glb> <ausgabe.glb>

Beim Menschen dreht sich die Hand (Pronation/Supination) nicht im Handgelenk, sondern im Unterarm:
Elle und Speiche drehen sich umeinander, die Drehung nimmt vom Ellbogen zum Handgelenk hin zu. Das
Modell hatte dafuer keinen Knochen, jede Handdrehung verdrillte die Haut direkt am Handgelenk. Das
Skript
  1. legt je Arm einen Knochen fa_l/fa_r vom Ellbogen zum Handgelenk an (Kind von el, gleiche Lage),
     die Hand (wr) haengt danach an fa statt an el,
  2. gibt jedem Unterarmpunkt einen Anteil an fa, der vom Ellbogen (0) zum Handgelenk (1) waechst.
     Dreht das Spiel fa um die Unterarmachse, verdrillt sich der Unterarm also gleichmaessig.
"""
import sys

import bpy
from mathutils import Vector

SRC, OUT = sys.argv[1], sys.argv[2]


def smoothstep(a: float, b: float, x: float) -> float:
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
body = bpy.data.objects["player"] if "player" in bpy.data.objects else next(
    o for o in bpy.data.objects if o.type == "MESH" and "wr_r" in o.vertex_groups)
assert "fa_r" not in rig.data.bones, "Unterarmknochen gibt es schon"

bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
eb = rig.data.edit_bones
seg = {}
for sd in ("l", "r"):
    el, wr = eb["el_" + sd], eb["wr_" + sd]
    fa = eb.new("fa_" + sd)
    fa.head = el.head.copy()
    fa.tail = el.tail.copy()
    fa.roll = el.roll
    fa.parent = el
    fa.use_connect = False
    wr.use_connect = False
    wr.parent = fa
    seg[sd] = (rig.matrix_world @ el.head, rig.matrix_world @ el.tail)
bpy.ops.object.mode_set(mode="OBJECT")

mw = body.matrix_world
moved = {}
for sd in ("l", "r"):
    a, b = seg[sd]
    ab = b - a
    ge = body.vertex_groups["el_" + sd]
    gf = body.vertex_groups.new(name="fa_" + sd)
    n = 0
    for v in body.data.vertices:
        we = next((g.weight for g in v.groups if g.group == ge.index), 0.0)
        if we <= 0.0:
            continue
        t = (mw @ v.co - a).dot(ab) / ab.length_squared
        # Am Ellbogen dreht nichts mit, zum Handgelenk hin alles (Speiche dreht sich um die Elle)
        k = smoothstep(0.08, 1.0, t)
        if k <= 0.0:
            continue
        gf.add([v.index], we * k, "REPLACE")
        if we * (1.0 - k) > 1e-4:
            ge.add([v.index], we * (1.0 - k), "REPLACE")
        else:
            ge.remove([v.index])
        n += 1
    moved[sd] = n
print("UNTERARM", moved)

bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False,
                          export_apply=False, export_animations=False, export_skins=True,
                          export_yup=True, export_def_bones=False,
                          export_vertex_color="ACTIVE", export_all_vertex_colors=False)
