"""Baut die Spielerfigur in Blender (als Python-Modul bpy) und exportiert sie als glTF.

Aufruf:  python build_player.py <ausgabe.glb> [vorschau_ordner]
Schreibt zusaetzlich <ausgabe>_markers.json (Stellen fuer Rueckennummer usw.).

Stil wie Mattis' Vorlage (references/stil-vorlage-spieler.png): facettiertes Low-Poly aus
unregelmaessigen Dreiecken, jede Flaeche leicht anders schattiert, matte Farben, Gesicht ohne
Augen und Mund (nur kantige Flaechen), athletischer Koerper, V-Kragen, weisse Seitenstreifen,
Hose bis Mitte Oberschenkel, dicke Knieschoner, weisse Stutzen, hohe Volleyballschuhe.

Teamfarben setzt das Spiel ueber die Materialnamen (siehe scripts/team_style.gd):
jersey, panel, collar, logo, shorts, socks, shoes, accent, sole, pads, trousers, skin, hair.
Vier Frisuren als eigene Objekte hair_0 .. hair_3 (das Spiel blendet eine ein).

Blender-Achsen: Z oben, Figur schaut nach +Y, rechts ist +X. Nach dem Export (glTF, Y oben)
schaut sie nach -Z wie die Figuren im Spiel. Das Skelett benutzt die Gelenknamen aus
scripts/figure.gd. Gebaut wird in T-Haltung (saubere Gewichte), danach werden die Arme
gesenkt und das als Ruhehaltung gespeichert ("alle Gelenke 0" = Arme haengen).
"""
import json
import math
import random
import sys

import bpy  # zuerst: bmesh und mathutils kommen mit bpy
import bmesh
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

OUT = sys.argv[1] if len(sys.argv) > 1 else "player.glb"
PREVIEW = sys.argv[2] if len(sys.argv) > 2 else ""

# ------------------------------------------------------------------ Masse (Meter)
SH_X = 0.212     # Schultergelenk seitlich
SH_Z = 1.505     # Schulterhoehe
UPPER = 0.30     # Oberarm
FORE = 0.27      # Unterarm
ARM_A = math.radians(40.0)  # Arme beim Bauen 40 Grad gesenkt (A-Haltung): weniger Verzerrung an der Schulter
HIP_X = 0.098
HIP_Z = 0.95
KNEE_Z = 0.51
ANKLE_Z = 0.095
PELVIS_Z = 1.02
CHEST_Z = 1.08
HEAD_Z = 1.645   # Kopfgelenk (oberes Halsende)
HEAD_C = HEAD_Z + 0.115  # Kopfmitte

# Vorschaufarben (im Spiel kommen die Farben vom Team)
def arm_pt(s, d, dz=0.0):
    """Punkt auf der Armachse, d Meter von der Schulter (A-Haltung), dz quer dazu."""
    return (s * (SH_X + d * math.cos(ARM_A) + dz * math.sin(ARM_A)), 0.0,
            SH_Z - d * math.sin(ARM_A) + dz * math.cos(ARM_A))


def to_a_pose(co, s):
    """Punkt aus der T-Haltung um das Schultergelenk in die A-Haltung drehen."""
    x, y, z = co.x - s * SH_X, co.y, co.z - SH_Z
    a = s * ARM_A
    return Vector((x * math.cos(a) + z * math.sin(a) + s * SH_X, y, -x * math.sin(a) + z * math.cos(a) + SH_Z))


def arm_coord(c):
    """(Abstand entlang des Arms ab Schulter, Abstand von der Armachse) fuer einen Punkt."""
    s = 1.0 if c.x >= 0 else -1.0
    vx, vz = s * c.x - SH_X, c.z - SH_Z
    ux, uz = math.cos(ARM_A), -math.sin(ARM_A)
    a = vx * ux + vz * uz
    px, pz = vx - a * ux, vz - a * uz
    return a, math.sqrt(px * px + pz * pz + c.y * c.y)


COLORS = {
    "skin": (0.86, 0.6, 0.42, 1),
    "hair": (0.28, 0.17, 0.1, 1),
    "jersey": (0.09, 0.12, 0.26, 1),
    "panel": (0.92, 0.92, 0.92, 1),
    "collar": (0.92, 0.92, 0.92, 1),
    "logo": (0.92, 0.92, 0.92, 1),
    "shorts": (0.09, 0.12, 0.26, 1),
    "socks": (0.92, 0.92, 0.92, 1),
    "shoes": (0.92, 0.92, 0.92, 1),
    "accent": (0.09, 0.12, 0.26, 1),
    "sole": (0.85, 0.85, 0.87, 1),
    "pads": (0.08, 0.08, 0.09, 1),
    "trousers": (0.1, 0.1, 0.12, 1),
}
RND = random.Random(11)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.diffuse_color = COLORS[name]
        m.use_nodes = True
        nt = m.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        bsdf.inputs["Roughness"].default_value = 0.85
        # Grundfarbe * Facetten-Helligkeit (Farbattribut "Col"), wie spaeter in Godot
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs[6].default_value = COLORS[name]
        nt.links.new(attr.outputs["Color"], mix.inputs[7])
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
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
    new = bpy.data.objects.new(name + "_tmp", me)
    bpy.context.collection.objects.link(new)
    bpy.data.objects.remove(ob)
    new.name = name
    me.name = name
    return new


def facet(ob, target_tris, smooth_levels=0):
    """Low-Poly-Facetten: optional glatt unterteilen, dann auf etwa target_tris Dreiecke
    vereinfachen. Das ergibt die unregelmaessigen Dreiecksflaechen der Vorlage."""
    if smooth_levels:
        sub = ob.modifiers.new("Sub", "SUBSURF")
        sub.levels = smooth_levels
        sub.render_levels = smooth_levels
        ob = evaluated_copy(ob, ob.name)
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if tris > target_tris:
        dec = ob.modifiers.new("Dec", "DECIMATE")
        dec.decimate_type = "COLLAPSE"
        dec.ratio = target_tris / tris
        dec.use_collapse_triangulate = True
        ob = evaluated_copy(ob, ob.name)
    else:
        tri = ob.modifiers.new("Tri", "TRIANGULATE")
        ob = evaluated_copy(ob, ob.name)
    return ob


def facet_colors(ob, amount=0.07, seed=0):
    """Jede Flaeche bekommt eine leicht andere Helligkeit (Farbattribut "Col")."""
    rnd = random.Random(seed or hash(ob.name) & 0xFFFF)
    me = ob.data
    if "Col" in me.color_attributes:
        me.color_attributes.remove(me.color_attributes["Col"])
    ca = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    for p in me.polygons:
        # nach oben zeigende Flaechen etwas heller, nach unten etwas dunkler
        v = 1.0 - amount * rnd.random() - 0.02 * max(0.0, -p.normal.z)
        for li in p.loop_indices:
            ca.data[li].color = (v, v, v, 1.0)


