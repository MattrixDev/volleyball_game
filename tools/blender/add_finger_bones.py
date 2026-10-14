"""Fingerknochen fuer die Spielfigur: Daumen und vier Finger, je zwei Glieder pro Hand.

Aufruf:  python add_finger_bones.py <player.glb> <ausgabe.glb> [--test-curl GRAD]

Das Meshy-Modell hat ausmodellierte Finger, aber nur einen Handknochen (wr_l/wr_r). Das Skript
  1. findet die Finger in der Geometrie (Handgewicht > 0,5, unterhalb der Knoechel; nach der
     Seitenlage gruppiert) und legt durch jeden Finger eine Achse (Hauptrichtung der Punkte),
  2. setzt pro Finger zwei Knochen (Grundglied ab dem Knoechel, Mittel-+Endglied ab dem
     Mittelgelenk) und zwei Daumenknochen (Sattelgelenk -> Grundgelenk -> Spitze),
  3. verteilt das bisherige Handgewicht jedes Punkts auf Mittelhand und Fingerglieder: je
     naeher ein Punkt an einem Knochenstueck liegt, desto mehr gehoert er dazu (weich an den Gelenken),
  4. schreibt die glb wieder heraus (gleiche Exportoptionen wie build_figure_rigged.py).
Die Knochen heissen th1_r, th2_r, ix1_r, ix2_r, md1_r, ... (Daumen, Zeige-, Mittel-, Ring-, kleiner Finger).
--test-curl beugt alle Finger zum Test und speichert die Punkte als <ausgabe>_curl.npy.
"""
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

SRC, OUT = sys.argv[1], sys.argv[2]
TEST = float(sys.argv[sys.argv.index("--test-curl") + 1]) if "--test-curl" in sys.argv else None
FINGERS = ["ix", "md", "rg", "pk"]
Y0 = [-0.068, -0.052, -0.032, -0.009]  # Startwerte der Seitenlage (rechte Hand, Blender-Koordinaten)
KNUCKLE_Z = 0.948  # Hoehe der Fingerknoechel bei haengendem Arm
KNUCKLE_Y = [-0.066, -0.047, -0.027, -0.008]  # Seitenlage der Knoechel (Zeige- und Mittelfinger liegen unten eng)
PIP_T = 0.47  # Mittelgelenk: Anteil der Strecke Knoechel -> Fingerspitze
# Daumen (rechte Hand): Sattelgelenk, Grundgelenk, Spitze
THUMB = [Vector((0.200, -0.064, 1.030)), Vector((0.190, -0.083, 0.988)), Vector((0.182, -0.090, 0.946))]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
body = bpy.data.objects["player"] if "player" in bpy.data.objects else next(
    o for o in bpy.data.objects if o.type == "MESH" and "wr_r" in o.vertex_groups)
mw = body.matrix_world
mwi = mw.inverted()
V = np.array([list(mw @ v.co) for v in body.data.vertices])


def seg_dist(p, a, b):
    ab = b - a
    t = np.clip(((p - a) @ ab) / max(ab @ ab, 1e-9), 0.0, 1.0)
    return np.linalg.norm(p - (a + t[:, None] * ab), axis=1)


