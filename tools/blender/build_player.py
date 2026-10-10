"""Baut die Spielerfigur in Blender (als Python-Modul bpy) und exportiert sie als glTF.

Aufruf:  python build_player.py <ausgabe.glb> [vorschau_ordner]

Stil: kantiges Low-Poly wie Mattis' Vorlage (Stachelfrisur, markantes Gesicht, weites
Trikot mit kurzen Aermeln, Hose bis Mitte Oberschenkel, Knieschoner, hohe Stutzen,
kraeftige Turnschuhe). Blender-Achsen: Z oben, Figur schaut nach +Y, rechts ist +X.
Nach dem Export (glTF, Y oben) schaut sie nach -Z, wie die Figuren im Spiel.

Das Skelett benutzt die Gelenknamen aus scripts/figure.gd. Gebaut wird in T-Haltung
(saubere Gewichte), danach werden die Arme gesenkt und das als Ruhehaltung gespeichert,
denn im Spiel bedeutet "alle Gelenke 0" = Arme haengen.
"""
import math
import random
import sys

import bpy  # zuerst: bmesh und mathutils kommen mit bpy
import bmesh
from mathutils import Matrix, Vector

OUT = sys.argv[1] if len(sys.argv) > 1 else "player.glb"
PREVIEW = sys.argv[2] if len(sys.argv) > 2 else ""

# ------------------------------------------------------------------ Masse (Meter)
SH_X = 0.215     # Schultergelenk seitlich
SH_Z = 1.53      # Schulterhoehe
UPPER = 0.30     # Oberarm
FORE = 0.27      # Unterarm
HIP_X = 0.095
HIP_Z = 0.95
KNEE_Z = 0.51
ANKLE_Z = 0.095
PELVIS_Z = 1.02
CHEST_Z = 1.08
HEAD_Z = 1.645   # Kopfgelenk (Halsansatz oben)

COLORS = {
    "skin": (0.93, 0.74, 0.6, 1),
    "jersey": (0.95, 0.95, 0.95, 1),
    "shorts": (0.1, 0.12, 0.3, 1),
    "hair": (0.2, 0.13, 0.08, 1),
    "shoes": (0.96, 0.96, 0.96, 1),
    "sole": (0.2, 0.2, 0.22, 1),
    "socks": (0.95, 0.95, 0.95, 1),
    "pads": (0.13, 0.13, 0.15, 1),
    "trim": (0.1, 0.12, 0.3, 1),
    "eyes": (0.08, 0.07, 0.07, 1),
}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.diffuse_color = COLORS[name]
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = COLORS[name]
            bsdf.inputs["Roughness"].default_value = 0.8
    return m