# ------------------------------------------------------------------ Koerper aus Ringen (kantig)
def _sstep(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def _ring(center, side, front, up_len, f, b, n, p=2.0, phase=0.0):
    """Ein Ring aus n Punkten (Superellipse): side = Richtung zur Seite (Halbachse up_len),
    front = nach vorn (+f) bzw. hinten (b). p > 2 macht die Form kantiger (flache Brust)."""
    pts = []
    for k in range(n):
        t = 2 * math.pi * (k + phase) / n
        c, s = math.cos(t), math.sin(t)
        x = math.copysign(abs(c) ** (2.0 / p), c) * up_len
        y = math.copysign(abs(s) ** (2.0 / p), s) * (f if s > 0 else b)
        pts.append(center + side * x + front * y)
    return pts


def _loft(bm, rings, cap_start=True, cap_end=True):
    """Ringe zu einer Roehre verbinden; Rueckgabe: Liste der Vertex-Listen je Ring."""
    vs = [[bm.verts.new(p) for p in r] for r in rings]
    n = len(rings[0])
    for a, b in zip(vs, vs[1:]):
        for k in range(n):
            k2 = (k + 1) % n
            bm.faces.new((a[k], a[k2], b[k2], b[k]))
    if cap_start:
        bm.faces.new(list(reversed(vs[0])))
    if cap_end:
        bm.faces.new(vs[-1])
    return vs


# Rumpf: (z, halbe Breite, vorn, hinten, y-Versatz, Kantigkeit)
TORSO = [
    (0.885, 0.105, 0.075, 0.085, 0.0, 2.0),
    (0.93, 0.14, 0.088, 0.104, -0.004, 2.2),
    (0.99, 0.152, 0.092, 0.112, -0.004, 2.3),   # Gesaess
    (1.06, 0.146, 0.088, 0.1, 0.0, 2.3),
    (1.12, 0.132, 0.088, 0.09, 0.004, 2.4),     # Taille
    (1.2, 0.138, 0.096, 0.09, 0.006, 2.5),
    (1.28, 0.152, 0.11, 0.096, 0.008, 2.6),     # unterer Brustkorb
    (1.35, 0.166, 0.124, 0.102, 0.01, 2.7),     # Brustmuskel
    (1.415, 0.176, 0.118, 0.104, 0.008, 2.7),
    (1.465, 0.172, 0.096, 0.096, 0.0, 2.6),
    (1.505, 0.158, 0.078, 0.086, -0.006, 2.4),  # Schulterlinie
    (1.54, 0.13, 0.062, 0.074, -0.008, 2.2),    # kraeftiger Kapuzenmuskel
    (1.57, 0.094, 0.064, 0.07, -0.006, 2.1),
    (1.595, 0.086, 0.066, 0.068, -0.002, 2.2),   # Hals (kraeftig)
    (1.62, 0.078, 0.064, 0.062, 0.004, 2.1),
    (1.665, 0.07, 0.06, 0.058, 0.01, 2.0),
]
# Arm: (Abstand ab Schulter, oben/unten, vorn, hinten)
ARM = [
    (-0.06, 0.052, 0.058, 0.058),
    (0.0, 0.058, 0.066, 0.066),
    (0.05, 0.06, 0.066, 0.064),    # Deltamuskel
    (0.11, 0.06, 0.064, 0.06),
    (0.17, 0.056, 0.072, 0.056),   # Bizeps
    (0.24, 0.05, 0.058, 0.052),
    (0.3, 0.043, 0.045, 0.045),    # Ellbogen
    (0.36, 0.05, 0.056, 0.05),     # Unterarmmuskel
    (0.45, 0.041, 0.042, 0.039),
    (0.54, 0.03, 0.026, 0.026),
    (0.575, 0.029, 0.022, 0.022),  # Handgelenk
]
# Bein: (z, seitlich, vorn, hinten, x-Versatz)
LEG = [
    (1.0, 0.09, 0.085, 0.095, 0.0),
    (0.9, 0.094, 0.09, 0.094, 0.004),
    (0.8, 0.088, 0.094, 0.084, 0.004),  # Oberschenkel vorn kraeftig
    (0.69, 0.078, 0.084, 0.072, 0.002),
    (0.6, 0.064, 0.07, 0.06, 0.0),
    (0.52, 0.054, 0.058, 0.05, 0.0),    # Knie
    (0.46, 0.055, 0.05, 0.06, 0.0),
    (0.38, 0.06, 0.046, 0.074, -0.002),  # Wade
    (0.29, 0.05, 0.042, 0.058, -0.002),
    (0.2, 0.038, 0.036, 0.04, 0.0),
    (0.12, 0.034, 0.034, 0.036, 0.0),   # Knoechel
]


def build_body_loft():
    """Koerper aus Ringen wie bei einem handmodellierten Low-Poly-Modell: Rumpf, Arme und
    Beine als kantige Roehren mit Muskelformen. Gewichte fuer das Skelett werden direkt
    aus der Lage am Koerper gesetzt (Rumpf, Arm entlang, Bein entlang)."""
    bm = bmesh.new()
    weights = {}  # BMVert -> {Knochen: Gewicht}
    X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
    def tk(z):   # breiter Brustkorb, Hals bleibt
        return 1.0 + 0.13 * (1 - _sstep(1.5, 1.58, z)) * _sstep(0.9, 1.1, z)
    rings = [_ring(Vector((0, yo, z)), X, Y, hx * tk(z), f * (1 + 0.4 * (tk(z) - 1)), b, 16, p) for z, hx, f, b, yo, p in TORSO]
    for r, (z, *_rest) in zip(_loft(bm, rings), TORSO):
        for v in r:
            sh = _sstep(1.0, 1.17, z)
            hd = _sstep(1.6, 1.66, z)
            w = {"hips": 1 - sh, "chest": sh * (1 - hd), "head": hd}
            # Schulterecke geht ein wenig mit dem Oberarm mit
            if z > 1.38 and abs(v.co.x) > 0.11:
                k = 0.45 * _sstep(0.11, 0.17, abs(v.co.x)) * _sstep(1.38, 1.47, z)
                w = {n: g * (1 - k) for n, g in w.items()}
                w["sh_" + ("r" if v.co.x > 0 else "l")] = k
            weights[v] = w
    for s, sd in ((-1, "l"), (1, "r")):
        u = Vector((s * math.cos(ARM_A), 0, -math.sin(ARM_A)))
        upv = Vector((s * math.sin(ARM_A), 0, math.cos(ARM_A)))
        # Achse an der Schulter etwas tiefer: der Deltamuskel liegt unter der Schulterlinie
        rings = [_ring(Vector(arm_pt(s, d, -0.014 * max(0.0, 1.0 - d / 0.15))), upv, Y, a * 1.15, f * 1.15, b * 1.15, 10, 2.2, 0.5)
                 for d, a, f, b in ARM]
        for r, (d, *_rest) in zip(_loft(bm, rings), ARM):
            for v in r:
                c = _sstep(-0.05, 0.04, d)
                e = _sstep(0.27, 0.33, d)
                wr = _sstep(0.55, 0.585, d)
                weights[v] = {"chest": 1 - c, "sh_" + sd: c * (1 - e), "el_" + sd: e * (1 - wr), "wr_" + sd: wr}
        rings = [_ring(Vector((s * (HIP_X + xo), 0, z)), X, Y, sx * 1.15, f * 1.15, b * 1.15, 10, 2.2, 0.5) for z, sx, f, b, xo in LEG]
        for r, (z, *_rest) in zip(_loft(bm, rings), LEG):
            for v in r:
                h = _sstep(1.03, 0.88, z)
                k = _sstep(0.56, 0.47, z)
                a = _sstep(0.15, 0.1, z)
                weights[v] = {"hips": 1 - h, "hip_" + sd: h * (1 - k), "kn_" + sd: k * (1 - a), "an_" + sd: a}
    # Facetten: Quads in Dreiecke, Punkte leicht verrueckt (unregelmaessige Flaechen)
    rnd = random.Random(21)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])   # gespiegelte Arme zeigen sonst nach innen
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * rnd.uniform(-0.0025, 0.0025)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="ALTERNATE")
    ob = new_object("body", bm)
    # Vertex-Indizes bleiben beim to_mesh in Reihenfolge der Erzeugung
    add_mat(ob, "skin")
    groups = {}
    for i, (v, w) in enumerate(weights.items()):
        for n, g in w.items():
            if g > 0.001:
                if n not in groups:
                    groups[n] = ob.vertex_groups.new(name=n)
                groups[n].add([i], g, "REPLACE")
    return ob


