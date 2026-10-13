"""Baut eine Spielfigur aus Mattis' geriggtem Meshy-Modell (Spieler oder Schiedsrichter).

Aufruf:  python build_figure_rigged.py <player|official> <ausgabe.glb> <clip.glb> [clip.glb ...]

Jede clip.glb ist dieselbe Figur mit einer Animation (Meshy: Walking, Running, ...).
Das Skript
  1. dreht die Figur nach +Y (Blickrichtung des Spiels) und senkt die Arme in die Ruhehaltung
     des Spiels (Arme haengen, 2 Grad vom Koerper weg),
  2. setzt das Spiel-Skelett (15 Gelenke wie in scripts/figure.gd) an die Gelenke des
     Meshy-Skeletts und uebernimmt dessen Gewichte (Wirbelsaeule -> chest usw.),
  3. teilt die Textur in Farbbereiche auf (Haut, Haare, Trikot, Seitenteile, Hose, ...), damit
     das Spiel die Figur je Team einfaerbt; aufgedruckte Nummern verschwinden dabei,
  4. schreibt <ausgabe>.glb, <ausgabe>_markers.json (Nummern) und <ausgabe>_clips.json:
     je Animation und Bild die Gelenkdrehungen im Format von HumanFigure.pose().
"""
import json
import math
import random
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

KIND = sys.argv[1]
OUT = sys.argv[2]
CLIPS = sys.argv[3:]
BASE = OUT.rsplit(".", 1)[0]

# Spiel-Gelenk -> (Meshy-Knochen fuer die Drehung, Meshy-Knochen fuer die Lage)
MAP = {
    "hips": ("Hips", "Hips"), "chest": ("Spine2", "Spine"), "head": ("Head", "Neck"),
}
for _sd, _side in (("l", "Left"), ("r", "Right")):
    MAP.update({
        "sh_" + _sd: (_side + "Arm", _side + "Arm"), "el_" + _sd: (_side + "ForeArm", _side + "ForeArm"),
        "wr_" + _sd: (_side + "Hand", _side + "Hand"), "hip_" + _sd: (_side + "UpLeg", _side + "UpLeg"),
        "kn_" + _sd: (_side + "Leg", _side + "Leg"), "an_" + _sd: (_side + "Foot", _side + "Foot"),
    })
PARENT = {"hips": None, "chest": "hips", "head": "chest"}
for _sd in "lr":
    PARENT.update({"sh_" + _sd: "chest", "el_" + _sd: "sh_" + _sd, "wr_" + _sd: "el_" + _sd,
                   "hip_" + _sd: "hips", "kn_" + _sd: "hip_" + _sd, "an_" + _sd: "kn_" + _sd})
# Meshy-Gewichtsgruppe -> Spiel-Gelenk
GROUPS = {"Hips": "hips", "Spine": "chest", "Spine1": "chest", "Spine2": "chest", "Neck": "head",
          "Head": "head", "headfront": "head"}
for _sd, _side in (("l", "Left"), ("r", "Right")):
    GROUPS.update({_side + "Shoulder": "chest", _side + "Arm": "sh_" + _sd, _side + "ForeArm": "el_" + _sd,
                   _side + "Hand": "wr_" + _sd, _side + "UpLeg": "hip_" + _sd, _side + "Leg": "kn_" + _sd,
                   _side + "Foot": "an_" + _sd, _side + "ToeBase": "an_" + _sd})
ANKLE_Z = 0.095   # Drehpunkt Sprunggelenk (das Spiel rechnet die Sohle 9,5 cm darunter)
ARM_OUT = math.radians(2.0)


def mb(name):
    return "mixamorig:" + name if name != "headfront" else name


# ------------------------------------------------------------------ laden, drehen, Masse
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=CLIPS[0])
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
body = next(o for o in bpy.data.objects if o.type == "MESH" and o.parent == arm)
for o in list(bpy.data.objects):
    if o not in (arm, body):
        bpy.data.objects.remove(o)
actions = {}
for a in bpy.data.actions:
    actions[a.name] = a
for path in CLIPS[1:]:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    for o in set(bpy.data.objects) - before:
        bpy.data.objects.remove(o)
for a in bpy.data.actions:
    actions[a.name.split(".")[0]] = a
arm.animation_data_create()
arm.animation_data.action = None

