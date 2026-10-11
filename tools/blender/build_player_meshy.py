"""Baut die Spielerfigur aus Mattis' Meshy-Modell (Low-Poly Volleyball Player, CC BY 4.0).

Aufruf:  python build_player_meshy.py <meshy.blend> <ausgabe.glb> [vorschau_ordner]

Das Meshy-Modell ist ein einziges ungefaerbtes Netz in T-Haltung. Dieses Skript
  1. dreht es nach +Y (Blickrichtung des Spiels), stellt die Fuesse auf z = 0 und vereinfacht es,
  2. faerbt es nach Bereichen ueber die Materialnamen des Spiels (Haut, Haare, Trikot, Seitenteile,
     Kragen, Hose, Stutzen, Knieschoner, Schuhe), damit das Team-System es wie bisher einfaerbt,
  3. gibt ihm das Skelett mit den Gelenknamen aus scripts/figure.gd (Gewichte nach Lage am Koerper),
  4. senkt die Arme in die Ruhehaltung und schreibt player.glb plus player_markers.json.
Die Hilfsfunktionen (Materialien, Facetten, Skelett, Arme senken) kommen aus build_player.py.
"""
import json
import math
import os
import sys

import bpy  # zuerst: bmesh und mathutils kommen mit bpy
import bmesh
from mathutils import Vector

SRC = sys.argv[1]
OUT = sys.argv[2]
PREVIEW = sys.argv[3] if len(sys.argv) > 3 else ""
TARGET_TRIS = int(os.environ.get("TARGET_TRIS", "10000"))
HEAD_W = float(os.environ.get("HEAD_W", "0.998"))
BODY_W = float(os.environ.get("BODY_W", "1.0"))
INVERT = False
HERE = os.path.dirname(os.path.abspath(__file__))

bpy.ops.wm.open_mainfile(filepath=SRC)

# Hilfsfunktionen des bisherigen Skripts laden (ohne dessen main()).
_src = open(os.path.join(HERE, "build_player.py")).read().rsplit("\nmain()", 1)[0]
sys.argv = [sys.argv[0], OUT, PREVIEW]
ns = {"__name__": "build_player"}
exec(compile(_src, "build_player.py", "exec"), ns)
add_mat, facet, facet_colors, flat_shade = ns["add_mat"], ns["facet"], ns["facet_colors"], ns["flat_shade"]
surface_hit, logo, lower_arms = ns["surface_hit"], ns["logo"], ns["lower_arms"]