def build_skin(body):
    """Sichtbare Haut = Kopie des Koerpers (gleiche Gewichte)."""
    b = bpy.data.objects.new("skin_body", body.data.copy())
    bpy.context.collection.objects.link(b)
    return b


# ------------------------------------------------------------------ Koerper (Skin-Modifier)
def build_body_smooth():
    """Rumpf, Arme, Beine als ein Stueck: ein Gerippe aus Punkten mit Radien, aus dem der
    Skin-Modifier eine geschlossene Huelle macht. Mehr Punkte = Muskelformen (Brust,
    Deltamuskel, Bizeps, Unterarm, Oberschenkel, Wade). Ergebnis noch glatt (fuer Kleidung)."""
    pts, edges, radii = [], [], []

    def p(co, rx, ry=None):
        pts.append(Vector(co))
        radii.append((rx, ry if ry is not None else rx))
        return len(pts) - 1

    def chain(*ids):
        for a, b in zip(ids, ids[1:]):
            edges.append((a, b))

    crotch = p((0, 0, 0.90), 0.13, 0.10)
    pelvis = p((0, 0, 0.98), 0.14, 0.106)
    waist = p((0, 0, 1.10), 0.126, 0.094)
    abdo = p((0, 0.003, 1.22), 0.138, 0.098)
    lchest = p((0, 0.016, 1.32), 0.17, 0.122)
    chest = p((0, 0.02, 1.40), 0.186, 0.128)
    upper = p((0, 0.0, 1.465), 0.176, 0.1)       # Schulterlinie, faellt zum Arm hin ab
    neck0 = p((0, -0.008, 1.56), 0.06, 0.058)      # schlanker, sichtbarer Hals
    neck1 = p((0, 0.0, HEAD_Z + 0.025), 0.054, 0.054)
    chain(crotch, pelvis, waist, abdo, lchest, chest, upper, neck0, neck1)
    for s in (-1, 1):
        sh = p(arm_pt(s, 0.0), 0.074)
        dl = p(arm_pt(s, 0.06, -0.004), 0.071, 0.068)      # Deltamuskel
        bi = p(arm_pt(s, 0.15, -0.006), 0.062, 0.066)      # Bizeps
        el0 = p(arm_pt(s, 0.255, -0.008), 0.054, 0.056)
        el = p(arm_pt(s, UPPER, -0.01), 0.05)
        fa = p(arm_pt(s, UPPER + 0.07, -0.01), 0.058, 0.052)  # Unterarmmuskel
        fa2 = p(arm_pt(s, UPPER + 0.17, -0.01), 0.046, 0.038)
        wr = p(arm_pt(s, UPPER + FORE, -0.01), 0.036, 0.028)
        chain(upper, sh, dl, bi, el0, el, fa, fa2, wr)
        hp = p((s * HIP_X, 0, HIP_Z), 0.098, 0.104)
        q1 = p((s * (HIP_X + 0.004), 0.006, 0.84), 0.094, 0.1)        # Oberschenkel
        q2 = p((s * (HIP_X + 0.004), 0.008, 0.71), 0.086, 0.092)
        q3 = p((s * (HIP_X + 0.004), 0.006, 0.6), 0.076, 0.078)
        kn = p((s * (HIP_X + 0.003), 0.0, KNEE_Z), 0.063, 0.064)
        c1 = p((s * (HIP_X + 0.003), -0.016, 0.39), 0.07, 0.076)       # Wade
        c2 = p((s * (HIP_X + 0.002), -0.008, 0.25), 0.054, 0.056)
        an = p((s * HIP_X, 0, ANKLE_Z + 0.02), 0.04, 0.044)
        chain(crotch, hp, q1, q2, q3, kn, c1, c2, an)
    me = bpy.data.meshes.new("body_src")
    me.from_pydata([tuple(v) for v in pts], edges, [])
    ob = bpy.data.objects.new("body", me)
    bpy.context.collection.objects.link(ob)
    sk = ob.modifiers.new("Skin", "SKIN")
    sk.use_smooth_shade = False
    sk.branch_smoothing = 0.4
    for i, r in enumerate(radii):
        ob.data.skin_vertices[0].data[i].radius = r
    ob.data.skin_vertices[0].data[crotch].use_root = True
    sub = ob.modifiers.new("Sub", "SUBSURF")
    sub.levels = 2
    ob = evaluated_copy(ob, "body")
    add_mat(ob, "skin")
    return ob


# ------------------------------------------------------------------ Kleidung aus dem Koerper
def shell(body, name, mat, keep, push, extra=None, cut=None):
    """Kopiert die Flaechen des (glatten) Koerpers, deren Mitte keep(c, n) erfuellt, und
    schiebt sie entlang der Normalen nach aussen (Kleidung sitzt locker darueber).
    cut(bm) darf vorher Schnittkanten einziehen, damit Ausschnitte saubere Raender haben."""
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.normal_update()
    if cut:
        cut(bm)
    kill = [f for f in bm.faces if not keep(f.calc_center_median(), f.normal)]
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


def thicken(ob, t, rim_mat=None):
    """Stoffdicke, damit Saeume als Kante sichtbar sind."""
    m = ob.modifiers.new("Sol", "SOLIDIFY")
    m.thickness = t
    m.offset = -1.0
    m.use_rim = True
    if rim_mat:
        m.material_offset_rim = add_mat(ob, rim_mat)
    return evaluated_copy(ob, ob.name)