def new_object(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


def add_mat(ob, name):
    m = material(name)
    if m.name not in ob.data.materials:
        ob.data.materials.append(m)
    return list(ob.data.materials).index(m)


def evaluated_copy(ob, name):
    """Objekt mit allen Modifikatoren als neues, einfaches Mesh-Objekt."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, depsgraph=dg)
    me.name = name
    new = bpy.data.objects.new(name + "_tmp", me)
    bpy.context.collection.objects.link(new)
    bpy.data.objects.remove(ob)
    new.name = name
    me.name = name
    return new


# ------------------------------------------------------------------ Koerper (Skin-Modifier)
def build_body():
    """Rumpf, Arme, Beine als ein Stueck: ein Gerippe aus Punkten mit Radien,
    aus dem Blenders Skin-Modifier eine geschlossene Huelle macht."""
    pts = []
    edges = []
    radii = []

    def p(co, rx, ry=None):
        pts.append(Vector(co))
        radii.append((rx, ry if ry is not None else rx))
        return len(pts) - 1

    def e(a, b):
        edges.append((a, b))

    crotch = p((0, 0, 0.90), 0.13, 0.10)
    pelvis = p((0, 0, 0.98), 0.155, 0.11)
    waist = p((0, 0, 1.10), 0.135, 0.095)
    belly = p((0, 0, 1.22), 0.148, 0.10)
    chest = p((0, 0.008, 1.36), 0.185, 0.125)
    upper = p((0, 0, 1.47), 0.198, 0.118)
    neck0 = p((0, -0.005, 1.585), 0.062, 0.062)
    neck1 = p((0, 0.0, HEAD_Z + 0.02), 0.055, 0.055)
    for a, b in [(crotch, pelvis), (pelvis, waist), (waist, belly), (belly, chest), (chest, upper), (upper, neck0), (neck0, neck1)]:
        e(a, b)
    for s in (-1, 1):
        sh = p((s * SH_X, 0, SH_Z), 0.08)
        dl = p((s * (SH_X + 0.08), 0, SH_Z - 0.005), 0.077, 0.07)  # Deltamuskel
        mid = p((s * (SH_X + UPPER * 0.55), 0, SH_Z - 0.005), 0.064, 0.06)
        el = p((s * (SH_X + UPPER), 0, SH_Z - 0.01), 0.05)
        fa = p((s * (SH_X + UPPER + FORE * 0.35), 0, SH_Z - 0.01), 0.056, 0.05)
        wr = p((s * (SH_X + UPPER + FORE), 0, SH_Z - 0.01), 0.037, 0.03)
        for a, b in [(upper, sh), (sh, dl), (dl, mid), (mid, el), (el, fa), (fa, wr)]:
            e(a, b)
        hp = p((s * HIP_X, 0, HIP_Z), 0.108, 0.11)
        th = p((s * (HIP_X + 0.005), 0.005, 0.76), 0.1, 0.102)
        kn = p((s * (HIP_X + 0.003), 0.0, KNEE_Z), 0.064, 0.066)
        cf = p((s * (HIP_X + 0.002), -0.014, 0.37), 0.07, 0.074)
        an = p((s * HIP_X, 0, ANKLE_Z + 0.02), 0.04, 0.044)
        for a, b in [(crotch, hp), (hp, th), (th, kn), (kn, cf), (cf, an)]:
            e(a, b)
    me = bpy.data.meshes.new("body_src")
    me.from_pydata([tuple(v) for v in pts], edges, [])
    ob = bpy.data.objects.new("body", me)
    bpy.context.collection.objects.link(ob)
    sk = ob.modifiers.new("Skin", "SKIN")
    sk.use_smooth_shade = False
    sk.branch_smoothing = 0.3
    for i, r in enumerate(radii):
        ob.data.skin_vertices[0].data[i].radius = r
    ob.data.skin_vertices[0].data[crotch].use_root = True
    sub = ob.modifiers.new("Sub", "SUBSURF")
    sub.levels = 1
    sub.render_levels = 1
    ob = evaluated_copy(ob, "body")
    add_mat(ob, "skin")
    return ob


# ------------------------------------------------------------------ Kleidung aus dem Koerper
def shell(body, name, mat, keep, push, extra=None):
    """Kopiert die Flaechen des Koerpers, deren Mitte keep(c) erfuellt, und schiebt sie
    entlang der Normalen nach aussen (Kleidung sitzt locker darueber)."""
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.normal_update()
    kill = [f for f in bm.faces if not keep(f.calc_center_median())]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.normal_update()
    vn = {v: v.normal.copy() for v in bm.verts}
    for v in bm.verts:
        d = push(v.co) if callable(push) else push
        v.co += vn[v] * d
    if extra:
        extra(bm)
    ob = new_object(name, bm)
    ob.data.materials.clear()
    add_mat(ob, mat)
    return ob


def thicken(ob, t, mat_rim=None):
    """Stoffdicke, damit Saeume als Kante sichtbar sind."""
    m = ob.modifiers.new("Sol", "SOLIDIFY")
    m.thickness = t
    m.offset = -1.0
    m.use_rim = True
    if mat_rim:
        idx = add_mat(ob, mat_rim)
        m.material_offset_rim = idx
    return evaluated_copy(ob, ob.name)


def build_clothes(body):
    def is_torso(c):
        return 0.97 < c.z < 1.585 and abs(c.x) < SH_X + 0.17

    def jersey_push(co):
        # Trikot faellt locker: unten weiter, an den Aermeln weit
        d = 0.018 + max(0.0, 1.3 - co.z) * 0.06
        if abs(co.x) > SH_X + 0.03:
            d += 0.012
        return d

    def jersey_hem(bm):
        # Unterkante leicht nach unten ziehen, damit das Trikot ueber die Hose faellt
        for v in bm.verts:
            if v.co.z < 1.02 and abs(v.co.x) < 0.3:
                v.co.z -= 0.04
    jersey = shell(body, "jersey", "jersey", is_torso, jersey_push, jersey_hem)
    jersey = thicken(jersey, 0.008, "trim")

    def is_shorts(c):
        return 0.69 < c.z < 1.07 and abs(c.x) < 0.3

    def shorts_push(co):
        return 0.02 + max(0.0, 0.92 - co.z) * 0.12  # Beine weiten sich nach unten

    shorts = shell(body, "shorts", "shorts", is_shorts, shorts_push)
    shorts = thicken(shorts, 0.008)

    def is_sock(c):
        return 0.09 < c.z < 0.40

    socks = shell(body, "socks", "socks", is_sock, 0.006)
    socks = thicken(socks, 0.005, "trim")
    return [jersey, shorts, socks]


# ------------------------------------------------------------------ Knieschoner, Schuhe, Haende
def knee_pad(s):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=10, radius1=0.074, radius2=0.07, depth=0.15)
    for v in bm.verts:
        # hinten flacher, vorn gewoelbt
        if v.co.y < 0:
            v.co.y *= 0.82
        else:
            v.co.y *= 1.12
    bmesh.ops.translate(bm, verts=bm.verts, vec=(s * (HIP_X + 0.003), 0.01, KNEE_Z - 0.01))
    ob = new_object("pad_" + ("l" if s < 0 else "r"), bm)
    add_mat(ob, "pads")
    return thicken(ob, 0.012)


def shoe(s):
    """Kraeftiger Turnschuh: Oberteil mit runder Spitze, dicke Sohle, Streifen."""
    bm = bmesh.new()
    res = bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=2, use_grid_fill=True)
    for v in bm.verts:
        x, y, z = v.co  # Wuerfel -0,5..0,5
        y2 = y + 0.5  # 0 hinten, 1 vorn
        w = 0.112 * (1.0 - 0.25 * max(0.0, y2 - 0.6) / 0.4) * (0.9 + 0.1 * (z + 0.5))
        h = 0.105 * (1.0 - 0.45 * max(0.0, y2 - 0.45) / 0.55)
        v.co = Vector((x * w, -0.08 + y2 * 0.3, (z + 0.5) * h))
        # Spitze rund, Ferse hochgezogen
        if y2 > 0.8:
            v.co.z *= 0.85
        if y2 < 0.15 and z > 0:
            v.co.z += 0.02
    for v in bm.verts:
        v.co.x += s * HIP_X
    ob = new_object("shoe_" + ("l" if s < 0 else "r"), bm)
    add_mat(ob, "shoes")
    # Sohle
    sb = bmesh.new()
    bmesh.ops.create_cube(sb, size=1.0)
    bmesh.ops.subdivide_edges(sb, edges=sb.edges[:], cuts=1, use_grid_fill=True)
    for v in sb.verts:
        x, y, z = v.co
        y2 = y + 0.5
        w = 0.122 * (1.0 - 0.22 * max(0.0, y2 - 0.6) / 0.4)
        v.co = Vector((x * w + s * HIP_X, -0.088 + y2 * 0.318, (z + 0.5) * 0.032 - 0.002))
        if y2 > 0.9:
            v.co.z += 0.01 * (z + 0.5)
    so = new_object("sole_" + ("l" if s < 0 else "r"), sb)
    add_mat(so, "sole")
    # seitlicher Streifen
    st = bmesh.new()
    bmesh.ops.create_cube(st, size=1.0)
    for v in st.verts:
        x, y, z = v.co
        v.co = Vector((x * 0.118 + s * HIP_X, 0.06 + y * 0.12 + z * 0.05, 0.05 + z * 0.018))
    sto = new_object("stripe_" + ("l" if s < 0 else "r"), st)
    add_mat(sto, "trim")
    return [ob, so, sto]


def hand(s):
    """Hand in T-Haltung (Handflaeche nach unten): Handteller, vier Finger, Daumen."""
    x0 = s * (SH_X + UPPER + FORE)
    z0 = SH_Z - 0.01
    bm = bmesh.new()

    def block(cx, cy, cz, sx, sy, sz, taper=1.0):
        r = bmesh.ops.create_cube(bm, size=1.0)
        vs = r["verts"]
        for v in vs:
            x, y, z = v.co
            k = 1.0 + (taper - 1.0) * (s * x + 0.5)
            v.co = Vector((cx + x * sx, cy + y * sy * k, cz + z * sz * k))
        return vs

    block(x0 + s * 0.05, 0, z0, 0.095, 0.085, 0.032, 0.95)          # Handteller
    for i in range(4):
        y = -0.03 + i * 0.02
        ln = [0.07, 0.08, 0.076, 0.062][i]
        block(x0 + s * (0.097 + ln * 0.5), y, z0 - 0.002, ln, 0.018, 0.022, 0.85)
    tv = block(x0 + s * 0.045, 0.055, z0 - 0.008, 0.07, 0.022, 0.024, 0.85)  # Daumen nach vorn
    for v in tv:
        d = abs(v.co.x - x0)
        v.co.y += d * 0.35
    ob = new_object("hand_" + ("l" if s < 0 else "r"), bm)
    add_mat(ob, "skin")
    return ob


# ------------------------------------------------------------------ Kopf
def head():
    """Kantiger Kopf: schmales Kinn, markante Wangen, gerade Nase, Brauenwulst, Ohren,
    dazu eine hochstehende Stachelfrisur."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=9, radius=1.0)
    cz = HEAD_Z + 0.115
    for v in bm.verts:
        x, y, z = v.co
        # Grundform: oben breiter Schaedel, unten schmaler Kiefer
        w = 0.092
        if z < 0.0:
            w *= 1.0 - 0.28 * (-z) ** 1.3
        dpt = 0.112
        if y > 0 and z < -0.2:
            dpt *= 0.92  # Kinn etwas zurueck
        h = 0.128 if z > 0 else 0.118
        nx, ny, nz = x * w, y * dpt, z * h
        # Gesicht vorne flacher, Wangenknochen
        if y > 0.6:
            ny -= (y - 0.6) * 0.03
        if y > 0.2 and -0.2 < z < 0.2:
            nx *= 1.04
        # Kinn kantig nach vorn
        if z < -0.75 and y > 0.3:
            ny += 0.01
        v.co = Vector((nx, ny, nz + cz))
    # Nase: Keil vorn
    nb = bmesh.new()
    bmesh.ops.create_cone(nb, cap_ends=True, segments=3, radius1=0.022, radius2=0.004, depth=0.05)
    for v in nb.verts:
        v.co = Matrix.Rotation(math.radians(-15), 4, "X") @ v.co
        v.co += Vector((0, 0.103, cz - 0.01))
    nose_me = bpy.data.meshes.new("nose_tmp")
    nb.to_mesh(nose_me)
    nb.free()
    bm.from_mesh(nose_me)
    bpy.data.meshes.remove(nose_me)
    # Ohren
    for s in (-1, 1):
        r = bmesh.ops.create_cube(bm, size=1.0)
        for v in r["verts"]:
            x, y, z = v.co
            v.co = Vector((s * 0.088 + x * 0.014, -0.008 + y * 0.026, cz - 0.005 + z * 0.04))
    ob = new_object("head", bm)
    add_mat(ob, "skin")
    # Brauen und Augen als flache dunkle Teile
    eb = bmesh.new()
    for s in (-1, 1):
        r = bmesh.ops.create_cube(eb, size=1.0)
        for v in r["verts"]:
            x, y, z = v.co
            v.co = Vector((s * 0.037 + x * 0.034, 0.1 + y * 0.012, cz + 0.032 + z * 0.006 - s * x * 0.01))
        r = bmesh.ops.create_cube(eb, size=1.0)
        for v in r["verts"]:
            x, y, z = v.co
            v.co = Vector((s * 0.036 + x * 0.022, 0.097 + y * 0.01, cz + 0.012 + z * 0.01))
    eyes = new_object("eyes", eb)
    add_mat(eyes, "eyes")
    # Mund
    mb = bmesh.new()
    r = bmesh.ops.create_cube(mb, size=1.0)
    for v in r["verts"]:
        x, y, z = v.co
        v.co = Vector((x * 0.034, 0.096 + y * 0.01, cz - 0.058 + z * 0.005))
    mouth = new_object("mouth", mb)
    add_mat(mouth, "eyes")
    return [ob, eyes, mouth, hair(cz)]


def hair(cz):
    """Kappe auf dem Schaedel (an den Seiten kurz) plus dichte Zacken, die vorn hoch
    aufstehen und nach hinten flacher anliegen, wie in der Vorlage."""
    rnd = random.Random(7)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=14, v_segments=9, radius=1.0)
    kill = [v for v in bm.verts if v.co.z < -0.45 or (v.co.y > 0.35 and v.co.z < 0.35)
            or (abs(v.co.x) > 0.55 and v.co.z < 0.05 and v.co.y > -0.4)]
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    for v in bm.verts:
        x, y, z = v.co
        v.co = Vector((x * 0.1, y * 0.119 - 0.003, z * 0.133 + cz + 0.006))
    # Zacken (4-seitige Kegel): Reihen von vorn nach hinten
    rows = [(0.085, 7, 0.10, 32), (0.045, 7, 0.09, 12), (0.0, 7, 0.08, -8), (-0.045, 6, 0.065, -28), (-0.085, 5, 0.05, -48)]
    for ry, n, ln0, tilt in rows:
        for k in range(n):
            u = (k + 0.5) / n * 2.0 - 1.0  # -1 links .. 1 rechts
            x = u * 0.075 * (1.0 - 0.25 * abs(ry) / 0.085)
            y = ry + rnd.uniform(-0.01, 0.01)
            top = math.sqrt(max(0.0, 1.0 - (x / 0.1) ** 2 - (y / 0.12) ** 2))
            z = cz + 0.006 + top * 0.125
            ln = ln0 * rnd.uniform(0.8, 1.15) * (1.0 - 0.3 * abs(u))
            r = bmesh.ops.create_cone(bm, cap_ends=True, segments=4, radius1=rnd.uniform(0.026, 0.034), radius2=0.0, depth=ln)
            tx = math.radians(tilt + rnd.uniform(-8, 8))     # vorn nach vorn-oben, hinten nach hinten
            ty = math.radians(u * 38 + rnd.uniform(-8, 8))   # seitlich nach aussen
            m = (Matrix.Translation((x, y, z)) @ Matrix.Rotation(ty, 4, "Y") @ Matrix.Rotation(-tx, 4, "X")
                 @ Matrix.Translation((0, 0, ln * 0.42)) @ Matrix.Rotation(rnd.uniform(0, math.tau), 4, "Z"))
            for v in r["verts"]:
                v.co = m @ v.co
    ob = new_object("hair", bm)
    add_mat(ob, "hair")
    return ob


