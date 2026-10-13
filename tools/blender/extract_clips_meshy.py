"""Meshy-Animationen auf das Spiel-Skelett uebertragen, ohne die Figur neu zu bauen.

Aufruf:  python extract_clips_meshy.py <gerigt_mit_animationen.glb> <player_clips.json> [clip ...]

Liest alle Animationen (oder nur die genannten) aus der Meshy-Datei und schreibt sie als
Gelenkdrehungen in die vorhandene player_clips.json (gleiche Rechnung wie
build_figure_rigged.py). Funktioniert mit beiden Meshy-Skeletten: mit "mixamorig:"-Namen
(Spine, Spine1, Spine2, Neck) und mit dem neuen Meshy-Rig (Spine02, Spine01, Spine, neck).
Die Hueftverschiebung wird nicht gespeichert: das Spiel stellt die Figur ueber den tiefsten
Punkt auf den Boden, und die Text-to-Motion-Clips haben unbrauchbare Hueft-Lagen.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

SRC = sys.argv[1]
OUT = sys.argv[2]
ONLY = set(sys.argv[3:])
ARM_OUT = math.radians(2.0)

MAP = {"hips": "Hips", "chest": "Spine2", "head": "Head"}
for _sd, _side in (("l", "Left"), ("r", "Right")):
    MAP.update({"sh_" + _sd: _side + "Arm", "el_" + _sd: _side + "ForeArm", "wr_" + _sd: _side + "Hand",
                "hip_" + _sd: _side + "UpLeg", "kn_" + _sd: _side + "Leg", "an_" + _sd: _side + "Foot"})
PARENT = {"hips": None, "chest": "hips", "head": "chest"}
for _sd in "lr":
    PARENT.update({"sh_" + _sd: "chest", "el_" + _sd: "sh_" + _sd, "wr_" + _sd: "el_" + _sd,
                   "hip_" + _sd: "hips", "kn_" + _sd: "hip_" + _sd, "an_" + _sd: "kn_" + _sd})
NEW_RIG = {"Spine2": "Spine", "Neck": "neck"}  # Mixamo-Name -> Name im neuen Meshy-Rig

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
mixamo = any(b.name.startswith("mixamorig:") for b in arm.data.bones)


def mb(name):
    if mixamo:
        return "mixamorig:" + name if name != "headfront" else name
    return NEW_RIG.get(name, name)


actions = {a.name.split(".")[0]: a for a in bpy.data.actions}
arm.animation_data_create()
arm.animation_data.action = None
for o in list(bpy.data.objects):
    if o is not arm and o.parent is not arm:
        bpy.data.objects.remove(o)
arm.rotation_mode = "XYZ"
arm.rotation_euler = (0, 0, math.pi)
bpy.context.view_layer.update()
bpy.ops.object.select_all(action="DESELECT")
for o in bpy.data.objects:
    o.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def set_action(name):
    a = actions[name]
    arm.animation_data.action = a
    if hasattr(a, "slots") and len(a.slots):
        arm.animation_data.action_slot = a.slots[0]


for pb in arm.pose.bones:
    pb.location = (0, 0, 0)
    pb.rotation_quaternion = (1, 0, 0, 0)
    pb.rotation_euler = (0, 0, 0)
    pb.scale = (1, 1, 1)
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


# Ruhehaltung des Spiels: Arme haengen 2 Grad seitlich, Beine gerade nach unten
for side, s in (("Left", -1), ("Right", 1)):
    down = Vector((s * math.sin(ARM_OUT), 0.0, -math.cos(ARM_OUT)))
    for b in ("Arm", "ForeArm", "Hand"):
        aim(side + b, down)
hang = {pb.name: pb.matrix.copy() for pb in arm.pose.bones}
hang_rot = {j: hang[mb(r)].to_3x3().normalized() for j, r in MAP.items()}

C = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))  # Blender -> Godot (x, z, -y)
clips = {}
if os.path.exists(OUT):
    with open(OUT) as f:
        clips = json.load(f)
scene = bpy.context.scene
fps = scene.render.fps / scene.render.fps_base
for name in sorted(actions):
    if ONLY and name not in ONLY:
        continue
    set_action(name)
    a = actions[name]
    f0, f1 = int(a.frame_range[0]), int(a.frame_range[1])
    frames = []
    for fno in range(f0, f1 + 1):
        scene.frame_set(fno)
        g = {j: arm.pose.bones[mb(r)].matrix.to_3x3().normalized() @ hang_rot[j].inverted() for j, r in MAP.items()}
        fr = {}
        for j in MAP:
            loc = g[j] if PARENT[j] is None else g[PARENT[j]].inverted() @ g[j]
            q = (C @ loc @ C.transposed()).to_quaternion()
            fr[j] = [round(q.x, 4), round(q.y, 4), round(q.z, 4), round(q.w, 4)]
        frames.append(fr)
    clips[name] = {"fps": fps, "frames": frames}
    print("CLIP", name, len(frames), "Bilder", round(len(frames) / fps, 2), "s")
arm.animation_data.action = None
with open(OUT, "w") as f:
    json.dump(clips, f, separators=(",", ":"))
print("FERTIG", OUT)