def paint_faces(ob, mat, test):
    """Flaechen, fuer die test(center, normal) gilt, bekommen ein anderes Material."""
    idx = add_mat(ob, mat)
    for p in ob.data.polygons:
        if test(p.center, p.normal):
            p.material_index = idx


def v_neck_cut(c):
    """True, wenn die Stelle im Halsausschnitt liegt: rundes Loch um den Hals, vorn ein V."""
    r = math.hypot(c.x, c.y * 1.15)
    if c.z > 1.558 or (c.z > 1.51 and r < 0.1):
        return True
    if c.y > 0.02 and c.z > V_TIP:
        return abs(c.x) < V_W * (c.z - V_TIP) / (V_TOP - V_TIP)
    return False


V_TIP = 1.455  # Spitze des V-Ausschnitts
V_TOP = 1.57   # Hoehe, auf der V_W gilt
V_W = 0.068    # halbe Breite des V auf Hoehe V_TOP


def neck_cut(bm):
    """Schnittkanten entlang der beiden V-Linien und rund um den Hals."""
    for sx in (-1, 1):
        d = Vector((sx * V_W, 0, V_TOP - V_TIP)).normalized()
        n = Vector((d.z, 0, -sx * d.x)) if sx > 0 else Vector((-d.z, 0, d.x))
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector((0, 0, V_TIP)), plane_no=n)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector((0, 0, 1.51)), plane_no=Vector((0, 0, 1)))
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector((0, 0, 1.558)), plane_no=Vector((0, 0, 1)))
    bm.faces.ensure_lookup_table()


def zcut(bm, *zs):
    """Waagerechte Schnittkanten (saubere Saeume statt Dreieckszacken)."""
    for z in zs:
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector((0, 0, z)), plane_no=Vector((0, 0, 1)))


def arm_cut(bm, d):
    """Schnittkante quer zum Arm, d Meter ab der Schulter (Aermelsaum)."""
    for s in (-1, 1):
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        u = Vector((s * math.cos(ARM_A), 0, -math.sin(ARM_A)))
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector(arm_pt(s, d)), plane_no=u)


def jersey_cut(bm):
    neck_cut(bm)
    zcut(bm, 0.97)
    arm_cut(bm, 0.165)


def collar_strip(j, width=0.022, lift=0.004):
    """Kragen als sauberes Band entlang des Halsausschnitts (Rand des Trikots)."""
    src = bmesh.new()
    src.from_mesh(j.data)
    src.normal_update()
    edges = [e for e in src.edges if e.is_boundary and all(v.co.z > V_TIP - 0.03 and abs(v.co.x) < 0.14 for v in e.verts)]
    out = bmesh.new()
    inner, outer = {}, {}
    for e in edges:
        for v in e.verts:
            if v in inner:
                continue
            n = v.normal.normalized()
            # Richtung vom Rand ins Trikot hinein (tangential)
            into = Vector((0, 0, 0))
            for f in v.link_faces:
                into += f.calc_center_median() - v.co
            into = (into - n * into.dot(n)).normalized()
            inner[v] = out.verts.new(v.co + n * lift)
            outer[v] = out.verts.new(v.co + into * width + n * lift)
    for e in edges:
        a, b = e.verts
        try:
            out.faces.new((inner[a], inner[b], outer[b], outer[a]))
        except ValueError:
            pass
    bmesh.ops.recalc_face_normals(out, faces=out.faces[:])
    # nach aussen zeigen lassen
    for f in out.faces:
        c = f.calc_center_median()
        if f.normal.dot(Vector((c.x, c.y, 0))) < 0 and f.normal.z < 0.7:
            f.normal_flip()
    src.free()
    ob = new_object("collar", out)
    add_mat(ob, "collar")
    return ob


def build_jersey(body):
    def keep(c, n):
        if v_neck_cut(c):
            return False
        a, r = arm_coord(c)
        return 0.97 < c.z < 1.7 and not (a > 0.165 and r < 0.11)

    def push(co):
        d = 0.011 + max(0.0, 1.24 - co.z) * 0.12   # sitzt oben eng, faellt unten ueber die Hose
        a, r = arm_coord(co)
        if a > 0.04 and r < 0.11:
            d += 0.002                               # Aermel
        return d

    def hem(bm):
        for v in bm.verts:
            if v.co.z < 1.02 and abs(v.co.x) < 0.3:
                v.co.z -= 0.035                      # faellt ueber den Hosenbund
    j = shell(body, "jersey", "jersey", keep, push, hem, jersey_cut)
    j = facet(j, 1500)
    collar = thicken(collar_strip(j), 0.005)
    pi = add_mat(j, "panel")
    for p in j.data.polygons:
        c, n = p.center, p.normal
        ang = math.degrees(math.atan2(c.y, abs(c.x)))
        if c.z < 1.42 and -28.0 < ang < 18.0 and arm_coord(c)[1] > 0.11:
            p.material_index = pi
    j = thicken(j, 0.007)
    return j, collar


def build_shorts(body):
    def keep(c, n):
        return 0.68 < c.z < 1.07 and abs(c.x) < 0.3

    def push(co):
        return 0.022 + max(0.0, 0.95 - co.z) * 0.12  # weite, gerade Hosenbeine wie in der Vorlage
    s = shell(body, "shorts", "shorts", keep, push, cut=lambda bm: zcut(bm, 0.68, 1.07))
    s = facet(s, 700)
    return thicken(s, 0.007)


def build_trousers(body):
    """Lange Hose fuer Schiedsrichter und Linienrichter (bei Spielern unsichtbar)."""
    def keep(c, n):
        return 0.1 < c.z < 1.07 and abs(c.x) < 0.3

    def push(co):
        return 0.024 + max(0.0, 0.5 - co.z) * 0.02
    t = shell(body, "trousers", "trousers", keep, push)
    t = facet(t, 700)
    return thicken(t, 0.006)


def build_socks(body):
    def keep(c, n):
        return 0.105 < c.z < 0.33
    s = shell(body, "socks", "socks", keep, 0.005, cut=lambda bm: zcut(bm, 0.105, 0.33))
    s = facet(s, 300)
    return thicken(s, 0.005)


def build_body_lowpoly(body_smooth):
    """Sichtbare Haut: Koerper vereinfachen. Unter der Kleidung bleibt er (verdeckt)."""
    b = bpy.data.objects.new("skin_body", body_smooth.data.copy())
    bpy.context.collection.objects.link(b)
    return facet(b, 2600)


# ------------------------------------------------------------------ Knieschoner, Schuhe, Haende
def knee_pad(s):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=14, radius1=0.08, radius2=0.075, depth=0.17)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=2, use_grid_fill=False)
    for v in bm.verts:
        if v.co.y < 0:
            v.co.y *= 0.8        # hinten flacher (Kniekehle)
        else:
            v.co.y *= 1.16       # vorn gewoelbt
            v.co.y += 0.012 * (1.0 - (v.co.z / 0.085) ** 2)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(s * (HIP_X + 0.003), 0.008, KNEE_Z - 0.008))
    ob = new_object("pad_" + ("l" if s < 0 else "r"), bm)
    add_mat(ob, "pads")
    ob = thicken(ob, 0.016)
    return facet(ob, 260)