# ------------------------------------------------------------------ Skelett
BONES = [
    # name, kopf, ende, eltern
    ("hips", (0, 0, PELVIS_Z), (0, 0, CHEST_Z), None),
    ("chest", (0, 0, CHEST_Z), (0, 0, 1.58), "hips"),
    ("head", (0, 0, HEAD_Z), (0, 0, HEAD_Z + 0.25), "chest"),
]
for _sd, _s in (("l", -1), ("r", 1)):
    BONES += [
        ("sh_" + _sd, (_s * SH_X, 0, SH_Z), (_s * (SH_X + UPPER), 0, SH_Z - 0.01), "chest"),
        ("el_" + _sd, (_s * (SH_X + UPPER), 0, SH_Z - 0.01), (_s * (SH_X + UPPER + FORE), 0, SH_Z - 0.01), "sh_" + _sd),
        ("wr_" + _sd, (_s * (SH_X + UPPER + FORE), 0, SH_Z - 0.01), (_s * (SH_X + UPPER + FORE + 0.18), 0, SH_Z - 0.01), "el_" + _sd),
        ("hip_" + _sd, (_s * HIP_X, 0, HIP_Z), (_s * HIP_X, 0, KNEE_Z), "hips"),
        ("kn_" + _sd, (_s * HIP_X, 0, KNEE_Z), (_s * HIP_X, 0, ANKLE_Z), "hip_" + _sd),
        ("an_" + _sd, (_s * HIP_X, 0, ANKLE_Z), (_s * HIP_X, 0.17, 0.02), "kn_" + _sd),
    ]