# 180 Grad um Z (Meshy schaut nach -Y), Massstab 0,01 der Armatur fest uebernehmen
arm.rotation_mode = "XYZ"
arm.rotation_euler = (0, 0, math.pi)
bpy.context.view_layer.update()
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
body.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def set_action(name):
    a = actions[name]
    arm.animation_data.action = a
    if hasattr(a, "slots") and len(a.slots):
        arm.animation_data.action_slot = a.slots[0]


def clear_pose():
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.rotation_euler = (0, 0, 0)
        pb.scale = (1, 1, 1)


# ------------------------------------------------------------------ Arme senken (Ruhehaltung)
arm.animation_data.action = None
clear_pose()
bpy.context.view_layer.update()


def aim(bone, direction):
    pb = arm.pose.bones[mb(bone)]
    m = pb.matrix.copy()
    d0 = (pb.tail - pb.head).normalized()
    q = d0.rotation_difference(direction.normalized())
    rot = q.to_matrix().to_4x4() @ Matrix(m.to_3x3()).to_4x4()
    rot.translation = m.translation
    pb.matrix = rot
    bpy.context.view_layer.update()


for side, s in (("Left", -1), ("Right", 1)):
    down = Vector((s * math.sin(ARM_OUT), 0.0, -math.cos(ARM_OUT)))
    for b in ("Arm", "ForeArm", "Hand"):
        aim(side + b, down)

hang = {pb.name: pb.matrix.copy() for pb in arm.pose.bones}
# Mesh in dieser Haltung festschreiben (ohne Skelett)
dg = bpy.context.evaluated_depsgraph_get()
me = bpy.data.meshes.new_from_object(body.evaluated_get(dg), depsgraph=dg)
fig = bpy.data.objects.new("player" if KIND == "player" else "official", me)
bpy.context.collection.objects.link(fig)
for vg in body.vertex_groups:
    fig.vertex_groups.new(name=vg.name)
for v_src, v in zip(body.data.vertices, fig.data.vertices):
    for g in v_src.groups:
        fig.vertex_groups[g.group].add([v.index], g.weight, "REPLACE")
fig.modifiers.clear()
print("DREIECKE", sum(len(p.vertices) - 2 for p in me.polygons))


def head_of(bone):
    return hang[mb(bone)].translation.copy()


# ------------------------------------------------------------------ Spiel-Skelett
pos = {}
for j, (_r, loc) in MAP.items():
    pos[j] = head_of(loc)
for sd in "lr":
    pos["an_" + sd].z = ANKLE_Z
tails = {
    "hips": pos["chest"], "chest": head_of("Neck"), "head": head_of("Neck") + Vector((0, 0, 0.25)),
}
for sd, side in (("l", "Left"), ("r", "Right")):
    tails["sh_" + sd] = pos["el_" + sd]
    tails["el_" + sd] = pos["wr_" + sd]
    tails["wr_" + sd] = pos["wr_" + sd] + Vector((0, 0, -0.18))
    tails["hip_" + sd] = pos["kn_" + sd]
    tails["kn_" + sd] = pos["an_" + sd]
    tails["an_" + sd] = pos["an_" + sd] + Vector((0, 0.17, -0.075))

rig_data = bpy.data.armatures.new("rig")
rig = bpy.data.objects.new("rig", rig_data)
bpy.context.collection.objects.link(rig)
bpy.ops.object.select_all(action="DESELECT")
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
eb = {}
for j in MAP:
    b = rig_data.edit_bones.new(j)
    b.head = pos[j]
    b.tail = tails[j]
    b.roll = 0.0
    if PARENT[j]:
        b.parent = eb[PARENT[j]]
        b.use_connect = False
    eb[j] = b
bpy.ops.object.mode_set(mode="OBJECT")

# Gewichte zusammenlegen
acc = [dict() for _ in fig.data.vertices]
names = {vg.index: vg.name.replace("mixamorig:", "") for vg in fig.vertex_groups}
for v in fig.data.vertices:
    for g in v.groups:
        j = GROUPS.get(names[g.group])
        if j:
            acc[v.index][j] = acc[v.index].get(j, 0.0) + g.weight
for vg in list(fig.vertex_groups):
    fig.vertex_groups.remove(vg)
new_groups = {j: fig.vertex_groups.new(name=j) for j in MAP}
for i, w in enumerate(acc):
    tot = sum(w.values()) or 1.0
    for j, val in w.items():
        if val / tot > 0.005:
            new_groups[j].add([i], val / tot, "REPLACE")