def shoe(s):
    """Hoher Volleyballschuh: Oberteil bis ueber den Knoechel, dicke Sohle, farbige
    Seitenstreifen und Fersenkappe (Material accent)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=3, use_grid_fill=True)
    for v in bm.verts:
        x, y, z = v.co
        y2 = y + 0.5   # 0 hinten .. 1 vorn
        z2 = z + 0.5   # 0 unten .. 1 oben
        w = 0.118 * (1.0 - 0.28 * max(0.0, y2 - 0.62) / 0.38)
        top = 0.16 - 0.1 * min(1.0, max(0.0, (y2 - 0.25) / 0.6))   # hinten hoch, vorn flach
        v.co = Vector((x * w * (0.92 + 0.08 * (1 - z2)), -0.09 + y2 * 0.31, 0.03 + z2 * top))
    ob = new_object("shoe_" + ("l" if s < 0 else "r"), bm)
    for v in ob.data.vertices:
        v.co.x += s * HIP_X
    add_mat(ob, "shoes")
    ob = facet(ob, 420, smooth_levels=1)
    ai = add_mat(ob, "accent")
    for p in ob.data.polygons:
        c, n = p.center, p.normal
        side_band = abs(n.x) > 0.55 and 0.05 < c.z < 0.1 and -0.03 < c.y < 0.15 and abs((c.z - 0.05) - (c.y + 0.03) * 0.25) < 0.025
        heel = c.y < -0.06 and c.z > 0.06
        collar = c.z > 0.16
        if side_band or heel or collar:
            p.material_index = ai
    # Sohle
    sb = bmesh.new()
    bmesh.ops.create_cube(sb, size=1.0)
    bmesh.ops.subdivide_edges(sb, edges=sb.edges[:], cuts=2, use_grid_fill=True)
    for v in sb.verts:
        x, y, z = v.co
        y2 = y + 0.5
        w = 0.128 * (1.0 - 0.25 * max(0.0, y2 - 0.6) / 0.4)
        v.co = Vector((x * w + s * HIP_X, -0.098 + y2 * 0.33, (z + 0.5) * 0.036 - 0.003 + max(0.0, y2 - 0.85) * 0.08 * (z + 0.5)))
    so = new_object("sole_" + ("l" if s < 0 else "r"), sb)
    add_mat(so, "sole")
    so = facet(so, 140, smooth_levels=1)
    return [ob, so]


def hand(s):
    """Hand in T-Haltung (Handflaeche nach unten): Handteller, eng anliegende Finger, Daumen."""
    x0 = s * (SH_X + UPPER + FORE)
    z0 = SH_Z - 0.01
    bm = bmesh.new()

    def block(cx, cy, cz, sx, sy, sz, taper=1.0):
        r = bmesh.ops.create_cube(bm, size=1.0)
        for v in r["verts"]:
            x, y, z = v.co
            k = 1.0 + (taper - 1.0) * (s * x + 0.5)
            v.co = Vector((cx + x * sx, cy + y * sy * k, cz + z * sz * k))
        return r["verts"]

    block(x0 + s * 0.048, 0, z0, 0.1, 0.088, 0.034, 0.92)
    for i in range(4):
        y = -0.031 + i * 0.0205
        ln = [0.072, 0.084, 0.08, 0.064][i]
        block(x0 + s * (0.096 + ln * 0.5), y, z0 - 0.003, ln, 0.02, 0.022, 0.8)
    tv = block(x0 + s * 0.04, 0.056, z0 - 0.01, 0.075, 0.024, 0.025, 0.8)
    for v in tv:
        v.co.y += abs(v.co.x - x0) * 0.3
    for v in bm.verts:
        v.co = to_a_pose(v.co, s)
    ob = new_object("hand_" + ("l" if s < 0 else "r"), bm)
    add_mat(ob, "skin")
    return facet(ob, 220, smooth_levels=1)


# ------------------------------------------------------------------ Kopf (ohne Augen und Mund)
# Kopf: (z relativ zur Kopfmitte, halbe Breite, vorn, hinten, y-Versatz, Kantigkeit). Wenige,
# grosse Flaechen wie in der Vorlage: flache Stirn, kantiger breiter Kiefer, eckiges Kinn.
HEAD_RINGS = [
    (-0.126, 0.038, 0.02, 0.03, 0.07, 3.2),    # Kinn unten (flach, breit)
    (-0.11, 0.054, 0.03, 0.06, 0.06, 3.6),     # Kinn vorn
    (-0.085, 0.066, 0.04, 0.08, 0.045, 3.6),
    (-0.058, 0.07, 0.05, 0.095, 0.035, 3.5),   # Kieferwinkel
    (-0.024, 0.074, 0.062, 0.1, 0.025, 3.0),   # Wange
    (0.01, 0.078, 0.07, 0.105, 0.02, 2.8),     # Wangenknochen, Augen
    (0.04, 0.079, 0.072, 0.107, 0.018, 2.6),   # Brauen
    (0.075, 0.077, 0.066, 0.105, 0.012, 2.4),  # Stirn
    (0.105, 0.068, 0.052, 0.095, 0.006, 2.2),
    (0.128, 0.048, 0.035, 0.07, 0.0, 2.0),
    (0.14, 0.02, 0.015, 0.03, -0.004, 2.0),
]


def _wedge(bm, pts, faces):
    vs = [bm.verts.new(Vector(p)) for p in pts]
    for f in faces:
        bm.faces.new([vs[i] for i in f])


def head():
    """Kantiger Kopf wie in der Vorlage: kein Mund, keine Augen, nur grosse Flaechen fuer
    Stirn, Brauenbogen, Augenhoehlen, Wangenknochen, Nase, breiten Kiefer und eckiges Kinn."""
    bm = bmesh.new()
    X, Y = Vector((1, 0, 0)), Vector((0, 1, 0))
    n = 12
    rings = [_ring(Vector((0, yo, HEAD_C + z)), X, Y, hx, f, b, n, p, 0.0) for z, hx, f, b, yo, p in HEAD_RINGS]
    vs = _loft(bm, rings)
    front = n // 4
    for ri, (z, *_r) in enumerate(HEAD_RINGS):
        r = vs[ri]
        if abs(z - 0.01) < 0.001:       # Augenhoehlen
            for dk in (-1, 1):
                r[front + dk].co.y -= 0.013
                r[front + dk].co.z += 0.004
        if abs(z + 0.024) < 0.001:      # Wangenknochen treten vor
            for dk in (-2, 2):
                r[front + dk].co.x += math.copysign(0.004, r[front + dk].co.x)
                r[front + dk].co.y += 0.006
        if abs(z + 0.058) < 0.001:      # Kieferkante
            for dk in (-2, 2):
                r[front + dk].co.x += math.copysign(0.006, r[front + dk].co.x)
    hc = HEAD_C
    # Nase: Keil von der Nasenwurzel zur Spitze
    _wedge(bm, [(-0.008, 0.086, hc + 0.03), (0.008, 0.086, hc + 0.03), (0, 0.108, hc - 0.022),
                (-0.014, 0.088, hc - 0.028), (0.014, 0.088, hc - 0.028), (0, 0.096, hc - 0.032)],
           [(0, 3, 2), (0, 2, 1), (1, 2, 4), (3, 5, 2), (2, 5, 4)])
    # Brauenbogen: Leiste ueber den Augen, unten schraeg (wirft Schatten in die Augenhoehlen)
    bx = [-0.068, -0.034, 0.0, 0.034, 0.068]
    top, edge, under = [], [], []
    for x in bx:
        yf = 0.092 - 3.2 * x * x
        top.append(bm.verts.new((x, yf - 0.006, hc + 0.064)))
        edge.append(bm.verts.new((x, yf + 0.004, hc + 0.04 + abs(x) * 0.12)))   # Brauen fallen zur Mitte ab
        under.append(bm.verts.new((x, yf - 0.012, hc + 0.026 + abs(x) * 0.1)))
    for i in range(len(bx) - 1):
        bm.faces.new((top[i], top[i + 1], edge[i + 1], edge[i]))
        bm.faces.new((edge[i], edge[i + 1], under[i + 1], under[i]))
    for s in (-1, 1):  # Ohren: flache Keile an den Seiten
        _wedge(bm, [(s * 0.074, -0.0, hc + 0.035), (s * 0.088, -0.016, hc + 0.03), (s * 0.086, -0.022, hc - 0.03),
                    (s * 0.074, -0.004, hc - 0.035), (s * 0.072, -0.03, hc + 0.0)],
               [(0, 1, 2, 3) if s > 0 else (3, 2, 1, 0), (1, 4, 2) if s > 0 else (2, 4, 1)])
    for v in bm.verts:   # etwas breiter als hoch, wie in der Vorlage
        v.co.x *= 1.08
        v.co.y *= 1.03
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="ALTERNATE")
    bm.normal_update()
    ob = new_object("head", bm)
    add_mat(ob, "skin")
    return ob


# ------------------------------------------------------------------ Frisuren (kantige Straehnen)
def _scalp(u, v, lift=0.0):
    """Punkt auf dem Schaedel: u = Winkel um die Hochachse (0 = vorn), v = Hoehe 0..1."""
    el = v * math.pi / 2.0
    x = math.sin(u) * math.cos(el) * 0.088
    y = math.cos(u) * math.cos(el) * 0.101 + 0.004
    z = math.sin(el) * 0.135 + 0.008
    n = Vector((x / 0.088 ** 2, (y - 0.004) / 0.101 ** 2, (z - 0.008) / 0.135 ** 2)).normalized()
    return Vector((x, y, z + HEAD_C)) + n * lift, n


def _tuft(bm, root, d, width, length, rnd, sides=4, bend=None, normal=None, flat=1.0):
    """Eine Straehne als spitze, leicht gebogene Pyramide. Mit normal und flat < 1 wird sie
    flach wie ein breites Blatt (liegt am Kopf an)."""
    d = d.normalized()
    if normal is not None:
        b = (normal - d * normal.dot(d)).normalized()
        a = d.cross(b).normalized()
        rot = 0.0
    else:
        a = d.orthogonal().normalized()
        b = d.cross(a).normalized()
        rot = rnd.uniform(0, math.pi)
    base = []
    for k in range(sides):
        t = rot + 2 * math.pi * k / sides
        base.append(bm.verts.new(root + (a * math.cos(t) + b * math.sin(t) * flat) * width * rnd.uniform(0.85, 1.15)))
    off = bend * length if bend is not None else Vector()
    mid_c = root + d * length * 0.5 + off * 0.25
    mid = [bm.verts.new(mid_c + (bv.co - root) * 0.75) for bv in base]
    tip = bm.verts.new(root + d * length + off * 0.6)
    for k in range(sides):
        k2 = (k + 1) % sides
        bm.faces.new((base[k], base[k2], mid[k2], mid[k]))
        bm.faces.new((mid[k], mid[k2], tip))
    bm.faces.new(list(reversed(base)))


def _in_hair(u, v):
    fu = math.cos(u)
    side = abs(math.sin(u))
    lim = 0.42 * max(0.0, fu) ** 1.5 - 0.05 * side - 0.3 * max(0.0, -fu)
    if side > 0.8 and fu > -0.3:      # Koteletten vor den Ohren
        lim = min(lim, -0.12)
    return v > lim


def _hair_cap(name, lift, vmin_back=-0.25):
    """Kappe: Schaedelteil oberhalb des Haaransatzes, etwas nach aussen versetzt."""
    bm = bmesh.new()
    nu, nv = 22, 10
    grid = {}
    for j in range(nv + 1):
        v = vmin_back + (1.0 - vmin_back) * j / nv
        for i in range(nu):
            u = -math.pi + 2 * math.pi * i / nu
            co, _n = _scalp(u, min(v, 0.999), lift)
            grid[i, j] = bm.verts.new(co)
    top = bm.verts.new(_scalp(0, 1.0, lift)[0])
    for j in range(nv):
        for i in range(nu):
            i2 = (i + 1) % nu
            u = -math.pi + 2 * math.pi * (i + 0.5) / nu
            v = vmin_back + (1.0 - vmin_back) * (j + 0.5) / nv
            if _in_hair(u, v):
                bm.faces.new((grid[i, j], grid[i2, j], grid[i2, j + 1], grid[i, j + 1]))
    for i in range(nu):
        bm.faces.new((grid[i, nv], grid[(i + 1) % nu, nv], top))
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    # Rand an die Kopfhaut ziehen, damit keine Kante absteht
    for v in bm.verts:
        if v.is_boundary:
            v.co -= (v.co - Vector((0, 0, HEAD_C))).normalized() * lift * 0.9
    return bm


def _finish_hair(name, bm, seed):
    rnd = random.Random(seed)
    for v in bm.verts:
        v.co += Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * 0.001
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="ALTERNATE")
    ob = new_object(name, bm)
    add_mat(ob, "hair")
    return ob


def _side_back_tufts(bm, rnd, count, length, vmax=0.5):
    """Seiten und Hinterkopf: flache Straehnen, die nach hinten unten am Kopf anliegen."""
    for i in range(count):
        u = rnd.uniform(-math.pi, math.pi)
        v = rnd.uniform(-0.2, vmax)
        if not _in_hair(u, v) or (math.cos(u) > 0.5 and v < 0.35):
            continue
        root, n = _scalp(u, v, 0.008)
        d = n * 0.15 + Vector((0, -0.75, -0.5)) + Vector((math.sin(u) * 0.1, 0, 0))
        _tuft(bm, root, d, rnd.uniform(0.035, 0.045), length * rnd.uniform(0.8, 1.2), rnd, normal=n, flat=0.35)


def _hair_shell(nu, nv, vmin, keep, lift_fn, spike_fn, edge_fn=None):
    """Frisur als ein geschlossenes, kantiges Volumen ueber dem Schaedel: Hoehe je Punkt aus
    lift_fn(u, v), einzelne Punkte werden mit spike_fn zu Spitzen herausgezogen. Der Rand
    liegt auf der Kopfhaut auf (keine Luecke). Ergibt grosse, klare Flaechen wie in der Vorlage."""
    bm = bmesh.new()
    grid, nrm = {}, {}
    for j in range(nv + 1):
        v = vmin + (1.0 - vmin) * j / nv
        for i in range(nu):
            u = -math.pi + 2 * math.pi * (i + 0.5 * (j % 2)) / nu
            co, n = _scalp(u, min(v, 0.995), 0.0)
            grid[i, j] = bm.verts.new(co)
            nrm[i, j] = (u, v, n)
    top = bm.verts.new(_scalp(0, 1.0, 0.0)[0])
    cells = set()
    for j in range(nv):
        for i in range(nu):
            u = -math.pi + 2 * math.pi * (i + 0.5) / nu
            v = vmin + (1.0 - vmin) * (j + 0.5) / nv
            if keep(u, v):
                cells.add((i, j))
                bm.faces.new((grid[i, j], grid[(i + 1) % nu, j], grid[(i + 1) % nu, j + 1], grid[i, j + 1]))
    for i in range(nu):
        bm.faces.new((grid[i, nv], grid[(i + 1) % nu, nv], top))
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    # Hoehe und Spitzen; Randpunkte bleiben auf der Haut
    for (i, j), vert in grid.items():
        if not vert.is_valid:
            continue
        u, v, n = nrm[i, j]
        if vert.is_boundary:
            vert.co += n * 0.003
            if edge_fn:
                vert.co += edge_fn(u, v, n, i, j)
            continue
        vert.co += n * lift_fn(u, v) + spike_fn(u, v, n, i, j)
    top.co += Vector((0, 0, lift_fn(0.0, 1.0))) + spike_fn(0.0, 1.0, Vector((0, 0, 1)), 0, nv + 1)
    # Unterseite schliessen: Rand zum Kopf hin ist offen, das Volumen sitzt auf dem Kopf
    return bm


def hair_variants():
    out = []
    # 0: wie die Vorlage: volles Haar, oben und vorn grosse Spitzen nach oben, leicht zur
    #    rechten Seite gekaemmt, Seiten anliegend, Koteletten, Stirn mit Zacken
    rnd = random.Random(51)

    def lift0(u, v):
        front = max(0.0, math.cos(u))
        side = abs(math.sin(u))
        return 0.01 + 0.012 * max(0.0, v) + 0.012 * side * min(1.0, max(0.0, v) / 0.5) + 0.004 * front * max(0.0, v - 0.4)

    def spike0(u, v, n, i, j):
        if v < 0.35 or (i + j) % 2:
            return Vector()
        front = max(0.0, math.cos(u))
        d = n * 1.0 + Vector((0.3 + 0.6 * math.sin(u), 0.35 * front - 0.3 * (1 - front), 0.3))
        big = 1.5 if v > 0.6 and rnd.random() < 0.5 else 1.0
        return d.normalized() * rnd.uniform(0.014, 0.03) * big * (0.6 + 0.5 * v)

    def edge0(u, v, n, i, j):
        if math.cos(u) > 0.4 and i % 2 == 0:   # Stirn: Zacken fallen leicht nach vorn
            return Vector((0, 0.006, -0.008))
        return Vector()
    bm = _hair_shell(20, 7, -0.3, _in_hair, lift0, spike0, edge0)
    out.append(_finish_hair("hair_0", bm, 1))
    # 1: sehr kurz, kleine Zacken
    rnd = random.Random(52)
    bm = _hair_shell(20, 6, -0.3, _in_hair, lambda u, v: 0.008 + 0.008 * max(0.0, v),
                     lambda u, v, n, i, j: n * rnd.uniform(0.0, 0.008) if (i + j) % 2 == 0 else Vector())
    out.append(_finish_hair("hair_1", bm, 2))
    # 2: laenger, Seitenscheitel, nach rechts und hinten gekaemmt, hinten bis in den Nacken
    rnd = random.Random(53)
    keep2 = lambda u, v: _in_hair(u, v) or (math.cos(u) < -0.4 and v > -0.45)

    def spike2(u, v, n, i, j):
        if (i + j) % 2:
            return Vector()
        flow = Vector((0.9, -0.2, -0.4)) if math.cos(u) > -0.2 else Vector((0.1, -0.6, -0.8))
        return (n * 0.3 + flow).normalized() * rnd.uniform(0.02, 0.04)
    bm = _hair_shell(20, 8, -0.45, keep2, lambda u, v: 0.016 + 0.022 * max(0.0, v), spike2)
    out.append(_finish_hair("hair_2", bm, 3))
    # 3: lockig: dichtes Volumen mit vielen kleinen Beulen
    rnd = random.Random(54)
    bm = _hair_shell(28, 10, -0.3, _in_hair, lambda u, v: 0.024 + 0.02 * max(0.0, v),
                     lambda u, v, n, i, j: n * rnd.uniform(-0.006, 0.014))
    out.append(_finish_hair("hair_3", bm, 4))
    return out


# ------------------------------------------------------------------ Logo und Markierungen
def surface_hit(obj, origin, direction):
    """Punkt und Normale auf obj entlang eines Strahls (fuer Logo und Nummern)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    tree = BVHTree.FromBMesh(bm)
    loc, nrm, _i, _d = tree.ray_cast(Vector(origin), Vector(direction).normalized())
    bm.free()
    return loc, nrm