def build_armature():
    arm = bpy.data.armatures.new("rig")
    ob = bpy.data.objects.new("rig", arm)
    bpy.context.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = {}
    for name, h, t, par in BONES:
        b = arm.edit_bones.new(name)
        b.head = h
        b.tail = t
        b.roll = 0.0
        if par:
            b.parent = eb[par]
            b.use_connect = False
        eb[name] = b
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


def bind(rig, meshes, rigid):
    """Koerper automatisch (Waermeverteilung) an die Knochen binden. Kleidung uebernimmt
    die Gewichte der naechsten Koerperstelle, damit sie genau mit der Haut mitgeht.
    Starre Teile (Kopf, Haende, Schuhe, Schoner) haengen ganz an einem Knochen."""
    from mathutils.bvhtree import BVHTree
    body = next(m for m in meshes if m.name == "body")
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    names = [g.name for g in body.vertex_groups]
    bw = []
    for v in body.data.vertices:
        d = {}
        for g in v.groups:
            if g.weight > 0.001:
                d[names[g.group]] = g.weight
        bw.append(d)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.faces.ensure_lookup_table()
    tree = BVHTree.FromBMesh(bm)
    for m in meshes:
        if m is body:
            continue
        m.parent = rig
        mod = m.modifiers.new("Armature", "ARMATURE")
        mod.object = rig
        if m.name in rigid:
            vg = m.vertex_groups.new(name=rigid[m.name])
            vg.add([v.index for v in m.data.vertices], 1.0, "REPLACE")
            continue
        groups = {n: m.vertex_groups.new(name=n) for n in names}
        for v in m.data.vertices:
            loc, _n, fi, _d = tree.find_nearest(v.co)
            f = bm.faces[fi]
            acc = {}
            tot = 0.0
            for fv in f.verts:
                w = 1.0 / max((fv.co - loc).length, 1e-4)
                tot += w
                for n, gw in bw[fv.index].items():
                    acc[n] = acc.get(n, 0.0) + gw * w
            for n, val in acc.items():
                groups[n].add([v.index], val / tot, "REPLACE")
    bm.free()