# ------------------------------------------------------------------ Farbbereiche aus der Textur
img = next(im for im in bpy.data.images if im.size[0] > 0)
img.scale(1024, 1024)
px = np.empty(1024 * 1024 * 4, dtype=np.float32)
img.pixels.foreach_get(px)
px = px.reshape(1024, 1024, 4)[:, :, :3]
PROTO = {"navy": (0.0, 0.055, 0.125), "skin": (0.78, 0.64, 0.53), "skin2": (0.58, 0.51, 0.46),
         "white": (0.78, 0.78, 0.78), "brown": (0.27, 0.21, 0.16), "black": (0.03, 0.05, 0.06)}
PK = list(PROTO)
PV = np.array([PROTO[k] for k in PK])


def tex_class(uv):
    x = min(1023, max(0, int(uv[0] * 1024)))
    y = min(1023, max(0, int(uv[1] * 1024)))
    c = px[y, x]
    k = PK[int(np.argmin(((PV - c) ** 2).sum(axis=1)))]
    return "skin" if k == "skin2" else k


uvl = me.uv_layers.active.data
zs = [v.co.z for v in me.vertices]
TOP = max(zs)
# Nummer vorn/hinten: Mitte von Brust/Ruecken und vorderes Hosenbein
SH_Z = head_of("LeftArm").z


def region(p, cls):
    c = p.center
    ax = abs(c.x)
    if cls == "skin":
        return "skin"
    if cls == "brown":
        return "hair" if c.z > TOP - 0.3 else "skin"
    if KIND == "official":
        if cls == "white":
            if c.z < 0.15:
                return "shoes"
            return "jersey" if c.z > 0.95 else "trousers"
        if cls == "navy":
            if c.z > SH_Z - 0.2:
                return "collar"   # Kragen und Aermelsaeume
            return "trousers" if c.z > 0.15 else "accent"
        if cls == "black":
            if c.z > TOP - 0.3 and abs(c.x) < 0.13:
                return "hair"
            return "accent" if c.z > 0.15 else "sole"
        return "skin"
    hem = HEM
    if cls == "navy":
        if c.z > hem:
            return "jersey"
        if c.z > 0.62:
            return "shorts"
        return "accent"
    if cls == "white":
        if c.z < SHOE_TOP:
            return "shoes"
        if c.z < SOCK_TOP:
            return "socks"
        if c.z > hem:
            if c.z > SH_Z - 0.06 and ax < 0.11:
                return "collar"
            # aufgedruckte Nummer auf Brust und Ruecken: Trikotfarbe
            if ax < 0.13 and abs(p.normal.y) > 0.5:
                return "jersey"
            return "panel"
        if c.z > 0.62:
            return "shorts" if abs(p.normal.y) > 0.5 and ax < 0.17 else "panel"
        return "socks"
    if cls == "black":
        if c.z < 0.05:
            return "sole"
        if 0.35 < c.z < 0.7:
            return "pads"
        return "accent"
    return "skin"


# Saum von Trikot und Hose und Schuh-/Sockenhoehe aus der Textur schaetzen
cls_of = []
for p in me.polygons:
    votes = {}
    for li in list(p.loop_indices) + [None]:
        uv = uvl[li].uv if li is not None else sum((uvl[k].uv for k in p.loop_indices), Vector((0, 0))) / len(p.loop_indices)
        k = tex_class(uv)
        votes[k] = votes.get(k, 0) + (2 if li is None else 1)
    cls_of.append(max(votes, key=votes.get))


def lowest(cls, zmin, zmax):
    zz = [p.center.z for p, c in zip(me.polygons, cls_of) if c == cls and zmin < p.center.z < zmax]
    return min(zz) if zz else None


HEM = 1.03
SHOE_TOP, SOCK_TOP = 0.16, 0.36
if KIND == "player":
    # Unterkante Trikot: wo Haut (Arme ausgenommen) unter Navy beginnt, sonst Mittelwert
    navy_z = sorted(p.center.z for p, c in zip(me.polygons, cls_of) if c == "navy" and abs(p.center.x) < 0.2)
    skin_leg = [p.center.z for p, c in zip(me.polygons, cls_of) if c == "skin" and abs(p.center.x) < 0.25 and p.center.z < 0.9]
    if skin_leg:
        print("Haut Beine bis", round(max(skin_leg), 3))
    print("Navy von", round(navy_z[0], 3), "bis", round(navy_z[-1], 3))