bones = {}  # name -> (head, tail, parent)
new_w = {}  # name -> {vertex index: weight}
for sd, sx in (("r", 1.0), ("l", -1.0)):
    mir = np.array([sx, 1.0, 1.0])
    vg = body.vertex_groups["wr_" + sd]
    hand_w = np.zeros(len(V))
    for v in body.data.vertices:
        for g in v.groups:
            if g.group == vg.index:
                hand_w[v.index] = g.weight
    idx = np.nonzero(hand_w > 0.0)[0]
    P = V[idx] * mir  # in Koordinaten der rechten Hand
    wr_head = np.array(list(rig.matrix_world @ rig.data.bones["wr_" + sd].head_local)) * mir
    # Finger: Punkte unterhalb der Knoechel nach der Seitenlage gruppieren
    sel = (P[:, 2] < 0.915) & (P[:, 1] > -0.082) & (hand_w[idx] > 0.5)
    F = P[sel]
    c = np.array(Y0)
    for _ in range(25):
        lab = np.argmin(np.abs(F[:, 1:2] - c[None]), axis=1)
        c = np.array([F[lab == k, 1].mean() if (lab == k).any() else c[k] for k in range(4)])
    segs = []  # (name, a, b)
    chain = {}
    for k, fn in enumerate(FINGERS):
        G = F[lab == k]
        m = G.mean(axis=0)
        _u, _s, vt = np.linalg.svd(G - m)
        d = vt[0] if vt[0][2] < 0 else -vt[0]  # zeigt nach unten (Richtung Fingerspitze)
        tip = m + d * ((G - m) @ d).max()
        mcp = m + d * ((KNUCKLE_Z - m[2]) / d[2])
        mcp[1] = KNUCKLE_Y[k]
        pip = mcp + (tip - mcp) * PIP_T
        chain[fn] = (mcp, pip, tip)
        segs += [("wr", wr_head, mcp), (fn + "1", mcp, pip), (fn + "2", pip, tip)]
    th = [np.array(list(p)) for p in THUMB]
    chain["th"] = tuple(th)
    segs += [("wr", wr_head, th[0]), ("th1", th[0], th[1]), ("th2", th[1], th[2])]
    # Gewichte: Abstand zu jedem Knochenstueck, weich gemischt (Temperatur 4 mm)
    D = np.stack([seg_dist(P, a, b) for _n, a, b in segs], axis=1)
    names = [n for n, _a, _b in segs]
    uniq = sorted(set(names))
    S = np.exp(-(D - D.min(axis=1, keepdims=True)) / 0.004)
    share = {u: np.zeros(len(P)) for u in uniq}
    for col, n in enumerate(names):
        share[n] = np.maximum(share[n], S[:, col])
    tot = sum(share.values())
    for u in uniq:
        if u == "wr":
            continue
        name = u + "_" + sd
        frac = share[u] / tot * hand_w[idx]
        new_w[name] = {int(i): float(f) for i, f in zip(idx, frac) if f > 0.01}
    wr_frac = share["wr"] / tot * hand_w[idx]
    for i, f in zip(idx, wr_frac):
        vg.add([int(i)], float(f), "REPLACE")
    for fn, (a, b, cpt) in chain.items():
        bones[fn + "1_" + sd] = (Vector(a * mir), Vector(b * mir), "wr_" + sd)
        bones[fn + "2_" + sd] = (Vector(b * mir), Vector(cpt * mir), fn + "1_" + sd)
    print("HAND", sd, {fn: [list(np.round(p * mir, 3)) for p in ch] for fn, ch in chain.items()})

# Knochen anlegen (Armatur-Raum)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
ri = rig.matrix_world.inverted()
eb = rig.data.edit_bones
for name, (h, t, par) in bones.items():
    b = eb.new(name)
    b.head = ri @ h
    b.tail = ri @ t
    b.roll = 0.0
    b.parent = eb[par]
    b.use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")
for name, ws in new_w.items():
    g = body.vertex_groups.get(name) or body.vertex_groups.new(name=name)
    for i, w in ws.items():
        g.add([i], w, "REPLACE")
print("KNOCHEN", len(bones), "GEWICHTE", {k: len(v) for k, v in new_w.items()})

if TEST is not None:
    import math
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    for name in sorted(bones, key=lambda n: n[2]):  # erst Grundglieder, dann Endglieder
        pb = rig.pose.bones[name]
        axis = Vector((0, 1, 0)) if name.endswith("_r") else Vector((0, -1, 0))
        if name.startswith("th"):
            axis = Vector((0, 0, 1)) if name.endswith("_r") else Vector((0, 0, -1))
        h = pb.head.copy()
        rot = Matrix.Rotation(math.radians(TEST), 4, axis)
        pb.matrix = Matrix.Translation(h) @ rot @ Matrix.Translation(-h) @ pb.matrix
        bpy.context.view_layer.update()
    bpy.ops.object.mode_set(mode="OBJECT")
    dg = bpy.context.evaluated_depsgraph_get()
    me = body.evaluated_get(dg).to_mesh()
    np.save(OUT.rsplit(".", 1)[0] + "_curl.npy", np.array([list(mw @ v.co) for v in me.vertices]))
    sys.exit(0)

bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False,
                          export_apply=False, export_animations=False, export_skins=True,
                          export_yup=True, export_def_bones=False,
                          export_vertex_color="ACTIVE", export_all_vertex_colors=False)
