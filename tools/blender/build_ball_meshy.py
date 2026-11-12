"""Baut den Ball aus Mattis' Meshy-Modell (Volleyball, gelb-blau-weiss).

Aufruf:  python build_ball_meshy.py <meshy_ball.glb> <ausgabe.glb>

Mittelpunkt auf 0, Radius 10,5 cm (Spiel zeichnet ihn etwas groesser), Textur 1024 px.
"""
import sys

import bpy

SRC, OUT = sys.argv[1], sys.argv[2]
R = 0.105

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
ob = [o for o in bpy.data.objects if o.type == "MESH"][0]
ob.name = ob.data.name = "ball"
pts = [ob.matrix_world @ v.co for v in ob.data.vertices]
lo = [min(p[i] for p in pts) for i in range(3)]
hi = [max(p[i] for p in pts) for i in range(3)]
mid = [(a + b) / 2 for a, b in zip(lo, hi)]
s = R / (max(b - a for a, b in zip(lo, hi)) / 2)
for v, p in zip(ob.data.vertices, pts):
    v.co = ((p[0] - mid[0]) * s, (p[1] - mid[1]) * s, (p[2] - mid[2]) * s)
ob.matrix_world.identity()
ob.data.update()
for im in bpy.data.images:
    if im.size[0] > 1024:
        im.scale(1024, 1024)
ob.data.materials[0].name = "ball_meshy"
print("DREIECKE", sum(len(p.vertices) - 2 for p in ob.data.polygons))
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_image_format="JPEG", export_jpeg_quality=90)