def logo(name, at, nrm, size):
    """Kleines Dreieck-Logo flach auf der Oberflaeche."""
    bm = bmesh.new()
    pts = [Vector((-0.5, -0.36, 0)), Vector((0.5, -0.36, 0)), Vector((0, 0.5, 0))]
    vs = [bm.verts.new(p * size) for p in pts]
    vb = [bm.verts.new(p * size + Vector((0, 0, -0.003))) for p in pts]
    bm.faces.new(vs)
    for a in range(3):
        b = (a + 1) % 3
        bm.faces.new([vs[b], vs[a], vb[a], vb[b]])
    rot = Vector((0, 0, 1)).rotation_difference(nrm).to_matrix().to_4x4()
    # Dreieck aufrecht halten (Spitze nach oben)
    up_fix = Vector((0, 0, 1)).rotation_difference(nrm)
    for v in bm.verts:
        v.co = Matrix.Translation(at + nrm * 0.004) @ rot @ Matrix.Rotation(0, 4, "Z") @ v.co
    ob = new_object(name, bm)
    add_mat(ob, "logo")
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
        ("sh_" + _sd, arm_pt(_s, 0.0), arm_pt(_s, UPPER, -0.01), "chest"),
        ("el_" + _sd, arm_pt(_s, UPPER, -0.01), arm_pt(_s, UPPER + FORE, -0.01), "sh_" + _sd),
        ("wr_" + _sd, arm_pt(_s, UPPER + FORE, -0.01), arm_pt(_s, UPPER + FORE + 0.18, -0.01), "el_" + _sd),
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


