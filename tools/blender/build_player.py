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
HEAD_Z = 1.645   # Kopfgelenk (oberes Halsende)
HEAD_C = HEAD_Z + 0.115  # Kopfmitte

# Vorschaufarben (im Spiel kommen die Farben vom Team)
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
    pelvis = p((0, 0, 0.98), 0.158, 0.112)
    waist = p((0, 0, 1.10), 0.138, 0.096)
    abdo = p((0, 0.003, 1.22), 0.15, 0.102)
    lchest = p((0, 0.01, 1.33), 0.176, 0.116)
    chest = p((0, 0.014, 1.42), 0.196, 0.12)
    upper = p((0, 0.0, 1.50), 0.205, 0.11)
    neck0 = p((0, -0.006, 1.585), 0.072, 0.068)
    neck1 = p((0, 0.0, HEAD_Z + 0.025), 0.062, 0.06)
    chain(crotch, pelvis, waist, abdo, lchest, chest, upper, neck0, neck1)
    for s in (-1, 1):
        sh = p((s * SH_X, 0, SH_Z), 0.083)
        dl = p((s * (SH_X + 0.07), 0, SH_Z - 0.004), 0.08, 0.074)       # Deltamuskel
        bi = p((s * (SH_X + 0.16), 0, SH_Z - 0.006), 0.066, 0.07)       # Bizeps
        el0 = p((s * (SH_X + 0.255), 0, SH_Z - 0.008), 0.054, 0.056)
        el = p((s * (SH_X + UPPER), 0, SH_Z - 0.01), 0.05)
        fa = p((s * (SH_X + UPPER + 0.07), 0, SH_Z - 0.01), 0.058, 0.052)  # Unterarmmuskel
        fa2 = p((s * (SH_X + UPPER + 0.17), 0, SH_Z - 0.01), 0.046, 0.038)
        wr = p((s * (SH_X + UPPER + FORE), 0, SH_Z - 0.01), 0.036, 0.028)
        chain(upper, sh, dl, bi, el0, el, fa, fa2, wr)
        hp = p((s * HIP_X, 0, HIP_Z), 0.11, 0.112)
        q1 = p((s * (HIP_X + 0.006), 0.006, 0.84), 0.108, 0.11)        # Oberschenkel
        q2 = p((s * (HIP_X + 0.006), 0.008, 0.71), 0.098, 0.1)
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
    if c.z > 1.54 and r < 0.088:
        return True
    if c.y > 0.02 and c.z > V_TIP:
        return abs(c.x) < V_W * (c.z - V_TIP) / (1.6 - V_TIP)
    return False


V_TIP = 1.49   # Spitze des V-Ausschnitts
V_W = 0.068    # halbe Breite des V auf Hoehe 1.6


def neck_cut(bm):
    """Schnittkanten entlang der beiden V-Linien und rund um den Hals."""
    for sx in (-1, 1):
        d = Vector((sx * V_W, 0, 1.6 - V_TIP)).normalized()
        n = Vector((d.z, 0, -sx * d.x)) if sx > 0 else Vector((-d.z, 0, d.x))
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector((0, 0, V_TIP)), plane_no=n)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector((0, 0, 1.54)), plane_no=Vector((0, 0, 1)))
    bm.faces.ensure_lookup_table()


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
        return 0.97 < c.z < 1.7 and abs(c.x) < SH_X + 0.165

    def push(co):
        d = 0.015 + max(0.0, 1.32 - co.z) * 0.05   # unten etwas weiter
        if abs(co.x) > SH_X + 0.04:
            d += 0.005                               # Aermel etwas weiter
        return d

    def hem(bm):
        for v in bm.verts:
            if v.co.z < 1.02 and abs(v.co.x) < 0.3:
                v.co.z -= 0.035                      # faellt ueber den Hosenbund
    j = shell(body, "jersey", "jersey", keep, push, hem, neck_cut)
    j = facet(j, 1500)
    collar = thicken(collar_strip(j), 0.005)
    pi = add_mat(j, "panel")
    for p in j.data.polygons:
        c, n = p.center, p.normal
        if abs(c.x) < SH_X + 0.01 and c.z < 1.43 and abs(n.x) > 0.8:
            p.material_index = pi
    j = thicken(j, 0.007)
    return j, collar