def lower_arms(rig, meshes):
    """Arme aus der T-Haltung senken, Meshes in dieser Haltung festschreiben und sie als
    neue Ruhehaltung des Skeletts uebernehmen."""
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    for sd, s in (("l", -1), ("r", 1)):
        pb = rig.pose.bones["sh_" + sd]
        # Knochen zeigt entlang seiner Y-Achse; Drehung in Weltachsen um Y (vorn/hinten)
        rest = pb.bone.matrix_local.to_3x3()
        world_rot = Matrix.Rotation(math.radians(s * 88.0), 3, "Y")
        local = rest.inverted() @ world_rot @ rest
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = local.to_quaternion()
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.view_layer.update()
    for m in meshes:
        bpy.context.view_layer.objects.active = m
        mod = next(md for md in m.modifiers if md.type == "ARMATURE")
        # Ergebnis der Verformung als neue Grundform speichern, Gewichte bleiben
        dg = bpy.context.evaluated_depsgraph_get()
        ev = m.evaluated_get(dg)
        co = [v.co.copy() for v in ev.data.vertices]
        m.modifiers.remove(mod)
        for v, c in zip(m.data.vertices, co):
            v.co = c
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    for m in meshes:
        mod = m.modifiers.new("Armature", "ARMATURE")
        mod.object = rig