def bind(rig, body_smooth, meshes, rigid):
    """Glatten Koerper automatisch (Waermeverteilung) an die Knochen binden. Alle anderen
    weichen Teile (Haut, Kleidung) uebernehmen die Gewichte der naechsten Koerperstelle,
    damit sie genau zusammen gehen. Starre Teile haengen ganz an einem Knochen."""
    bpy.ops.object.select_all(action="DESELECT")
    body_smooth.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    if body_smooth.vertex_groups:
        body_smooth.parent = rig   # Gewichte stehen schon (build_body_loft)
        body_smooth.modifiers.new("Armature", "ARMATURE").object = rig
    else:
        bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    names = [g.name for g in body_smooth.vertex_groups]
    bw = []
    for v in body_smooth.data.vertices:
        bw.append({names[g.group]: g.weight for g in v.groups if g.weight > 0.001})
    bm = bmesh.new()
    bm.from_mesh(body_smooth.data)
    bm.faces.ensure_lookup_table()
    tree = BVHTree.FromBMesh(bm)
    for m in meshes:
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
            acc, tot = {}, 0.0
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
        rest = pb.bone.matrix_local.to_3x3()
        world_rot = Matrix.Rotation(s * (math.radians(88.0) - ARM_A), 3, "Y")
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (rest.inverted() @ world_rot @ rest).to_quaternion()
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    for m in meshes:
        mod = next(md for md in m.modifiers if md.type == "ARMATURE")
        co = [v.co.copy() for v in m.evaluated_get(dg).data.vertices]
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