def build_shorts(body):
    def keep(c, n):
        return 0.665 < c.z < 1.07 and abs(c.x) < 0.3

    def push(co):
        return 0.018 + max(0.0, 0.93 - co.z) * 0.06  # Beine weiten sich leicht nach unten
    s = shell(body, "shorts", "shorts", keep, push)
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
    s = shell(body, "socks", "socks", keep, 0.005)
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
    ob = new_object("hand_" + ("l" if s < 0 else "r"), bm)
    add_mat(ob, "skin")
    return facet(ob, 220, smooth_levels=1)


# ------------------------------------------------------------------ Kopf (ohne Augen und Mund)
def head():
    """Kantiger Kopf wie in der Vorlage: kein Mund, keine Augen, nur Flaechen fuer Stirn,
    Brauenbogen, Augenhoehlen, Wangenknochen, gerade Nase, kraeftigen Kiefer und Kinn."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=40, v_segments=28, radius=1.0)
    for v in bm.verts:
        x, y, z = v.co  # Einheitskugel, y = vorn
        w = 0.089
        if z < -0.25:                        # Kiefer bis zum Kieferwinkel breit, dann zum Kinn
            t = (-z - 0.25) / 0.75
            w *= 1.0 - 0.03 * t - 0.3 * max(0.0, t - 0.6) / 0.4
        d = 0.104 if y < 0 else 0.098
        if y < 0 and z > -0.3:
            d *= 1.05                        # Hinterkopf
        h = 0.114 if z > 0 else 0.108
        if z < -0.82:
            z = -0.82 - (-z - 0.82) * 0.4    # Kinn unten flach
        nx, ny, nz = x * w, y * d, z * h
        if y > 0.5:                          # Gesicht vorn flacher
            ny -= (y - 0.5) * 0.03
        if abs(x) < 0.3 and -0.45 < z < 0.2 and y > 0.7:   # Nase
            k = (1 - abs(x) / 0.3) ** 1.5
            prof = max(0.0, 1.0 - abs(z + 0.24) / 0.26)
            ny += 0.024 * k * (0.35 + 0.65 * prof)
        if abs(x) < 0.75 and 0.1 < z < 0.32 and y > 0.6:   # Brauenbogen
            ny += 0.006 * (1 - abs(z - 0.21) / 0.11)
        if 0.22 < abs(x) < 0.62 and -0.04 < z < 0.12 and y > 0.65:  # Augenhoehlen
            ny -= 0.007
        if 0.45 < abs(x) < 0.85 and -0.28 < z < -0.02 and y > 0.3:  # Wangenknochen
            nx += math.copysign(0.004, x)
        if z < -0.62 and abs(x) > 0.45:      # kantiger Kieferwinkel
            nx += math.copysign(0.004, x)
        if z < -0.8 and y > 0.35:            # Kinn nach vorn
            ny += 0.008
        v.co = Vector((nx, ny + 0.002, nz + HEAD_C))
    for s in (-1, 1):  # Ohren: flache Halbschalen
        r = bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=6, radius=1.0)
        for v in r["verts"]:
            x, y, z = v.co
            v.co = Vector((s * 0.08 + x * 0.013, -0.008 + y * 0.026, HEAD_C - 0.008 + z * 0.04))
    ob = new_object("head", bm)
    add_mat(ob, "skin")
    return facet(ob, 520)


# ------------------------------------------------------------------ Frisuren (Metaballs)
def _skull_point(u, v, lift=0.0):
    """Punkt auf der Kopfoberflaeche: u = Winkel um die Hochachse (0 = vorn), v = Hoehe 0..1."""
    el = v * math.pi / 2.0
    x = math.sin(u) * math.cos(el) * 0.091
    y = math.cos(u) * math.cos(el) * 0.104
    z = math.sin(el) * 0.124
    n = Vector((x / 0.091 ** 2, y / 0.104 ** 2, z / 0.124 ** 2)).normalized()
    return Vector((x, y, z + HEAD_C)) + n * lift, n


def _in_hairline(u, v):
    """Haaransatz: vorn hoch (Stirn frei), an den Seiten ueber den Ohren, hinten tief."""
    fu = math.cos(u)  # 1 vorn, -1 hinten
    side = abs(math.sin(u))
    limit = 0.42 * max(0.0, fu) ** 1.5 + 0.2 * side - 0.3 * max(0.0, -fu)
    return v > limit


def hair_mesh(name, elements, resolution=0.012, target=700):
    mb = bpy.data.metaballs.new(name)
    mb.resolution = resolution
    mb.render_resolution = resolution
    mb.threshold = 0.6
    ob = bpy.data.objects.new(name + "_mb", mb)
    bpy.context.collection.objects.link(ob)
    for (co, radius, size, rot) in elements:
        el = mb.elements.new(type="ELLIPSOID")
        el.co = co
        el.radius = radius
        el.size_x, el.size_y, el.size_z = size
        el.rotation = rot
        el.stiffness = 1.6
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), depsgraph=dg)
    bpy.data.objects.remove(ob)
    hob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(hob)
    hob.data.materials.clear()
    add_mat(hob, "hair")
    return facet(hob, target)


def _tuft_rot(n, back_tilt, side_tilt, twist):
    """Drehung eines Buendels: entlang der Kopfnormalen, nach hinten/seitlich geneigt."""
    up = Vector((0, 0, 1))
    q = up.rotation_difference(n)
    m = q.to_matrix() @ Matrix.Rotation(back_tilt, 3, "X") @ Matrix.Rotation(side_tilt, 3, "Y") @ Matrix.Rotation(twist, 3, "Z")
    return m.to_quaternion()


def _flow_rot(n, d):
    """Ellipsoid-Drehung: lange Achse (z) entlang der Kammrichtung d, flach zur Kopfhaut."""
    d = (d - n * d.dot(n)).normalized()
    side = n.cross(d).normalized()
    m = Matrix((side, n, d)).transposed()   # Spalten: x = seitlich, y = Normale, z = Richtung
    return m.to_quaternion()


def _hair_layer(rnd, lift_fn, flow_fn, radius, size, vmin=-0.2, count=26, rings=9, extra_keep=None):
    els = []
    for ri in range(rings):
        v = vmin + (1.0 - vmin) * (ri + 0.5) / rings
        n_ring = max(3, int(count * math.cos(max(0.0, v) * math.pi / 2.0) + 2))
        for k in range(n_ring):
            u = -math.pi + (k + rnd.uniform(0.2, 0.8)) / n_ring * 2 * math.pi
            ok = _in_hairline(u, v) or (extra_keep is not None and extra_keep(u, v))
            if not ok:
                continue
            co, n = _skull_point(u, v, lift_fn(u, v))
            els.append((co, radius * rnd.uniform(0.9, 1.1), size, _flow_rot(n, flow_fn(u, v, n))))
    return els


def hair_variants():
    rnd = random.Random(5)
    out = []
    back_up = lambda u, v, n: Vector((0.15, -1.0, 0.55))
    # 0: wellig, oben voll und nach hinten gekaemmt, vorn leicht aufgestellt (wie die Vorlage)
    els = _hair_layer(rnd, lambda u, v: 0.006 + 0.034 * max(0.0, v) ** 1.3 * (0.55 + 0.45 * max(0.0, math.cos(u))),
                      back_up, 0.034, (0.95, 0.6, 1.6), vmin=-0.15, count=22, rings=10)
    els += _hair_layer(rnd, lambda u, v: -0.004, back_up, 0.03, (1.0, 0.45, 1.2), vmin=-0.2, count=20, rings=8)
    for k in range(9):  # Wellen und lockere Spitzen oben vorn
        u = rnd.uniform(-0.9, 0.9)
        v = rnd.uniform(0.6, 0.95)
        co, n = _skull_point(u, v, 0.04)
        d = Vector((math.sin(u) * 0.6, -0.4 + rnd.uniform(-0.2, 0.3), 1.0))
        els.append((co, 0.026, (0.8, 0.6, 1.7), _flow_rot(n, d)))
    out.append(hair_mesh("hair_0", els, 0.0085, 900))
    # 1: sehr kurz (dichte Kappe)
    els = _hair_layer(rnd, lambda u, v: -0.004, back_up, 0.03, (1.0, 0.45, 1.2), vmin=-0.2, count=22, rings=9)
    out.append(hair_mesh("hair_1", els, 0.009, 500))
    # 2: laenger, Scheitel links, Pony zur Seite gekaemmt, hinten bis in den Nacken
    side_back = lambda u, v, n: Vector((0.9 if math.cos(u) > 0.2 else 0.25, -0.7, -0.15))
    els = _hair_layer(rnd, lambda u, v: 0.003 + 0.012 * max(0.0, v), side_back, 0.03, (0.9, 0.45, 1.8),
                      vmin=-0.3, count=20, rings=10,
                      extra_keep=lambda u, v: math.cos(u) < -0.55 and v > -0.38)
    for k in range(7):  # Pony: lange Straehnen schraeg ueber die Stirn
        u = -0.55 + k * 0.17
        co, n = _skull_point(u, 0.62 + 0.04 * math.sin(k), 0.018)
        els.append((co, 0.03, (0.75, 0.45, 2.1), _flow_rot(n, Vector((1.0, 0.25, -0.55)))))
    out.append(hair_mesh("hair_2", els, 0.0085, 900))
    # 3: lockig (dichte kleine Locken)
    els = _hair_layer(rnd, lambda u, v: -0.004, back_up, 0.03, (1.0, 0.45, 1.2), vmin=-0.2, count=20, rings=8)
    for ri in range(11):
        v = -0.12 + 1.1 * (ri + 0.5) / 11
        n_ring = max(4, int(34 * math.cos(max(0.0, min(1.0, v)) * math.pi / 2.0) + 3))
        for k in range(n_ring):
            u = -math.pi + (k + rnd.uniform(0.3, 0.7)) / n_ring * 2 * math.pi
            if not _in_hairline(u, v):
                continue
            co, n = _skull_point(u, min(v, 1.0), 0.014 + 0.008 * max(0.0, v))
            els.append((co, rnd.uniform(0.018, 0.021), (1, 1, 1), _flow_rot(n, Vector((0, -1, 0.3)))))
    out.append(hair_mesh("hair_3", els, 0.007, 1100))
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


def bind(rig, body_smooth, meshes, rigid):
    """Glatten Koerper automatisch (Waermeverteilung) an die Knochen binden. Alle anderen
    weichen Teile (Haut, Kleidung) uebernehmen die Gewichte der naechsten Koerperstelle,
    damit sie genau zusammen gehen. Starre Teile haengen ganz an einem Knochen."""
    bpy.ops.object.select_all(action="DESELECT")
    body_smooth.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
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
        world_rot = Matrix.Rotation(math.radians(s * 88.0), 3, "Y")
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
    views = {"front": ((0, 9.5, 1.0), 1.0), "side": ((9.5, 0, 1.0), 1.0), "back": ((0, -9.5, 1.0), 1.0), "face": ((0.5, 1.5, 1.8), 1.72)}
    for vname, (loc, tz) in views.items():
        cam.location = loc
        d = Vector((0, 0, tz)) - cam.location
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        scn.render.filepath = f"{folder}/{tag}_{vname}.png"
        bpy.ops.render.render(write_still=True)


def main():
    reset()
    body_smooth = build_body_smooth()
    jersey, collar = build_jersey(body_smooth)
    shorts = build_shorts(body_smooth)
    socks = build_socks(body_smooth)
    trousers = build_trousers(body_smooth)
    skin = build_body_lowpoly(body_smooth)
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
    loc, n = surface_hit(shorts, (0.12, 0.6, 0.73), (0, -1, 0))
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
        ("num_shorts", shorts, (-0.12, 0.6, 0.74), (0, -1, 0), "hip_l"),
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