def sstep(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


# ------------------------------------------------------------------ Masse am Meshy-Modell
PEL = 1.02          # Hueftgelenk (wie bisher, das Spiel setzt die Hoehe danach)
SLEEVE_X = 0.365    # Aermelende (seitlich)
JERSEY_HEM = 1.034
SHORTS_HEM = 0.761
SHOE_TOP = 0.185
SOCK_TOP = 0.34
PAD_Z = (0.515, 0.675)
NECK_Z = 1.60
NECK_X = 0.085

BONES = [
    ("hips", (0, 0, PEL), (0, 0, 1.08), None),
    ("chest", (0, 0, 1.08), (0, 0, 1.58), "hips"),
    ("head", (0, 0, 1.645), (0, 0, 1.9), "chest"),
]
for _sd, _s in (("l", -1), ("r", 1)):
    BONES += [
        ("sh_" + _sd, (_s * 0.21, 0, 1.50), (_s * 0.52, 0, 1.495), "chest"),
        ("el_" + _sd, (_s * 0.52, 0, 1.495), (_s * 0.78, 0, 1.485), "sh_" + _sd),
        ("wr_" + _sd, (_s * 0.78, 0, 1.485), (_s * 0.95, 0, 1.48), "el_" + _sd),
        ("hip_" + _sd, (_s * 0.125, 0, 0.95), (_s * 0.14, 0, 0.52), "hips"),
        ("kn_" + _sd, (_s * 0.14, 0, 0.52), (_s * 0.165, 0, 0.095), "hip_" + _sd),
        ("an_" + _sd, (_s * 0.165, 0, 0.095), (_s * 0.165, 0.17, 0.02), "kn_" + _sd),
    ]
ns["BONES"] = BONES
ns["ARM_A"] = 0.0   # T-Haltung -> Arme um 88 Grad senken


# ------------------------------------------------------------------ Modell vorbereiten
for o in list(bpy.data.objects):
    if o.name != "mesh_node":
        bpy.data.objects.remove(o)
src_ob = bpy.data.objects["mesh_node"]
src_ob.location = (0, 0, 0)
src_ob.rotation_euler = (0, 0, 0)
src_ob.scale = (1, 1, 1)
for v in src_ob.data.vertices:
    # 180 Grad um Z (Meshy schaut nach -Y), Fuesse auf z = 0, Koerper mittig
    v.co = Vector((-v.co.x, -v.co.y + 0.045, v.co.z + 0.948))
src_ob.data.update()
# Kopf soll feiner bleiben als der Rest: Gewichtsgruppe steuert die Vereinfachung
vg_keep = src_ob.vertex_groups.new(name="keep")
for v in src_ob.data.vertices:
    vg_keep.add([v.index], HEAD_W if v.co.z > 1.62 else BODY_W, "REPLACE")
_dec = src_ob.modifiers.new("Dec", "DECIMATE")
_dec.decimate_type = "COLLAPSE"
_dec.ratio = float(os.environ.get("RATIO", "0.2"))
_dec.use_collapse_triangulate = True
_dec.vertex_group = "keep"
_dec.invert_vertex_group = INVERT
_dec.vertex_group_factor = 1.0
body = ns["evaluated_copy"](src_ob, "mesh_node")
print("KOPFDREIECKE", sum(1 for p in body.data.polygons if p.center.z > 1.65), "GESAMT", len(body.data.polygons))
body.name = "player"
body.data.name = "player"
for p in body.data.polygons:
    p.use_smooth = False


# ------------------------------------------------------------------ saubere Saeume: Schnittkanten
def cut(bm, co, no, region=None):
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    if region:
        fs = [f for f in bm.faces if region(f.calc_center_median())]
        geom = fs + list({e for f in fs for e in f.edges}) + list({v for f in fs for v in f.verts})
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector(co), plane_no=Vector(no))


_bm = bmesh.new()
_bm.from_mesh(body.data)
for z in (0.04, SHOE_TOP, SOCK_TOP, PAD_Z[0], PAD_Z[1], SHORTS_HEM, JERSEY_HEM, NECK_Z):
    cut(_bm, (0, 0, z), (0, 0, 1))
cut(_bm, (0, -0.075, 0), (0, 1, 0), lambda c: c.z < 0.19)
for sx in (-1, 1):
    cut(_bm, (sx * SLEEVE_X, 0, 0), (1, 0, 0), lambda c: c.z > 1.4)
    cut(_bm, (sx * NECK_X, 0, 0), (1, 0, 0), lambda c: 1.55 < c.z < 1.7 and abs(c.x) < 0.2)
bmesh.ops.triangulate(_bm, faces=_bm.faces[:])
_bm.to_mesh(body.data)
_bm.free()
body.data.update()
for p in body.data.polygons:
    p.use_smooth = False


# ------------------------------------------------------------------ Bereiche einfaerben
SLOTS = ["skin", "hair", "jersey", "panel", "collar", "shorts", "socks", "pads", "shoes", "accent", "sole", "logo"]
for name in SLOTS:
    add_mat(body, name)
SLOT = {n: i for i, n in enumerate(SLOTS)}


def is_hair(x, y, z):
    ax = abs(x)
    if z < 1.69:
        return False
    if y > 0.03:                       # Gesicht: Haare erst ab der Stirn
        return z > 1.835
    if ax > 0.07 or y < -0.02:         # Seiten und Hinterkopf
        return z > 1.765 or (y < -0.04 and z > 1.715)
    return z > 1.83


def classify(c, n):
    x, y, z = c
    ax = abs(x)
    if z < SHOE_TOP:
        if z < 0.04:
            return "sole"
        if y < -0.075:
            return "accent"
        return "shoes"
    if z < SOCK_TOP:
        return "socks"
    if PAD_Z[0] < z < PAD_Z[1] and n.y > -0.4:
        return "pads"
    if z < JERSEY_HEM - 0.004:
        return "shorts" if z >= SHORTS_HEM else "skin"
    if z < 1.625 and ax < SLEEVE_X and not (ax < NECK_X and z > NECK_Z):
        if abs(n.x) > 0.75 and z < 1.40 and ax < 0.2:
            return "panel"
        return "jersey"
    if z >= 1.625 and is_hair(x, y, z):
        return "hair"
    return "skin"