def render_preview(folder, tag, hide=()):
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    scn.cycles.samples = 32
    scn.cycles.device = "CPU"
    scn.render.resolution_x = 700
    scn.render.resolution_y = 900
    scn.view_settings.view_transform = "Standard"
    if scn.world is None:
        world = bpy.data.worlds.new("w")
        world.use_nodes = True
        world.node_tree.nodes["Background"].inputs[0].default_value = (0.09, 0.09, 0.1, 1)
        world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
        scn.world = world
        key = bpy.data.objects.new("key", bpy.data.lights.new("key", "SUN"))
        key.data.energy = 4.5
        key.rotation_euler = (math.radians(45), math.radians(-15), math.radians(35))
        scn.collection.objects.link(key)
        fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "SUN"))
        fill.data.energy = 1.0
        fill.rotation_euler = (math.radians(70), math.radians(20), math.radians(-140))
        scn.collection.objects.link(fill)
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        cam.data.lens = 85
        scn.collection.objects.link(cam)
        scn.camera = cam
    cam = scn.camera
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.hide_render = o.name in hide
    views = {"front": ((0, 9.5, 1.0), 1.0), "side": ((9.5, 0, 1.0), 1.0), "back": ((0, -9.5, 1.0), 1.0), "face": ((0.5, 1.5, 1.8), 1.72), "head": ((0.0, 1.3, 1.77), 1.75)}
    for vname, (loc, tz) in views.items():
        cam.location = loc
        d = Vector((0, 0, tz)) - cam.location
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        scn.render.filepath = f"{folder}/{tag}_{vname}.png"
        bpy.ops.render.render(write_still=True)


def main():
    reset()
    body_smooth = build_body_loft()
    jersey, collar = build_jersey(body_smooth)
    shorts = build_shorts(body_smooth)
    socks = build_socks(body_smooth)
    trousers = build_trousers(body_smooth)
    skin = build_skin(body_smooth)
    soft = [skin, jersey, collar, shorts, socks, trousers]
    rigid = {}
    parts = list(soft)
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
    hd = head()
    parts.append(hd)
    rigid[hd.name] = "head"
    hairs = hair_variants()
    for h in hairs:
        rigid[h.name] = "head"
    # Logos: links auf der Brust, rechts auf der Hose
    loc, n = surface_hit(jersey, (-0.085, 0.6, 1.43), (0, -1, 0))
    lg = logo("logo_chest", loc, n, 0.04)
    parts.append(lg)
    rigid[lg.name] = "chest"
    loc, n = surface_hit(shorts, (0.11, 0.6, 0.78), (0, -1, 0))
    lg2 = logo("logo_shorts", loc, n, 0.034)
    soft.append(lg2)
    parts.append(lg2)
    # Markierungen fuer die Nummern (Godot-Koordinaten, Ruhehaltung)
    def gd(v):
        return [round(v.x, 4), round(v.z, 4), round(-v.y, 4)]
    markers = {}
    for key, ob, origin, direction, bone in [
        ("num_front", jersey, (0, 0.6, 1.33), (0, -1, 0), "chest"),
        ("num_back", jersey, (0, -0.6, 1.36), (0, 1, 0), "chest"),
        ("num_shorts", shorts, (-0.11, 0.6, 0.79), (0, -1, 0), "hip_l"),
    ]:
        loc, n = surface_hit(ob, origin, direction)
        markers[key] = {"bone": bone, "pos": gd(loc), "normal": gd(n)}
    all_meshes = parts + hairs
    for m in all_meshes:
        facet_colors(m)
    flat_shade(all_meshes)
    if PREVIEW:
        render_preview(PREVIEW, "tpose", hide={"body", "trousers", "hair_1", "hair_2", "hair_3"})
    rig = build_armature()
    bind(rig, body_smooth, all_meshes, rigid)
    bpy.data.objects.remove(body_smooth)
    lower_arms(rig, all_meshes)
    if PREVIEW:
        render_preview(PREVIEW, "rest", hide={"trousers", "hair_1", "hair_2", "hair_3"})
        for k in (1, 2, 3):
            hide = {"trousers"} | {f"hair_{i}" for i in range(4) if i != k}
            scn = bpy.context.scene
            cam = scn.camera
            for o in bpy.data.objects:
                if o.type == "MESH":
                    o.hide_render = o.name in hide
            cam.location = (0.5, 1.5, 1.8)
            cam.rotation_euler = (Vector((0, 0, 1.72)) - cam.location).to_track_quat("-Z", "Y").to_euler()
            scn.render.filepath = f"{PREVIEW}/hair_{k}.png"
            bpy.ops.render.render(write_still=True)
    tris = sum(len(p.vertices) - 2 for m in all_meshes for p in m.data.polygons)
    for m in all_meshes:
        print("TEIL", m.name, len(m.data.polygons))
    # Ein Mesh fuer den Koerper (je Material eine Flaeche), Frisuren getrennt
    bpy.ops.object.select_all(action="DESELECT")
    for m in parts:
        m.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    parts[0].name = "player"
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False,
                              export_apply=False, export_animations=False, export_skins=True,
                              export_yup=True, export_def_bones=False,
                              export_vertex_color="ACTIVE", export_all_vertex_colors=False)
    with open(OUT.rsplit(".", 1)[0] + "_markers.json", "w") as f:
        json.dump(markers, f, indent=1)
    print("FERTIG", OUT, "Dreiecke:", tris)


main()