SLOTS = ["skin", "hair", "jersey", "panel", "collar", "shorts", "socks", "pads", "shoes", "accent", "sole",
         "logo", "trousers"]
me.materials.clear()
for n in SLOTS:
    m = bpy.data.materials.get(n) or bpy.data.materials.new(n)
    me.materials.append(m)
SLOT = {n: i for i, n in enumerate(SLOTS)}
count = {}
for p, c in zip(me.polygons, cls_of):
    r = region(p, c)
    count[r] = count.get(r, 0) + 1
    p.material_index = SLOT[r]
print("BEREICHE", count)
for p in me.polygons:
    p.use_smooth = False

# leichte Helligkeitsunterschiede je Flaeche (wie die anderen Figuren)
rnd = random.Random(7)
ca = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
for p in me.polygons:
    v = 1.0 - 0.07 * rnd.random() - 0.02 * max(0.0, -p.normal.z)
    for li in p.loop_indices:
        ca.data[li].color = (v, v, v, 1.0)
for layer in list(me.uv_layers):
    me.uv_layers.remove(layer)

# ------------------------------------------------------------------ Nummern-Marken
bm = bmesh.new()
bm.from_mesh(me)
tree = BVHTree.FromBMesh(bm)


def hit(origin, direction):
    loc, nrm, _i, _d = tree.ray_cast(Vector(origin), Vector(direction).normalized())
    return loc, nrm


def gd(v):
    return [round(v.x, 4), round(v.z, 4), round(-v.y, 4)]


markers = {}
if KIND == "player":
    chest_z = SH_Z - 0.2
    for key, origin, direction, bone in [
        ("num_front", (0, 0.6, chest_z), (0, -1, 0), "chest"),
        ("num_back", (0, -0.6, chest_z + 0.02), (0, 1, 0), "chest"),
        ("num_shorts", (-0.11, 0.6, HEM - 0.2), (0, -1, 0), "hip_l"),
    ]:
        loc, n = hit(origin, direction)
        if loc is not None:
            markers[key] = {"bone": bone, "pos": gd(loc), "normal": gd(n)}
bm.free()

# ------------------------------------------------------------------ Animationen uebertragen
C = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))  # Blender -> Godot (x, z, -y)
hang_rot = {j: hang[mb(r)].to_3x3().normalized() for j, (r, _l) in MAP.items()}
clips = {}
scene = bpy.context.scene
for name in actions:
    set_action(name)
    a = actions[name]
    f0, f1 = int(a.frame_range[0]), int(a.frame_range[1])
    frames = []
    for f in range(f0, f1 + 1):
        scene.frame_set(f)
        g = {}
        for j, (r, _l) in MAP.items():
            g[j] = arm.pose.bones[mb(r)].matrix.to_3x3().normalized() @ hang_rot[j].inverted()
        fr = {}
        for j in MAP:
            loc = g[j] if PARENT[j] is None else g[PARENT[j]].inverted() @ g[j]
            q = (C @ loc @ C.transposed()).to_quaternion()
            fr[j] = [round(q.x, 4), round(q.y, 4), round(q.z, 4), round(q.w, 4)]
        hp = arm.pose.bones[mb("Hips")].head
        fr["_hips_y"] = round(hp.z - head_of("Hips").z, 4)
        frames.append(fr)
    fps = scene.render.fps / scene.render.fps_base
    clips[name] = {"fps": fps, "frames": frames}
    print("CLIP", name, len(frames), "Bilder")
arm.animation_data.action = None

# ------------------------------------------------------------------ Export
for o in list(bpy.data.objects):
    if o not in (fig, rig):
        bpy.data.objects.remove(o)
fig.parent = rig
mod = fig.modifiers.new("Armature", "ARMATURE")
mod.object = rig
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False,
                          export_apply=False, export_animations=False, export_skins=True,
                          export_yup=True, export_def_bones=False,
                          export_vertex_color="ACTIVE", export_all_vertex_colors=False)
with open(BASE + "_markers.json", "w") as f:
    json.dump(markers, f, indent=1)
with open(BASE + "_clips.json", "w") as f:
    json.dump(clips, f, separators=(",", ":"))
print("FERTIG", OUT)