me = body.data
for p in me.polygons:
    p.material_index = SLOT[classify(p.center, p.normal)]


# ------------------------------------------------------------------ Gewichte
names = [b[0] for b in BONES]
groups = {n: body.vertex_groups.new(name=n) for n in names}


def weights(x, y, z):
    ax = abs(x)
    s = "r" if x > 0 else "l"
    if z < 1.03:                                   # Becken und Beine
        h = sstep(1.03, 0.88, z)
        k = sstep(0.58, 0.46, z)
        a = sstep(0.20, 0.12, z)
        return {"hips": 1 - h, "hip_" + s: h * (1 - k), "kn_" + s: k * (1 - a), "an_" + s: a}
    sh = sstep(1.0, 1.17, z)
    hd = sstep(1.60, 1.66, z) if ax < 0.14 else 0.0
    w = {"hips": 1 - sh, "chest": sh * (1 - hd), "head": hd}
    if z > 1.36 and ax > 0.14:                     # Arm
        a = sstep(0.13, 0.30, ax)
        e = sstep(0.47, 0.55, ax)
        wr = sstep(0.74, 0.82, ax)
        w = {k: v * (1 - a) for k, v in w.items()}
        w["sh_" + s] = a * (1 - e)
        w["el_" + s] = a * e * (1 - wr)
        w["wr_" + s] = a * wr
    return w


for v in me.vertices:
    w = weights(*v.co)
    tot = sum(w.values())
    for n, val in w.items():
        if val / tot > 0.005:
            groups[n].add([v.index], val / tot, "REPLACE")


# ------------------------------------------------------------------ Logos und Nummern-Marken
def gd(v):
    return [round(v.x, 4), round(v.z, 4), round(-v.y, 4)]


extra = []
for name, origin, bone, size in (("logo_chest", (-0.085, 0.6, 1.43), "chest", 0.04), ("logo_shorts", (0.11, 0.6, 0.80), "hip_r", 0.034)):
    loc, n = surface_hit(body, origin, (0, -1, 0))
    lg = logo(name, loc, n, size)
    vg = lg.vertex_groups.new(name=bone)
    vg.add([v.index for v in lg.data.vertices], 1.0, "REPLACE")
    extra.append(lg)
markers = {}
for key, origin, direction, bone in [
    ("num_front", (0, 0.6, 1.33), (0, -1, 0), "chest"),
    ("num_back", (0, -0.6, 1.36), (0, 1, 0), "chest"),
    ("num_shorts", (-0.11, 0.6, 0.83), (0, -1, 0), "hip_l"),
]:
    loc, n = surface_hit(body, origin, direction)
    markers[key] = {"bone": bone, "pos": gd(loc), "normal": gd(n)}


def render_preview(tag):
    if not PREVIEW:
        return
    scn = bpy.context.scene
    if scn.camera is None:
        scn.world = None   # das alte Skript baut dann Licht und Kamera selbst
    ns["render_preview"](PREVIEW, tag)


facet_colors(body)
render_preview("tpose")

# ------------------------------------------------------------------ Skelett, Arme senken, Export
for lg in extra:
    for p in lg.data.polygons:
        p.use_smooth = False
bpy.ops.object.select_all(action="DESELECT")
for lg in extra:
    lg.select_set(True)
body.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = "player"
facet_colors(body)
flat_shade([body])

rig = ns["build_armature"]()
body.parent = rig
mod = body.modifiers.new("Armature", "ARMATURE")
mod.object = rig
lower_arms(rig, [body])
render_preview("rest")

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False,
                          export_apply=False, export_animations=False, export_skins=True,
                          export_yup=True, export_def_bones=False,
                          export_vertex_color="ACTIVE", export_all_vertex_colors=False)
with open(OUT.rsplit(".", 1)[0] + "_markers.json", "w") as f:
    json.dump(markers, f, indent=1)
tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
print("FERTIG", OUT, "Dreiecke:", tris)
