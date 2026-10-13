"""Baut die Netzanlage aus Mattis' Meshy-Modell (Netz mit Pfosten, Polstern und Antennen).

Aufruf:  python build_net_meshy.py <meshy_netz.glb> <ausgabe.glb>

Das Meshy-Modell ist ~1,9 Einheiten breit und liegt entlang Blender-X. Dieses Skript
  1. bringt es auf echte Masse: Netzoberkante 2,43 m, Antennen bei +-4,5 m (ueber den
     Seitenlinien), Pfosten bei +-5,6 m. Netzfeld wird dafuer waagerecht gestreckt,
     Pfosten und Antennen behalten ihre Proportionen,
  2. dreht es so, dass das Netz in Godot entlang z steht (Netzebene x = 0),
  3. vereinfacht das Netz (338k -> ~85k Dreiecke) und verkleinert die Texturen.
Bewegt wird das Netz im Spiel per Shader (scripts/net.gd), nicht ueber ein Skelett.
"""
import sys

import bpy

SRC, OUT = sys.argv[1], sys.argv[2]
RATIO = 0.25

FLOOR, NET_TOP = -0.4354, 0.2209     # Hoehen im Meshy-Modell
S = 2.43 / (NET_TOP - FLOOR)          # Massstab fuer Hoehe, Tiefe, Pfosten, Antennen
# Stuetzpunkte |x| Meshy -> |z| Spiel: Netzfeld gestreckt, Antenne und Pfosten in Masstab S
ANT, POST = 0.794, 0.9064
KNOTS = [(0.0, 0.0), (ANT - 0.019, 4.5 - 0.019 * S), (ANT + 0.019, 4.5 + 0.019 * S),
         (0.861, 5.6 - (POST - 0.861) * S), (0.96, 5.6 + (0.96 - POST) * S)]


def map_x(x):
    a = abs(x)
    for (x0, z0), (x1, z1) in zip(KNOTS, KNOTS[1:]):
        if a <= x1 or (x1, z1) == KNOTS[-1]:
            return (z0 + (a - x0) / (x1 - x0) * (z1 - z0)) * (1 if x >= 0 else -1)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
ob = [o for o in bpy.data.objects if o.type == "MESH"][0]
ob.name = ob.data.name = "net_meshy"
# Meshy-Laenge (X) -> Spiel z = Blender -Y; Meshy-Tiefe (Y) -> Spiel x = Blender X
for v in ob.data.vertices:
    c = ob.matrix_world @ v.co
    v.co = (c.y * S, -map_x(c.x), (c.z - FLOOR) * S)
ob.matrix_world.identity()
ob.data.update()

dec = ob.modifiers.new("Dec", "DECIMATE")
dec.ratio = RATIO
bpy.context.view_layer.objects.active = ob
bpy.ops.object.modifier_apply(modifier="Dec")
print("DREIECKE", sum(len(p.vertices) - 2 for p in ob.data.polygons))

for im in bpy.data.images:
    if im.size[0] > 2048:
        im.scale(2048, 2048)
mat = ob.data.materials[0]
mat.name = "net_meshy"
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False,
                          export_image_format="JPEG", export_jpeg_quality=88, export_apply=True)