def flat_shade(meshes):
    for m in meshes:
        for p in m.data.polygons:
            p.use_smooth = False


def render_preview(folder, tag):
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    scn.cycles.samples = 24
    scn.cycles.device = "CPU"
    scn.render.resolution_x = 620
    scn.render.resolution_y = 820
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.32, 0.34, 0.38, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    scn.world = world
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(30))
    scn.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 85
    scn.collection.objects.link(cam)
    scn.camera = cam
    views = {"front": (0, 9.0, 0), "side": (9.0, 0, 0), "back": (0, -9.0, 0), "face": (0.5, 2.2, 0)}
    for vname, (x, y, _z) in views.items():
        tz = 1.0 if vname != "face" else 1.78
        cz = 1.0 if vname != "face" else 1.8
        cam.location = (x, y, cz)
        d = Vector((0, 0, tz)) - cam.location
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        scn.render.filepath = f"{folder}/{tag}_{vname}.png"
        bpy.ops.render.render(write_still=True)


def main():
    reset()
    body = build_body()
    clothes = build_clothes(body)
    parts = [body] + clothes
    rigid = {}
    for s, sd in ((-1, "l"), (1, "r")):
        pad = knee_pad(s)
        parts.append(pad)
        rigid[pad.name] = "kn_" + sd
        for o in shoe(s):
            parts.append(o)
            rigid[o.name] = "an_" + sd
        h = hand(s)
        parts.append(h)
        rigid[h.name] = "wr_" + sd
    for o in head():
        parts.append(o)
        rigid[o.name] = "head"
    flat_shade(parts)
    if PREVIEW:
        render_preview(PREVIEW, "tpose")
    rig = build_armature()
    bind(rig, parts, rigid)
    lower_arms(rig, parts)
    if PREVIEW:
        render_preview(PREVIEW, "rest")
    # Alles zu einem Mesh verbinden: eine Figur = ein Objekt mit je einer Flaeche pro Material.
    tris = sum(len(p.vertices) - 2 for m in parts for p in m.data.polygons)
    bpy.ops.object.select_all(action="DESELECT")
    for m in parts:
        m.select_set(True)
    body = parts[0]
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = "player"
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False,
                              export_apply=False, export_animations=False, export_skins=True,
                              export_yup=True, export_def_bones=False)
    print("FERTIG", OUT, "Dreiecke:", tris)


main()
