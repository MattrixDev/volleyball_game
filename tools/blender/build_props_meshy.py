"""Baut Linienrichterfahne und Schiedsrichterstuhl aus Mattis' Meshy-Modellen.

Aufruf:  python build_props_meshy.py <fahne.glb> <stuhl.glb> <ausgabe_ordner>

flag.glb: Ursprung = Griff, Stab entlang +y (Spiel-Koordinaten), Tuch haengt weiter in +y,
  wie die alte Fahne (arena.gd haengt sie an die rechte Hand und dreht sie nach unten).
referee_stand.glb: Plattform-Oberkante 1,46 m (dort steht der Schiedsrichter), Plattform
  mittig im Ursprung, Leiter hinten (-z), Polster vorn zum Feld (+z).
"""
import sys

import bpy

FLAG, STAND, OUTDIR = sys.argv[1], sys.argv[2], sys.argv[3]


def load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    ob = [o for o in bpy.data.objects if o.type == "MESH"][0]
    pts = [ob.matrix_world @ v.co for v in ob.data.vertices]
    return ob, pts


def finish(ob, pts, fn, name, ratio, tex):
    # fn: Meshy (x, y, z) -> Blender-Ausgabe (x, y, z); Export macht daraus Godot (x, z, -y)
    for v, p in zip(ob.data.vertices, pts):
        v.co = fn(p)
    ob.matrix_world.identity()
    ob.data.update()
    ob.name = ob.data.name = name
    if ratio < 1.0:
        dec = ob.modifiers.new("Dec", "DECIMATE")
        dec.ratio = ratio
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier="Dec")
    for im in bpy.data.images:
        if im.size[0] > tex:
            im.scale(tex, tex)
    print(name, "Dreiecke", sum(len(p.vertices) - 2 for p in ob.data.polygons))
    bpy.ops.export_scene.gltf(filepath=f"{OUTDIR}/{name}.glb", export_format="GLB",
                              export_image_format="JPEG", export_jpeg_quality=88)


# Fahne: Griff bei z = 0,72 (Meshy, Hoehe 1,9), Tuch darunter. 0,42 m pro Meshy-Einheit.
S = 0.42
ob, pts = load(FLAG)
finish(ob, pts, lambda p: ((p.x) * S, -(p.y) * S, (0.72 - p.z) * S), "flag", 0.15, 1024)

# Stuhl: Plattform bei z = 0,56, Boden bei -0,952 -> Plattform 1,46 m. Leiter liegt bei Meshy -y,
# muss im Spiel hinten (-z) liegen: Meshy -y -> Blender +y (= Godot -z), also um 180 Grad drehen.
ob, pts = load(STAND)
k = 1.46 / (0.56 + 0.952)
cy = 0.045
finish(ob, pts, lambda p: (-p.x * k, -(p.y - cy) * k, (p.z + 0.952) * k), "referee_stand", 0.12, 2048)
