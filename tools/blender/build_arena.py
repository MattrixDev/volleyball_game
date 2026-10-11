"""Baut die Sporthalle (Arena) in Blender (als Python-Modul bpy) und exportiert sie als glTF.
Dazu kommen kleine Einzelteile: Ball, Linienrichterfahne und Zuschauer-Bausteine.

Aufruf:  python build_arena.py <ausgabe_ordner> [vorschau_ordner]

Ergebnis im Ausgabeordner: arena.glb, ball.glb, flag.glb, fan.glb.

Stil wie Mattis' Vorlage (references/stil-vorlage-spieler.png): kantiges, facettiertes
Low-Poly. Alles flach schattiert, grosse Flaechen sind in unregelmaessige Dreiecke
zerlegt, und jede Flaeche bekommt ueber die Vertexfarbe "Col" eine leicht andere
Helligkeit (die Vertexfarbe wird im Spiel mit der Materialfarbe multipliziert).
Farben gedeckt und ruhig: Spielfeld terrakotta, Freizone staubblau, Tribuenen Beton
mit Sitzschalen in gedecktem Marine (links, x<0) und Weinrot (rechts, x>0).

Masse und Positionen sind genau die aus scripts/arena.gd und scripts/crowd.gd, denn das
Spiel (Ball, Figuren, Zuschauer) verlaesst sich darauf.

Achsen: Gebaut wird direkt in GODOT-Koordinaten (x, y oben, z). Erst beim Anlegen der
Vertices wird nach Blender umgerechnet: Godot (x, y, z) -> Blender (x, -z, y). Der
glTF-Export mit export_yup=True dreht das wieder zurueck. So kann man alle Zahlen
direkt mit arena.gd vergleichen.
"""
import math
import os
import random
import sys

import bpy  # zuerst: bmesh und mathutils kommen mit bpy
import bmesh
from mathutils import Matrix, Vector

OUT_DIR = sys.argv[1] if len(sys.argv) > 1 else "."
PREVIEW = sys.argv[2] if len(sys.argv) > 2 else ""
RND = random.Random(1234)

# Facetten-Streuung: jede Flaeche wird um bis zu JITTER dunkler (also +-5 % um die Mitte)
JITTER = 0.10


# ------------------------------------------------------------------ Farben / Materialien
def srgb(h):
    """Hex-Farbe (sRGB, wie im Malprogramm) -> lineare RGBA-Werte fuer Blender."""
    h = h.lstrip("#")
    out = []
    for i in range(3):
        c = int(h[i * 2:i * 2 + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


# Name: (Farbe, Rauheit, Leuchtstaerke). Gedeckte, leicht entsaettigte Toene.
PALETTE = {
    # Boden
    "court": ("#AD6542", 0.75, 0.0),         # Spielfeld terrakotta
    "free_zone": ("#4D6982", 0.75, 0.0),     # Freizone staubblau
    "coach_zone": ("#435C75", 0.75, 0.0),    # Trainer-/Aufwaermzone etwas dunkler
    "hall_floor": ("#5D6066", 0.85, 0.0),    # Hallenboden ausserhalb der Freizone
    "line": ("#ECE8DF", 0.7, 0.0),           # Linien gebrochen weiss
    # Netzanlage
    "net_strand": ("#1D1F23", 0.9, 0.0),
    "net_band": ("#EEECE6", 0.7, 0.0),
    "antenna_red": ("#B33F38", 0.6, 0.0),
    "antenna_white": ("#EEECE6", 0.6, 0.0),
    "steel": ("#A9ADB2", 0.45, 0.0),
    "steel_dark": ("#55595F", 0.6, 0.0),
    "padding": ("#2F3E5C", 0.85, 0.0),       # Polster marine
    "rubber": ("#2A2B2E", 0.9, 0.0),
    # Offizielle
    "platform": ("#4A4D53", 0.85, 0.0),
    "table_top": ("#E6E2DA", 0.7, 0.0),
    "table_body": ("#2F3E5C", 0.8, 0.0),
    "panel_front": ("#2F3E5C", 0.8, 0.0),
    "chair": ("#3B3F46", 0.8, 0.0),
    "tablet": ("#1C1D20", 0.4, 0.0),
    "tablet_screen": ("#9FB4C8", 0.4, 0.6),
    "paper": ("#F2EFE8", 0.9, 0.0),
    "bench_navy": ("#34445F", 0.8, 0.0),
    "bench_wine": ("#7A3A44", 0.8, 0.0),
    "bottle_navy": ("#3E5275", 0.5, 0.0),
    "bottle_wine": ("#8A4450", 0.5, 0.0),
    "bottle_cap": ("#E9E6DF", 0.5, 0.0),
    "towel": ("#DCD8CF", 0.95, 0.0),
    "crate": ("#3A3D44", 0.8, 0.0),
    # Tribuenen
    "concrete": ("#8E9195", 0.9, 0.0),
    "concrete_dark": ("#7C7F84", 0.9, 0.0),
    "seat_navy": ("#34445F", 0.75, 0.0),
    "seat_wine": ("#7A3A44", 0.75, 0.0),
    "seat_grey": ("#7D8187", 0.75, 0.0),
    "stripe_navy": ("#2F3E5C", 0.8, 0.0),
    "stripe_wine": ("#6E343E", 0.8, 0.0),
    "railing": ("#C9CCD0", 0.4, 0.0),
    # Werbung / Anzeigen
    "board_frame": ("#2A2C31", 0.6, 0.0),
    "adscreen": ("#3A4250", 0.5, 0.35),
    "scorescreen": ("#1E2128", 0.5, 0.2),
    "score_header": ("#C9A661", 0.6, 0.3),
    # Halle
    "wall": ("#BEB8AE", 0.9, 0.0),
    "wall_low": ("#9A958D", 0.9, 0.0),
    "wall_band": ("#34445F", 0.85, 0.0),
    "window": ("#B9C9D6", 0.3, 0.8),
    "window_frame": ("#4A4E55", 0.6, 0.0),
    "ceiling": ("#3B3E45", 0.9, 0.0),
    "truss": ("#62676F", 0.5, 0.0),
    "lamp_housing": ("#2E3036", 0.6, 0.0),
    "lamp": ("#FFF3DE", 0.4, 4.0),
    "door": ("#5E6B7A", 0.7, 0.0),
    "tunnel_dark": ("#18191C", 0.9, 0.0),
    "exit_sign": ("#5E9C7A", 0.5, 1.5),
    "banner_navy": ("#34445F", 0.9, 0.0),
    "banner_wine": ("#7A3A44", 0.9, 0.0),
    "banner_white": ("#E4E0D8", 0.9, 0.0),
    # Einzelteile
    "ball_yellow": ("#D8B54E", 0.6, 0.0),
    "ball_blue": ("#3D5A8C", 0.6, 0.0),
    "ball_white": ("#EEEBE4", 0.6, 0.0),
    "flag_red": ("#B8423A", 0.85, 0.0),
    "flag_yellow": ("#DDB64E", 0.85, 0.0),
    "flag_stick": ("#2A2B2E", 0.6, 0.0),
    "fan": ("#FFFFFF", 0.9, 0.0),
}


def material(name):
    """Einfaches Principled-Material. Die Vertexfarbe wird erst fuer die Vorschau
    eingehaengt (preview_materials), damit der glTF-Export saubere Farbfaktoren schreibt."""
    m = bpy.data.materials.get(name)
    if m is None:
        hexc, rough, emit = PALETTE[name]
        col = srgb(hexc)
        m = bpy.data.materials.new(name)
        m.diffuse_color = col
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = col
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = 0.0
        if emit > 0.0:
            bsdf.inputs["Emission Color"].default_value = col
            bsdf.inputs["Emission Strength"].default_value = emit
    return m


# ------------------------------------------------------------------ Bausteine
def G(p):
    """Godot-Koordinaten -> Blender-Koordinaten."""
    return Vector((p[0], -p[2], p[1]))


def V(x, y, z):
    return Vector((x, y, z))


UP = V(0, 1, 0)


class Part:
    """Ein Objekt der Szene, das Flaeche fuer Flaeche aufgebaut wird. Jede Flaeche hat
    eigene Vertices (flache Schattierung), ein Material und eine eigene Helligkeit."""

    def __init__(self, name, uv=False):
        self.name = name
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.color.new("Col")
        self.uvl = self.bm.loops.layers.uv.new("UVMap") if uv else None
        self.mats = []

    def mi(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def face(self, pts, mat, hint=None, shade=None, uvs=None, jit=JITTER):
        """pts in Godot-Koordinaten. hint = Richtung, in die die Vorderseite zeigen soll."""
        pts = [Vector(p) for p in pts]
        if hint is not None:
            n = Vector((0, 0, 0))
            for i in range(len(pts)):  # Newell-Normale, robust auch fuer Vielecke
                a, b = pts[i], pts[(i + 1) % len(pts)]
                n += V((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
            if n.dot(Vector(hint)) < 0:
                pts.reverse()
                if uvs:
                    uvs = list(reversed(uvs))
        vs = [self.bm.verts.new(G(p)) for p in pts]
        f = self.bm.faces.new(vs)
        f.material_index = self.mi(mat)
        f.smooth = False
        s = 1.0 if shade is None else shade
        if isinstance(s, (int, float)):
            s = (s, s, s)
        k = 1.0 - RND.random() * jit
        c = (min(1.0, s[0] * k), min(1.0, s[1] * k), min(1.0, s[2] * k), 1.0)
        for i, lp in enumerate(f.loops):
            lp[self.col] = c
            if self.uvl is not None and uvs:
                lp[self.uvl].uv = uvs[i]
        return f

    def tri_count(self):
        return sum(len(f.verts) - 2 for f in self.bm.faces)

    def build(self):
        """bmesh -> Blender-Objekt (trianguliert, damit die Facetten genau so bleiben)."""
        bmesh.ops.triangulate(self.bm, faces=self.bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(material(m))
        for p in me.polygons:
            p.use_smooth = False
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.collection.objects.link(ob)
        return ob


def box(part, c, size, mat, rot=None, skip=(), shade=None, jit=JITTER):
    """Quader (Godot-Koordinaten). rot: 3x3-Drehung um den Mittelpunkt. skip: Seiten
    weglassen, z.B. ('ny',) fuer den unsichtbaren Boden."""
    c = Vector(c)
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    R = rot if rot is not None else Matrix.Identity(3)

    def P(x, y, z):
        return c + R @ V(x, y, z)
    sides = {
        "px": ([(hx, -hy, -hz), (hx, hy, -hz), (hx, hy, hz), (hx, -hy, hz)], V(1, 0, 0)),
        "nx": ([(-hx, -hy, -hz), (-hx, -hy, hz), (-hx, hy, hz), (-hx, hy, -hz)], V(-1, 0, 0)),
        "py": ([(-hx, hy, -hz), (-hx, hy, hz), (hx, hy, hz), (hx, hy, -hz)], V(0, 1, 0)),
        "ny": ([(-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz), (-hx, -hy, hz)], V(0, -1, 0)),
        "pz": ([(-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)], V(0, 0, 1)),
        "nz": ([(-hx, -hy, -hz), (-hx, hy, -hz), (hx, hy, -hz), (hx, -hy, -hz)], V(0, 0, -1)),
    }
    for key, (pts, n) in sides.items():
        if key in skip:
            continue
        part.face([P(*p) for p in pts], mat, hint=R @ n, shade=shade, jit=jit)


def beam(part, a, b, w, h, mat, up=UP, caps=False, shade=None):
    """Vierkant-Stab von a nach b (Querschnitt w x h), z.B. fuer Fachwerk und Gelaender."""
    a, b = Vector(a), Vector(b)
    d = (b - a).normalized()
    u = up if abs(d.dot(up)) < 0.95 else V(1, 0, 0)
    s = d.cross(u).normalized()
    u = s.cross(d).normalized()
    cs = [s * w / 2 + u * h / 2, -s * w / 2 + u * h / 2, -s * w / 2 - u * h / 2, s * w / 2 - u * h / 2]
    for i in range(4):
        c0, c1 = cs[i], cs[(i + 1) % 4]
        part.face([a + c0, a + c1, b + c1, b + c0], mat, hint=(c0 + c1), shade=shade)
    if caps:
        part.face([a + c for c in cs], mat, hint=-d, shade=shade)
        part.face([b + c for c in cs], mat, hint=d, shade=shade)


def cyl(part, p0, p1, r0, r1, seg, mat, caps=(True, True), phase=0.0, shade=None):
    """Kegelstumpf/Zylinder von p0 nach p1 mit seg Seiten (kantig, wie gewollt)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = (p1 - p0).normalized()
    u = UP if abs(d.dot(UP)) < 0.95 else V(1, 0, 0)
    s = d.cross(u).normalized()
    u = s.cross(d).normalized()
    ring0, ring1 = [], []
    for i in range(seg):
        a = phase + i / seg * math.tau
        off = s * math.cos(a) + u * math.sin(a)
        ring0.append(p0 + off * r0)
        ring1.append(p1 + off * r1)
    mid = (p0 + p1) / 2
    for i in range(seg):
        j = (i + 1) % seg
        q = [ring0[i], ring0[j], ring1[j], ring1[i]]
        cen = sum(q, Vector()) / 4
        part.face(q, mat, hint=cen - mid - d * (cen - mid).dot(d), shade=shade)
    if caps[0] and r0 > 0:
        part.face(ring0, mat, hint=-d, shade=shade)
    if caps[1] and r1 > 0:
        part.face(ring1, mat, hint=d, shade=shade)


def breaks(lo, hi, must, step):
    """Teilungspunkte von lo bis hi: alle Pflichtwerte (Linien, Kanten) plus gleichmaessige
    Unterteilung dazwischen. Gibt (Werte, Menge der festen Werte) zurueck."""
    fixed = sorted({lo, hi} | {m for m in must if lo <= m <= hi})
    out = []
    for a, b in zip(fixed, fixed[1:]):
        n = max(1, math.ceil((b - a) / step - 1e-6))
        for k in range(n):
            out.append(a + (b - a) * k / n)
    out.append(hi)
    return out, set(round(f, 6) for f in fixed)


def grid(part, origin, U, Vv, us, vs, matfn, normal, fixed_u=(), fixed_v=(), jit=0.28,
         wobble=0.0, shade=None, face_jit=JITTER):
    """Grosse Flaeche als unregelmaessiges Dreiecksnetz: innere Punkte werden in der Ebene
    verschoben (Feldkanten und Linien bleiben fest und gerade), jede Zelle wird zufaellig
    diagonal geteilt. wobble verschiebt zusaetzlich senkrecht zur Ebene (nur Waende/Decke,
    nie der Spielboden). matfn(u, v) liefert das Material der Zelle oder None (Loch)."""
    origin, U, Vv, normal = Vector(origin), Vector(U), Vector(Vv), Vector(normal)
    fu = set(round(x, 6) for x in fixed_u)
    fv = set(round(x, 6) for x in fixed_v)
    P = []
    for i, u in enumerate(us):
        row = []
        for j, v in enumerate(vs):
            du = dv = 0.0
            if round(u, 6) not in fu and 0 < i < len(us) - 1:
                du = RND.uniform(-jit, jit) * min(us[i] - us[i - 1], us[i + 1] - us[i])
            if round(v, 6) not in fv and 0 < j < len(vs) - 1:
                dv = RND.uniform(-jit, jit) * min(vs[j] - vs[j - 1], vs[j + 1] - vs[j])
            w = RND.uniform(-wobble, wobble) if wobble and 0 < i < len(us) - 1 and 0 < j < len(vs) - 1 else 0.0
            row.append(origin + U * (u + du) + Vv * (v + dv) + normal * w)
        P.append(row)
    for i in range(len(us) - 1):
        for j in range(len(vs) - 1):
            m = matfn((us[i] + us[i + 1]) / 2, (vs[j] + vs[j + 1]) / 2)
            if m is None:
                continue
            a, b, c, d = P[i][j], P[i + 1][j], P[i + 1][j + 1], P[i][j + 1]
            if RND.random() < 0.5:
                part.face([a, b, c], m, hint=normal, shade=shade, jit=face_jit)
                part.face([a, c, d], m, hint=normal, shade=shade, jit=face_jit)
            else:
                part.face([a, b, d], m, hint=normal, shade=shade, jit=face_jit)
                part.face([b, c, d], m, hint=normal, shade=shade, jit=face_jit)


def rot_y(a):
    return Matrix.Rotation(a, 3, "Y")


def rot_x(a):
    return Matrix.Rotation(a, 3, "X")


def rot_z(a):
    return Matrix.Rotation(a, 3, "Z")


# ------------------------------------------------------------------ Hallenmasse
WALL_X = 25.75   # Innenseite der Stirnwaende (arena.gd: Wand 0,5 dick bei x = +-26)
WALL_Z = 20.75   # Innenseite der Laengswaende (bei z = +-21)
HALL_H = 14.0
ROWS = 4         # Tribuenenreihen (crowd.gd)
SPACING = 0.62   # Sitzabstand (crowd.gd)


# ------------------------------------------------------------------ Boden
def build_floor():
    """Hallenboden: Freizone 44 x 30 m, Spielfeld 18 x 9 m, Trainer-/Aufwaermzonen.
    Alles ein Dreiecksnetz in einer Ebene; die Feldgrenzen sind feste Gitterlinien."""
    p = Part("floor")
    must_x = [-22, -15, -12, -9, -3, 0, 3, 9, 12, 15, 22]
    must_z = [-15, -10.5, -7.5, -4.5, 0, 4.5, 7.5, 10.5, 15]
    xs, fx = breaks(-WALL_X, WALL_X, must_x, 1.5)
    zs, fz = breaks(-WALL_Z, WALL_Z, must_z, 1.5)

    def mat(x, z):
        if abs(x) < 9 and abs(z) < 4.5:
            return "court"
        if 12 < abs(x) < 15 and 7.5 < z < 10.5:
            return "coach_zone"
        if abs(x) < 22 and abs(z) < 15:
            return "free_zone"
        return "hall_floor"
    grid(p, V(0, 0, 0), V(1, 0, 0), V(0, 0, 1), xs, zs, mat, UP, fx, fz, jit=0.3)
    floor = p.build()

    # Linien 5 cm breit, flach knapp ueber dem Boden (wie arena.gd)
    ln = Part("court_lines")
    lw = 0.05
    y = 0.004

    def strip(x0, x1, z0, z1):
        ln.face([V(x0, y, z0), V(x1, y, z0), V(x1, y, z1), V(x0, y, z1)], "line", hint=UP, jit=0.04)
    for x in (-9.0, 9.0):                      # Grundlinien
        strip(x - lw / 2, x + lw / 2, -4.5 - lw / 2, 4.5 + lw / 2)
    for z in (-4.5, 4.5):                      # Seitenlinien
        strip(-9 - lw / 2, 9 + lw / 2, z - lw / 2, z + lw / 2)
    for x in (-3.0, 0.0, 3.0):                 # Mittellinie, Angriffslinien
        strip(x - lw / 2, x + lw / 2, -4.5 + lw / 2, 4.5 - lw / 2)
    for x in (-3.0, 3.0):                      # gestrichelte Verlaengerung (FIVB)
        for sz in (-1.0, 1.0):
            for k in range(5):
                zc = sz * (4.5 + 0.25 + k * 0.35)
                strip(x - lw / 2, x + lw / 2, zc - 0.075, zc + 0.075)
    # Rand der Trainerzonen als feine Linie
    for sx in (-1.0, 1.0):
        x0, x1 = sorted((sx * 12.0, sx * 15.0))
        strip(x0, x1, 7.5 - lw / 2, 7.5 + lw / 2)
        xi = sx * 12.0
        strip(xi - lw / 2, xi + lw / 2, 7.5, 10.5)
    return [floor, ln.build()]


# ------------------------------------------------------------------ Netzanlage
def build_net():
    """Netz bei x = 0: echte Maschen (10 cm) als duenne Stege, Ober-/Unterband,
    Seitenbaender, Antennen rot/weiss, Spannseile, Pfosten mit Polster, Bodenplatten."""
    objs = []
    # Maschen: senkrechte und waagerechte Stege, 3 mm stark, je 4 Seiten
    nm = Part("net_mesh")
    t = 0.003
    y0, y1 = 1.465, 2.36
    for k in range(99):
        z = -4.9 + k * 0.1
        beam(nm, V(0, y0, z), V(0, y1, z), t, t, "net_strand", up=V(0, 0, 1))
    for k in range(9):
        y = 1.49 + k * 0.1
        beam(nm, V(0, y, -4.9), V(0, y, 4.9), t, t, "net_strand")
    objs.append(nm.build())

    nb = Part("net_bands")
    box(nb, V(0, 2.395, 0), (0.03, 0.07, 9.8), "net_band")      # Oberband (Netzoberkante 2,43)
    box(nb, V(0, 1.44, 0), (0.02, 0.05, 9.8), "net_band")       # Unterband
    for z in (-4.5, 4.5):
        box(nb, V(0, 1.915, z), (0.025, 0.95, 0.05), "net_band")  # Seitenband
    # Spannseile vom Netz zu den Pfosten (oben und unten)
    for sz in (-1, 1):
        cyl(nb, V(0, 2.40, sz * 4.9), V(0, 2.40, sz * 5.55), 0.005, 0.005, 4, "steel_dark")
        cyl(nb, V(0, 1.44, sz * 4.9), V(0, 1.44, sz * 5.55), 0.004, 0.004, 4, "steel_dark")
        for k in range(5):  # Schnuere an den Netzenden
            y = 1.5 + k * 0.2
            cyl(nb, V(0, y, sz * 4.9), V(0, y + 0.04, sz * 5.5), 0.003, 0.003, 3, "net_strand")
    objs.append(nb.build())

    an = Part("antennas")
    for z in (-4.5, 4.5):
        for k in range(9):
            m = "antenna_red" if k % 2 == 0 else "antenna_white"
            cyl(an, V(0.0, 1.43 + 0.2 * k, z), V(0.0, 1.63 + 0.2 * k, z), 0.011, 0.011, 6, m,
                caps=(k == 0, k == 8))
        box(an, V(0, 2.395, z), (0.05, 0.1, 0.03), "rubber")     # Klemme am Oberband
        box(an, V(0, 1.47, z), (0.05, 0.08, 0.03), "rubber")
    objs.append(an.build())

    po = Part("posts")
    for sz in (-1, 1):
        z = sz * 5.6
        cyl(po, V(0, 1.8, z), V(0, 2.6, z), 0.055, 0.055, 10, "steel", caps=(False, True))
        cyl(po, V(0, 2.6, z), V(0, 2.64, z), 0.06, 0.04, 10, "steel_dark", caps=(False, True))
        # Spannkurbel oben am Pfosten, Haken fuer das Oberband
        box(po, V(0, 2.42, z - sz * 0.07), (0.05, 0.06, 0.06), "steel_dark")
        box(po, V(0, 1.44, z - sz * 0.07), (0.05, 0.05, 0.06), "steel_dark")
        # rundes Polster bis 1,8 m, oben leicht eingezogen, mit hellerem Reissverschluss-Streifen
        cyl(po, V(0, 0.03, z), V(0, 1.72, z), 0.135, 0.135, 12, "padding", caps=(False, False))
        cyl(po, V(0, 1.72, z), V(0, 1.82, z), 0.135, 0.07, 12, "padding", caps=(False, True))
        box(po, V(0, 0.9, z + sz * 0.132), (0.03, 1.6, 0.012), "net_band", skip=("ny", "py"))
        # Bodenplatte (rund) und Abdeckung
        cyl(po, V(0, 0.0, z), V(0, 0.022, z), 0.27, 0.25, 12, "steel_dark", caps=(False, True))
    objs.append(po.build())
    return objs


# ------------------------------------------------------------------ Schiedsrichterstuhl
def build_referee_stand():
    """Schiedsrichterstuhl bei (0, 0, -6,3): Plattform mit Oberkante 1,46 m (Platte um
    1,42 m wie in arena.gd, der Schiedsrichter steht in arena.gd auf y = 1,46),
    Rahmen aus Vierkantrohr, Polster an Front und Seiten, Leiter links (-x),
    gepolsterte Rueckenlehne hinten (-z). Schaut nach +z zum Feld."""
    p = Part("referee_stand")
    cz = -6.3
    top = 1.46
    # vier Beine und Querstreben
    for dx in (-0.36, 0.36):
        for dz in (-0.36, 0.36):
            box(p, V(dx, (top - 0.06) / 2, cz + dz), (0.05, top - 0.06, 0.05), "steel", skip=("ny",))
            box(p, V(dx, 0.01, cz + dz), (0.1, 0.02, 0.1), "rubber", skip=("ny",))
    for y in (0.4, 0.95):
        for dz in (-0.36, 0.36):
            beam(p, V(-0.36, y, cz + dz), V(0.36, y, cz + dz), 0.035, 0.035, "steel")
        for dx in (-0.36, 0.36):
            beam(p, V(dx, y, cz - 0.36), V(dx, y, cz + 0.36), 0.035, 0.035, "steel")
    for dx in (-0.36, 0.36):  # Diagonalen an den Seiten
        beam(p, V(dx, 0.4, cz - 0.36), V(dx, 0.95, cz + 0.36), 0.03, 0.03, "steel")
    # Plattform (Oberseite frei fuer die Figur) mit Gummibelag
    box(p, V(0, top - 0.03, cz), (0.92, 0.06, 0.92), "platform")
    box(p, V(0, top + 0.004, cz), (0.86, 0.008, 0.86), "rubber", skip=("ny",), jit=0.05)
    # Polster vorn (Richtung Feld, +z) und an beiden Seiten, unten bis kurz ueber den Boden
    box(p, V(0, 0.72, cz + 0.42), (0.86, 1.2, 0.08), "padding")
    box(p, V(0.42, 0.72, cz), (0.08, 1.2, 0.78), "padding")
    box(p, V(-0.42, 0.95, cz + 0.12), (0.08, 0.75, 0.54), "padding")  # Leiterseite nur oben
    # Rueckenlehne: zwei Pfosten, gepolsterter Querholm in Hueft-/Rueckenhoehe
    for dx in (-0.36, 0.36):
        box(p, V(dx, top + 0.42, cz - 0.4), (0.04, 0.84, 0.04), "steel")
    box(p, V(0, top + 0.72, cz - 0.42), (0.78, 0.2, 0.09), "padding")
    box(p, V(0, top + 0.72, cz - 0.475), (0.72, 0.16, 0.02), "steel_dark", skip=("pz",))
    # seitliche Handlaeufe von hinten nach vorn
    for dx in (-0.4, 0.4):
        beam(p, V(dx, top + 0.82, cz - 0.4), V(dx, top + 0.82, cz + 0.15), 0.035, 0.035, "steel", caps=True)
        box(p, V(dx, top + 0.41, cz + 0.15), (0.03, 0.82, 0.03), "steel")
    # Leiter auf der -x-Seite: zwei schraege Holme und drei Stufen
    xa, xb = -0.42, -1.12
    for dz in (-0.25, 0.25):
        beam(p, V(xa, top - 0.04, cz + dz), V(xb, 0.0, cz + dz), 0.05, 0.05, "steel")
    for k, y in enumerate((0.37, 0.74, 1.1)):
        x = xb + (xa - xb) * (y / top)
        box(p, V(x - 0.02, y, cz), (0.18, 0.04, 0.5), "platform")
    # Haltegriffe an der Leiter
    for dz in (-0.27, 0.27):
        beam(p, V(xa + 0.02, top + 0.8, cz + dz), V(xb + 0.2, 0.8, cz + dz), 0.03, 0.03, "steel")
    return [p.build()]


# ------------------------------------------------------------------ Kampfgericht, Baenke
def chair(p, x, z, face=-1.0, seat_h=0.5):
    """Stuhl mit Sitzflaeche auf seat_h, schaut in z-Richtung 'face'."""
    s = 0.44
    for dx in (-0.19, 0.19):
        for dz in (-0.19, 0.19):
            box(p, V(x + dx, (seat_h - 0.03) / 2, z + dz), (0.03, seat_h - 0.03, 0.03), "steel", skip=("ny",))
    box(p, V(x, seat_h - 0.025, z), (s, 0.05, s), "chair")
    zb = z - face * 0.21
    for dx in (-0.19, 0.19):
        box(p, V(x + dx, seat_h + 0.22, zb), (0.03, 0.44, 0.03), "steel")
    box(p, V(x, seat_h + 0.33, zb - face * 0.01), (s, 0.26, 0.04), "chair", rot=rot_x(-face * 0.12))


def build_officials():
    objs = []
    # Kampfgericht: Tisch 2,4 m breit, 0,75 m hoch bei z = 8,6, Front zum Feld (-z)
    t = Part("scorer_table")
    zc = 8.6
    box(t, V(0, 0.77, zc), (2.5, 0.05, 0.8), "table_top")                 # Platte (Oberkante 0,795)
    for sx in (-1, 1):
        box(t, V(sx * 1.17, 0.375, zc), (0.05, 0.74, 0.66), "table_body", skip=("ny",))  # Wangen
    box(t, V(0, 0.72, zc + 0.3), (2.3, 0.06, 0.04), "steel_dark")
    # Kleinkram auf dem Tisch: Tablet, Spielberichtsbogen, Stift, Summer, Flasche
    box(t, V(-0.6, 0.8, zc + 0.05), (0.26, 0.012, 0.19), "tablet", skip=("ny",), rot=rot_y(0.08))
    t.face([V(-0.72, 0.8065, zc - 0.035), V(-0.48, 0.8065, zc - 0.035), V(-0.48, 0.8065, zc + 0.135),
            V(-0.72, 0.8065, zc + 0.135)], "tablet_screen", hint=UP)
    box(t, V(0.6, 0.797, zc + 0.04), (0.3, 0.004, 0.42), "paper", skip=("ny",), rot=rot_y(-0.06))
    box(t, V(0.45, 0.797, zc + 0.08), (0.21, 0.003, 0.297), "paper", skip=("ny",), rot=rot_y(0.12), shade=0.94)
    cyl(t, V(0.78, 0.802, zc + 0.02), V(0.78, 0.802, zc + 0.16), 0.005, 0.005, 5, "bottle_navy")
    box(t, V(0.0, 0.82, zc + 0.12), (0.12, 0.05, 0.08), "rubber", skip=("ny",))
    cyl(t, V(0.0, 0.845, zc + 0.12), V(0.0, 0.86, zc + 0.12), 0.02, 0.02, 6, "antenna_red", caps=(False, True))
    cyl(t, V(1.05, 0.795, zc + 0.2), V(1.05, 1.0, zc + 0.2), 0.035, 0.035, 7, "bottle_navy", caps=(False, False))
    cyl(t, V(1.05, 1.0, zc + 0.2), V(1.05, 1.03, zc + 0.2), 0.035, 0.018, 7, "bottle_cap", caps=(False, True))
    # zwei Stuehle hinter dem Tisch (x = +-0,6, z = 9,3), Sitzhoehe 0,5
    for x in (-0.6, 0.6):
        chair(t, x, 9.3, face=-1.0, seat_h=0.5)
    objs.append(t.build())
    # Frontblende als eigenes Mesh mit UV (0..1), damit man ein Logo aufbringen kann
    f = Part("scorer_front", uv=True)
    x0, x1, y0, y1, zf = -1.2, 1.2, 0.04, 0.745, zc - 0.36
    f.face([V(x0, y0, zf), V(x1, y0, zf), V(x1, y1, zf), V(x0, y1, zf)], "panel_front", hint=V(0, 0, -1),
           uvs=[(1, 0), (0, 0), (0, 1), (1, 1)], jit=0.0)
    box(f, V(0, (y0 + y1) / 2, zf + 0.02), (2.4, y1 - y0, 0.04), "table_body", skip=("nz",))
    box(f, V(0, 0.71, zf - 0.006), (2.4, 0.03, 0.012), "net_band", skip=("pz",))  # heller Streifen oben
    objs.append(f.build())

    # Spielerbaenke: x = +-6,2, z = 9,0, 4,2 m lang, Sitzflaeche 0,45 m, Lehne hinten
    b = Part("benches")
    for t_, sx in ((0, -1.0), (1, 1.0)):
        cm = "bench_navy" if t_ == 0 else "bench_wine"
        xc, zc = sx * 6.2, 9.0
        box(b, V(xc, 0.42, zc), (4.2, 0.06, 0.46), cm)                       # Sitzpolster (Oberkante 0,45)
        box(b, V(xc, 0.385, zc), (4.2, 0.02, 0.46), "steel_dark", skip=("py",))
        for dx in (-2.0, 0.0, 2.0):
            for dz in (-0.19, 0.19):
                box(b, V(xc + dx, 0.19, zc + dz), (0.04, 0.38, 0.04), "steel", skip=("ny",))
            box(b, V(xc + dx, 0.015, zc + 0.05), (0.06, 0.03, 0.62), "steel_dark", skip=("ny",))
            box(b, V(xc + dx, 0.66, zc + 0.27), (0.04, 0.52, 0.04), "steel", rot=rot_x(0.1))
        beam(b, V(xc - 2.1, 0.12, zc - 0.19), V(xc + 2.1, 0.12, zc - 0.19), 0.03, 0.03, "steel")
        box(b, V(xc, 0.74, zc + 0.3), (4.2, 0.3, 0.06), cm, rot=rot_x(0.1))  # Rueckenlehne
    objs.append(b.build())

    # Details: Trinkflaschen, Flaschentraeger, Handtuecher
    d = Part("bench_props")
    for t_, sx in ((0, -1.0), (1, 1.0)):
        bm_ = "bottle_navy" if t_ == 0 else "bottle_wine"
        for k in range(6):
            x = sx * (4.55 + k * 0.62 + RND.uniform(-0.08, 0.08))
            z = 8.55 + RND.uniform(-0.05, 0.05)
            cyl(d, V(x, 0, z), V(x, 0.2, z), 0.036, 0.036, 7, bm_, caps=(False, False))
            cyl(d, V(x, 0.2, z), V(x, 0.235, z), 0.036, 0.016, 7, "bottle_cap", caps=(False, True))
        # Flaschentraeger mit vier Flaschen am Bankende
        xc = sx * 8.65
        box(d, V(xc, 0.09, 8.95), (0.34, 0.18, 0.26), "crate", skip=("ny",))
        for i in range(2):
            for j in range(2):
                x = xc - 0.08 + i * 0.16
                z = 8.89 + j * 0.12
                cyl(d, V(x, 0.18, z), V(x, 0.32, z), 0.034, 0.034, 6, bm_, caps=(False, False))
                cyl(d, V(x, 0.32, z), V(x, 0.35, z), 0.034, 0.015, 6, "bottle_cap", caps=(False, True))
        # Handtuch ueber die Sitzvorderkante gelegt
        xt = sx * 7.95
        prof = [(9.15, 0.452), (8.9, 0.455), (8.76, 0.45), (8.73, 0.36), (8.735, 0.22)]
        for a, c in zip(prof, prof[1:]):
            q = [V(xt - 0.18, a[1], a[0]), V(xt + 0.18, a[1], a[0]), V(xt + 0.18, c[1], c[0]), V(xt - 0.18, c[1], c[0])]
            n = V(0, c[0] - a[0], -(c[1] - a[1])) * -1
            n = V(0, n.y, n.z)
            n = V(0, 1, -1) if a[1] - c[1] > 0.02 else V(0, 1, 0)
            d.face(q, "towel", hint=n)
            d.face([v + V(0, -0.006, 0.006) for v in q], "towel", hint=-n, shade=0.9)
        # zweites Handtuch gefaltet auf der Bank
        box(d, V(sx * 4.25, 0.47, 9.05), (0.32, 0.04, 0.22), "towel", skip=("ny",), rot=rot_y(0.2))
    objs.append(d.build())
    return objs


# ------------------------------------------------------------------ Tribuenen
def seat(p, base, fwd, mat):
    """Sitzschale auf einer Stufe. base = Mitte der Sitzflaeche auf Stufenhoehe,
    fwd = Blickrichtung (waagerecht). Profil (vorn, oben) als L-Form, zur Mitte hin
    leicht eingesenkt, dazu ein kleiner Sockel. Sitzoberkante 0,42 m ueber der Stufe."""
    fwd = Vector(fwd).normalized()
    r = fwd.cross(UP).normalized()
    prof = [(0.21, 0.425), (-0.15, 0.41), (-0.22, 0.80), (-0.265, 0.79), (-0.215, 0.36), (0.19, 0.385)]

    def P(x, f, u):
        return base + r * x + fwd * f + UP * u
    rings = []
    for x, dip in ((-0.225, 0.0), (0.0, -0.018), (0.225, 0.0)):
        rings.append([P(x, f + (0.0 if dip == 0 else 0.01), u + dip) for f, u in prof])
    n = len(prof)
    for a, b in zip(rings, rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            f0, u0 = prof[i]
            f1, u1 = prof[j]
            hint = fwd * (u1 - u0) - UP * (f1 - f0)  # Profilnormale nach aussen (Profil laeuft im Uhrzeigersinn)
            p.face([a[i], a[j], b[j], b[i]], mat, hint=hint)
    p.face(rings[0], mat, hint=-r)
    p.face(rings[-1], mat, hint=r)
    # Sockel
    c = base + fwd * (-0.03) + UP * 0.18
    box(p, c, (0.1, 0.36, 0.1), "steel_dark", rot=Matrix((r, UP, -fwd)).transposed(), skip=("ny", "py"))


def seat_mat(x):
    """Blockfarben wie crowd.gd: x < -2 Marine, x > 1 Weinrot, dazwischen grau."""
    if x < -2.0:
        return "seat_navy"
    if x > 1.0:
        return "seat_wine"
    return "seat_grey"


def build_stands():
    """Stufentribuenen an den Laengsseiten (32 m, ab |z| = 12,4) und hinter den
    Grundlinien (22 m, ab |x| = 17,9). Stufe i: Oberkante 0,6 + i*0,6, 1,2 m tief,
    Mitte bei |z| = 13 + i*1,2 bzw. |x| = 18,5 + i*1,2 (exakt arena.gd/crowd.gd)."""
    st = Part("stands")
    se = Part("seats")
    ra = Part("railings")
    H = [0.6 + i * 0.6 for i in range(ROWS)]
    back_h = H[-1]

    # --- Laengsseiten: Tiefe laeuft in z, Laenge in x
    for sz in (-1.0, 1.0):
        out = V(0, 0, sz)       # von der Halle weg
        xs, fx = breaks(-16, 16, [-15.2, 15.2], 2.0)
        for i in range(ROWS):
            a, b = 12.4 + i * 1.2, 13.6 + i * 1.2
            h, h0 = H[i], (H[i - 1] if i else 0.0)
            # Trittflaeche (facettiert, Kanten fest)
            grid(st, V(0, h, sz * a), V(1, 0, 0), out, xs, [0, 0.6, 1.2],
                 lambda u, v: "concrete", UP, fx, {0, 1.2}, jit=0.25)
            # Setzstufe vorn (zur Halle), unterste Stufe mit Farbband
            m = "concrete_dark"
            grid(st, V(0, h0, sz * a), V(1, 0, 0), UP, xs, [0, h - h0], lambda u, v, m=m: m, -out, fx, {0, h - h0}, jit=0.2)
            # Stirnseiten bei x = +-16
            for sx in (-1, 1):
                st.face([V(sx * 16, 0, sz * a), V(sx * 16, 0, sz * b), V(sx * 16, h, sz * b), V(sx * 16, h, sz * a)],
                        "concrete_dark", hint=V(sx, 0, 0))
            # Sitzschalen, eine Reihe pro Stufe (x = -15 + k*0,62 wie crowd.gd)
            zc = sz * (13.0 + i * 1.2 + 0.08)
            k = 0
            while -15.0 + k * SPACING <= 15.0 + 1e-6:
                x = -15.0 + k * SPACING
                seat(se, V(x, h, zc), -out, seat_mat(x))
                k += 1
        # Farbband an der Front der untersten Stufe (links Marine, rechts Weinrot)
        for x0, x1, m in ((-15.2, -2.0, "stripe_navy"), (1.0, 15.2, "stripe_wine")):
            st.face([V(x0, 0.18, sz * 12.395), V(x1, 0.18, sz * 12.395), V(x1, 0.42, sz * 12.395), V(x0, 0.42, sz * 12.395)],
                    m, hint=-out)
        # Rueckwand und Bruestung hinten
        zb = 17.8
        grid(st, V(0, 0, sz * zb), V(1, 0, 0), UP, xs, [0, back_h, back_h + 1.0],
             lambda u, v: "concrete_dark", -out, fx, {0, back_h, back_h + 1.0}, jit=0.2)
        box(st, V(0, back_h + 1.04, sz * (zb + 0.08)), (32.0, 0.08, 0.3), "concrete", skip=("ny",))
        for sx in (-1, 1):
            st.face([V(sx * 16, back_h, sz * zb), V(sx * 16, back_h + 1.0, sz * zb), V(sx * 16, back_h + 1.0, sz * (zb + 0.16)),
                     V(sx * 16, back_h, sz * (zb + 0.16))], "concrete_dark", hint=V(sx, 0, 0))
            # Treppen am Ende jeder Laengstribuene (Gang x = +-15,25..15,95): Zwischenstufen
            for i in range(ROWS):
                a = 12.4 + i * 1.2
                h0 = H[i - 1] if i else 0.0
                xa, xb = sorted((sx * 15.25, sx * 15.95))
                box(st, V((xa + xb) / 2, h0 + 0.15, sz * (a - 0.2)), (xb - xa, 0.3, 0.4), "concrete", skip=("ny",))
                if i == 0:
                    box(st, V((xa + xb) / 2, 0.15, sz * (a - 0.6)), (xb - xa, 0.3, 0.4), "concrete", skip=("ny",))
                    box(st, V((xa + xb) / 2, 0.45, sz * (a - 0.2)), (xb - xa, 0.3, 0.4), "concrete", skip=("ny",))
            # Handlauf an der Treppe
            xr = sx * 15.2
            beam(ra, V(xr, 1.0, sz * 11.8), V(xr, back_h + 0.95, sz * 17.4), 0.04, 0.04, "railing")
            for zz, yy in ((11.8, 0.0), (17.4, back_h)):
                box(ra, V(xr, yy + 0.5, sz * zz), (0.04, 1.0, 0.04), "railing")
        # Gelaender vorn bei |z| = 12,4 auf der untersten Stufe (Gang an den Enden frei)
        zr = sz * 12.45
        beam(ra, V(-15.2, 1.3, zr), V(15.2, 1.3, zr), 0.06, 0.06, "railing")
        beam(ra, V(-15.2, 0.98, zr), V(15.2, 0.98, zr), 0.03, 0.03, "railing")
        for k in range(9):
            x = -15.2 + k * 3.8
            box(ra, V(x, 0.95, zr), (0.05, 0.7, 0.05), "railing")
        # Gelaender hinten oben
        beam(ra, V(-16, back_h + 1.25, sz * 17.88), V(16, back_h + 1.25, sz * 17.88), 0.05, 0.05, "railing")

    # --- Stirnseiten hinter den Grundlinien: Tiefe in x, Laenge in z
    for sx in (-1.0, 1.0):
        out = V(sx, 0, 0)
        zs, fz = breaks(-11, 11, [], 2.0)
        mat_seat = "seat_navy" if sx < 0 else "seat_wine"
        for i in range(ROWS):
            a, b = 17.9 + i * 1.2, 19.1 + i * 1.2
            h, h0 = H[i], (H[i - 1] if i else 0.0)
            grid(st, V(sx * a, h, 0), out, V(0, 0, 1), [0, 0.6, 1.2], zs, lambda u, v: "concrete", UP, {0, 1.2}, fz, jit=0.25)
            grid(st, V(sx * a, h0, 0), UP, V(0, 0, 1), [0, h - h0], zs, lambda u, v: "concrete_dark", -out, {0, h - h0}, fz, jit=0.2)
            for sz in (-1, 1):
                st.face([V(sx * a, 0, sz * 11), V(sx * b, 0, sz * 11), V(sx * b, h, sz * 11), V(sx * a, h, sz * 11)],
                        "concrete_dark", hint=V(0, 0, sz))
            xc = sx * (18.5 + i * 1.2 + 0.08)
            z = -10.5
            while z <= 10.5 + 1e-6:
                seat(se, V(xc, h, z), -out, mat_seat)
                z += SPACING
        stripe = "stripe_navy" if sx < 0 else "stripe_wine"
        st.face([V(sx * 17.895, 0.18, -11), V(sx * 17.895, 0.18, 11), V(sx * 17.895, 0.42, 11), V(sx * 17.895, 0.42, -11)],
                stripe, hint=-out)
        xb = 22.7
        grid(st, V(sx * xb, 0, 0), UP, V(0, 0, 1), [0, back_h, back_h + 1.0], zs, lambda u, v: "concrete_dark", -out,
             {0, back_h, back_h + 1.0}, fz, jit=0.2)
        box(st, V(sx * (xb + 0.08), back_h + 1.04, 0), (0.3, 0.08, 22.0), "concrete", skip=("ny",))
        for sz in (-1, 1):
            st.face([V(sx * xb, back_h, sz * 11), V(sx * xb, back_h + 1.0, sz * 11), V(sx * (xb + 0.16), back_h + 1.0, sz * 11),
                     V(sx * (xb + 0.16), back_h, sz * 11)], "concrete_dark", hint=V(0, 0, sz))
        xr = sx * 17.95
        beam(ra, V(xr, 1.3, -11), V(xr, 1.3, 11), 0.06, 0.06, "railing")
        beam(ra, V(xr, 0.98, -11), V(xr, 0.98, 11), 0.03, 0.03, "railing")
        for k in range(7):
            box(ra, V(xr, 0.95, -11 + k * 22 / 6), (0.05, 0.7, 0.05), "railing")
        beam(ra, V(sx * 22.78, back_h + 1.25, -11), V(sx * 22.78, back_h + 1.25, 11), 0.05, 0.05, "railing")
    return [st.build(), se.build(), ra.build()]


# ------------------------------------------------------------------ Werbebanden
def ad_board(frame, k, pos, rot_y_, size_long):
    """LED-Bande: Gehaeuse 5,8 x 0,9 m, leicht nach hinten geneigt, Stuetzen hinten,
    Bildschirm als eigenes Mesh adscreen_<k> mit UV 0..1, Vorderseite zum Feld."""
    R = rot_y(rot_y_)            # lokale +z-Achse = Richtung Feld
    tilt = rot_x(-0.06)          # ganz leicht nach hinten gekippt
    M = R @ tilt
    c = Vector(pos)
    w, h, d = size_long, 0.9, 0.1
    box(frame, c, (w, h, d), "board_frame", rot=M, skip=("ny",))
    box(frame, c + M @ V(0, h / 2 + 0.01, -0.01), (w + 0.02, 0.02, 0.13), "steel_dark", rot=M, skip=("ny",))
    # Stuetzen hinten (Dreiecksfuesse)
    for fx in (-w / 2 + 0.3, 0.0, w / 2 - 0.3):
        top = c + M @ V(fx, 0.3, -d / 2)
        foot = c + R @ V(fx, -0.5, -0.55)
        beam(frame, top, foot, 0.04, 0.04, "steel_dark")
        box(frame, c + R @ V(fx, -0.49, -0.3), (0.05, 0.02, 0.6), "steel_dark", rot=R, skip=("ny",))
    # Bildschirm
    sc = Part("adscreen_%d" % k, uv=True)
    sw, sh = w - 0.12, h - 0.12
    z = d / 2 + 0.004
    pts = [c + M @ V(-sw / 2, -sh / 2, z), c + M @ V(sw / 2, -sh / 2, z), c + M @ V(sw / 2, sh / 2, z), c + M @ V(-sw / 2, sh / 2, z)]
    sc.face(pts, "adscreen", hint=M @ V(0, 0, 1), uvs=[(0, 0), (1, 0), (1, 1), (0, 1)], jit=0.0)
    return sc.build()


def build_ad_boards():
    """Gleiche Reihenfolge und Positionen wie arena.gd _ad_boards(): erst die Laengsseiten
    (z = -10,5 dann +10,5, je 5 Banden bei x = -12 + b*6), dann die Stirnseiten
    (x = -15 dann +15, je 3 Banden bei z = -6 + b*6). Alle Bildschirme zeigen zum Feld."""
    frame = Part("adboard_frames")
    screens = []
    k = 0
    for sz in (-1.0, 1.0):
        for b in range(5):
            x = -12.0 + b * 6.0
            # Feld liegt bei z = 0: Bande bei z<0 schaut nach +z (Drehung 0), bei z>0 nach -z
            screens.append(ad_board(frame, k, V(x, 0.5, sz * 10.5), 0.0 if sz < 0 else math.pi, 5.8))
            k += 1
    for sx in (-1.0, 1.0):
        for b in range(3):
            z = -6.0 + b * 6.0
            # Bande bei x<0 schaut nach +x: lokale +z auf +x drehen = +90 Grad um y
            screens.append(ad_board(frame, k, V(sx * 15.0, 0.5, z), math.pi / 2 if sx < 0 else -math.pi / 2, 5.8))
            k += 1
    return [frame.build()] + screens


def build_scoreboards():
    """Anzeigetafeln an den Stirnwaenden bei (+-25,6, 6,4, 0), 9 x 3 m, zum Feld gerichtet.
    Bildschirm als eigenes Mesh scorescreen_0 (x<0) und scorescreen_1 (x>0)."""
    fr = Part("scoreboard_frames")
    out = []
    for idx, sx in enumerate((-1.0, 1.0)):
        c = V(sx * 25.6, 6.4, 0)
        inward = V(-sx, 0, 0)
        box(fr, c, (0.4, 3.0, 9.0), "board_frame")
        box(fr, c + V(0, 1.6, 0), (0.42, 0.2, 9.2), "score_header")       # Kopfleiste
        box(fr, c + V(0, -1.6, 0), (0.42, 0.1, 9.2), "steel_dark")
        for z in (-3.0, 3.0):  # Halterungen zur Wand
            beam(fr, c + V(sx * 0.2, 1.4, z), V(sx * WALL_X, 8.6, z), 0.06, 0.06, "steel_dark")
        sc = Part("scorescreen_%d" % idx, uv=True)
        x = c.x - sx * 0.205
        zl, zr = (8.6 / 2, -8.6 / 2) if sx < 0 else (-8.6 / 2, 8.6 / 2)  # links/rechts vom Feld aus gesehen
        y0, y1 = c.y - 1.32, c.y + 1.32
        sc.face([V(x, y0, zl), V(x, y0, zr), V(x, y1, zr), V(x, y1, zl)], "scorescreen", hint=inward,
                uvs=[(0, 0), (1, 0), (1, 1), (0, 1)], jit=0.0)
        out.append(sc.build())
    return [fr.build()] + out


# ------------------------------------------------------------------ Waende, Decke, Licht
def build_hall():
    objs = []
    w = Part("walls")
    # Laengswaende (z = +-20,75): Sockel bis 1,2 m, Farbband 8,2..9,8 m, Fensterband 10,9..12,3 m
    xs, fx = breaks(-WALL_X, WALL_X, [-21 + k * 6 + d for k in range(8) for d in (-2.5, 2.5)], 2.0)
    ys, fy = breaks(0, HALL_H, [1.2, 8.2, 9.8, 10.9, 12.3], 1.8)

    def long_mat(u, v):
        if v < 1.2:
            return "wall_low"
        if 8.2 < v < 9.8:
            return "wall_band"
        return "wall"
    for sz in (-1.0, 1.0):
        grid(w, V(0, 0, sz * WALL_Z), V(1, 0, 0), UP, xs, ys, long_mat, V(0, 0, -sz), fx, fy, jit=0.3, wobble=0.015)
    # Stirnwaende (x = +-25,75): Sockel, Farbband 2,6..4,2 m unter der Anzeigetafel
    zs, fz = breaks(-WALL_Z, WALL_Z, [-17.7, -13.3, 13.3, 17.7, -4.6, 4.6], 2.0)
    ys2, fy2 = breaks(0, HALL_H, [1.2, 2.6, 4.2, 3.6], 1.8)

    def end_mat(u, v):
        if v < 1.2:
            return "wall_low"
        if 2.6 < v < 4.2:
            return "wall_band"
        return "wall"
    for sx in (-1.0, 1.0):
        grid(w, V(sx * WALL_X, 0, 0), V(0, 0, 1), UP, zs, ys2, end_mat, V(-sx, 0, 0), fz, fy2, jit=0.3, wobble=0.015)
    # Wandpfeiler unter den Bindern (Laengswaende, bis unters Fensterband) und in gleichem Takt an den Stirnwaenden
    for sz in (-1.0, 1.0):
        for k in range(7):
            x = -21.0 + k * 7.0
            box(w, V(x, 5.35, sz * (WALL_Z - 0.25)), (0.7, 10.7, 0.5), "wall_low", skip=("ny",))
        # Gesims unter dem Fensterband
        box(w, V(0, 10.75, sz * (WALL_Z - 0.2)), (2 * WALL_X, 0.12, 0.4), "wall_low")
    for sx in (-1.0, 1.0):
        for z in (-19.0, -10.0, 10.0, 19.0):
            box(w, V(sx * (WALL_X - 0.2), 7.0, z), (0.4, 14.0, 0.6), "wall_low", skip=("ny", "py"))
    objs.append(w.build())

    # Fensterband an den Laengswaenden (leuchtet leicht), mit Rahmen und Sprossen
    win = Part("windows")
    wf = Part("window_frames")
    for sz in (-1.0, 1.0):
        z = sz * (WALL_Z - 0.02)
        for k in range(8):
            xc = -21.0 + k * 6.0
            for pane in range(4):
                x0 = xc - 2.5 + pane * 1.25
                win.face([V(x0, 10.9, z), V(x0 + 1.25, 10.9, z), V(x0 + 1.25, 12.3, z), V(x0, 12.3, z)], "window",
                         hint=V(0, 0, -sz), jit=0.12)
                box(wf, V(x0, 11.6, z - sz * 0.04), (0.08, 1.4, 0.08), "window_frame")
            box(wf, V(xc + 2.5, 11.6, z - sz * 0.04), (0.08, 1.4, 0.08), "window_frame")
            box(wf, V(xc, 10.88, z - sz * 0.06), (5.1, 0.08, 0.14), "window_frame")
            box(wf, V(xc, 12.32, z - sz * 0.05), (5.1, 0.08, 0.1), "window_frame")
    objs += [win.build(), wf.build()]

    # Tueren und Spielertunnel in den Ecken der Stirnwaende (zwischen den Tribuenen)
    dr = Part("doors")
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            x = sx * (WALL_X - 0.01)
            zc = sz * 15.5
            if sx > 0 and sz < 0:
                # Spielertunnel: dunkle Oeffnung, vorspringende Seitenwaende und Dach
                dr.face([V(x, 0, zc - 2.0), V(x, 0, zc + 2.0), V(x, 3.2, zc + 2.0), V(x, 3.2, zc - 2.0)], "tunnel_dark",
                        hint=V(-sx, 0, 0))
                for dz in (-2.2, 2.2):
                    box(dr, V(sx * (WALL_X - 1.5), 1.8, zc + dz), (3.0, 3.6, 0.4), "wall_band", skip=("ny",))
                box(dr, V(sx * (WALL_X - 1.5), 3.75, zc), (3.0, 0.3, 4.8), "wall_band")
                box(dr, V(sx * (WALL_X - 3.0), 3.75, zc), (0.04, 0.12, 4.8), "net_band")
                # Lichtband unter dem Tunneldach
                dr.face([V(sx * (WALL_X - 2.6), 3.595, zc - 1.4), V(sx * (WALL_X - 0.4), 3.595, zc - 1.4),
                         V(sx * (WALL_X - 0.4), 3.595, zc + 1.4), V(sx * (WALL_X - 2.6), 3.595, zc + 1.4)], "lamp", hint=V(0, -1, 0))
                grid(dr, V(sx * (WALL_X - 3.0), 0.003, zc - 2.0), V(sx, 0, 0), V(0, 0, 1), [0, 1.0, 2.0, 3.0], [0, 1, 2, 3, 4],
                     lambda u, v: "rubber", UP, (), (), jit=0.2)
            else:
                # Doppeltuer mit Zarge und Notausgangsschild
                dr.face([V(x, 0, zc - 1.0), V(x, 0, zc + 1.0), V(x, 2.4, zc + 1.0), V(x, 2.4, zc - 1.0)], "door",
                        hint=V(-sx, 0, 0))
                box(dr, V(x - sx * 0.03, 1.2, zc), (0.06, 2.4, 0.04), "window_frame")
                for dz in (-1.05, 1.05):
                    box(dr, V(x - sx * 0.05, 1.25, zc + dz), (0.1, 2.5, 0.1), "window_frame")
                box(dr, V(x - sx * 0.05, 2.5, zc), (0.1, 0.1, 2.2), "window_frame")
                for dz in (-0.3, 0.3):
                    box(dr, V(x - sx * 0.06, 1.05, zc + dz), (0.04, 0.04, 0.3), "steel")
                box(dr, V(x - sx * 0.06, 2.8, zc), (0.08, 0.2, 0.45), "exit_sign")
    objs.append(dr.build())

    # Decke: dunkles, leicht unruhiges Dreiecksnetz
    ce = Part("ceiling")
    xs3, fx3 = breaks(-WALL_X, WALL_X, [], 2.5)
    zs3, fz3 = breaks(-WALL_Z, WALL_Z, [], 2.5)
    grid(ce, V(0, HALL_H, 0), V(1, 0, 0), V(0, 0, 1), xs3, zs3, lambda u, v: "ceiling", V(0, -1, 0), (), (), jit=0.3, wobble=0.08)
    objs.append(ce.build())

    # Fachwerkbinder quer ueber die Halle (bei x = -21 + k*7 wie arena.gd), dazu Pfetten
    tr = Part("trusses")
    yt, yb = 13.75, 12.75
    for k in range(7):
        x = -21.0 + k * 7.0
        beam(tr, V(x, yt, -WALL_Z), V(x, yt, WALL_Z), 0.22, 0.2, "truss")
        beam(tr, V(x, yb, -WALL_Z + 1.0), V(x, yb, WALL_Z - 1.0), 0.18, 0.16, "truss")
        n = 26
        zs4 = [-WALL_Z + 1.0 + i * (2 * WALL_Z - 2.0) / n for i in range(n + 1)]
        for i, z in enumerate(zs4):
            beam(tr, V(x, yb, z), V(x, yt, z), 0.07, 0.07, "truss", up=V(0, 0, 1))
            if i < n:
                z2 = zs4[i + 1]
                if i % 2 == 0:
                    beam(tr, V(x, yb, z), V(x, yt, z2), 0.06, 0.06, "truss", up=V(1, 0, 0))
                else:
                    beam(tr, V(x, yt, z), V(x, yb, z2), 0.06, 0.06, "truss", up=V(1, 0, 0))
        # Auflager an der Wand
        for sz in (-1, 1):
            box(tr, V(x, yt - 0.6, sz * (WALL_Z - 0.2)), (0.4, 1.6, 0.4), "truss")
    for z in (-17.5, -10.5, -3.5, 3.5, 10.5, 17.5):
        beam(tr, V(-WALL_X, 13.95, z), V(WALL_X, 13.95, z), 0.12, 0.1, "truss")
    objs.append(tr.build())

    # Lichtfelder zwischen den Bindern: Gehaeuse plus leuchtende Unterseite (Material "lamp")
    lh = Part("lamp_housings")
    lp = Part("lamps")
    for xi in range(6):
        for zi in range(5):
            x = -17.5 + xi * 7.0
            z = -14.0 + zi * 7.0
            y = 13.1
            box(lh, V(x, y + 0.13, z), (2.6, 0.26, 1.2), "lamp_housing", skip=())
            for dx in (-1.0, 1.0):
                cyl(lh, V(x + dx, y + 0.26, z), V(x + dx, HALL_H, z), 0.012, 0.012, 4, "steel_dark")
            lp.face([V(x - 1.2, y - 0.005, z - 0.5), V(x + 1.2, y - 0.005, z - 0.5), V(x + 1.2, y - 0.005, z + 0.5),
                     V(x - 1.2, y - 0.005, z + 0.5)], "lamp", hint=V(0, -1, 0), jit=0.06)
    objs += [lh.build(), lp.build()]

    # Banner in Vereinsfarben, an den Bindern haengend (ueber den Tribuenen)
    bn = Part("banners")
    spots = []
    for sz in (-1.0, 1.0):
        for x in (-14.0, -7.0, 7.0, 14.0):
            spots.append((V(x, 0, sz * 18.6), "banner_navy" if x < 0 else "banner_wine", V(1, 0, 0)))
    for sx in (-1.0, 1.0):
        for z in (-7.0, 7.0):
            spots.append((V(sx * 21.0, 0, z), "banner_navy" if sx < 0 else "banner_wine", V(0, 0, 1)))
    for base, m, along in spots:
        banner(bn, base, m, along)
    objs.append(bn.build())
    return objs


def banner(p, base, mat, along):
    """Haengendes Fahnenbanner 1,6 x 4,4 m mit Spitze unten, weisser Streifen und Raute,
    leicht gewellt. Doppelseitig (Vorder- und Rueckseite)."""
    n = UP.cross(along).normalized()
    top = 12.6
    wdt, hgt = 1.6, 4.4
    cols = 4
    rows = 6

    def P(u, v):  # u -1..1 quer, v 0 (oben) .. 1 (unten)
        wave = 0.06 * math.sin(u * 2.4 + v * 3.0) + 0.03 * math.sin(v * 7.0)
        y = top - v * hgt
        if v >= 1.0 - 1e-6:
            y -= (1.0 - abs(u)) * 0.6  # Spitze
        return base + along * (u * wdt / 2) + UP * y + n * wave
    for i in range(cols):
        for j in range(rows):
            u0, u1 = -1 + 2 * i / cols, -1 + 2 * (i + 1) / cols
            v0, v1 = j / rows, (j + 1) / rows
            vm = (v0 + v1) / 2
            m = "banner_white" if 0.62 < vm < 0.72 else mat
            q = [P(u0, v0), P(u1, v0), P(u1, v1), P(u0, v1)]
            for sgn in (1, -1):
                off = n * 0.004 * sgn
                if (i + j) % 2:
                    p.face([q[0] + off, q[1] + off, q[2] + off], m, hint=n * sgn)
                    p.face([q[0] + off, q[2] + off, q[3] + off], m, hint=n * sgn)
                else:
                    p.face([q[0] + off, q[1] + off, q[3] + off], m, hint=n * sgn)
                    p.face([q[1] + off, q[2] + off, q[3] + off], m, hint=n * sgn)
    # Raute (Vereinszeichen) auf beiden Seiten
    c = base + UP * (top - 1.6)
    for sgn in (1, -1):
        off = n * (0.075 * sgn)
        pts = [c + UP * 0.45, c + along * 0.4, c - UP * 0.45, c - along * 0.4]
        p.face([q + off for q in pts], "banner_white", hint=n * sgn)
    # Stange oben und Haltedraehte
    beam(p, base + UP * (top + 0.03) - along * (wdt / 2 + 0.1), base + UP * (top + 0.03) + along * (wdt / 2 + 0.1),
         0.05, 0.05, "steel_dark", caps=True)
    for s in (-1, 1):
        cyl(p, base + UP * top + along * s * 0.7, base + UP * 13.75 + along * s * 0.7, 0.01, 0.01, 3, "steel_dark")


# ------------------------------------------------------------------ Einzelteile
def build_ball():
    """Volleyball r = 0,105 m: Wuerfelkugel aus 6 Seiten mit je 3 Streifen (klassisches
    18-Feld-Muster, benachbarte Seiten quer zueinander), Farben gelb/blau/weiss gedeckt.
    Je Seite 3 Streifen x 2 Teilungen x 4 laengs = 24 Vierecke -> 288 Dreiecke."""
    p = Part("ball")
    R = 0.105
    cols = ["ball_yellow", "ball_blue", "ball_white"]
    axes = [V(1, 0, 0), V(0, 1, 0), V(0, 0, 1)]
    for a in range(3):
        for s in (1, -1):
            nrm = axes[a] * s
            e1 = axes[(a + 1) % 3]   # Streifen wechseln entlang e1
            e2 = axes[(a + 2) % 3]

            def S(pp, qq):
                # gleichwinklige Wuerfel-Abbildung, dann auf die Kugel
                v = nrm + e1 * math.tan(pp * math.pi / 4) + e2 * math.tan(qq * math.pi / 4)
                return v.normalized() * R
            ps = [-1 + 2 * i / 6 for i in range(7)]
            qs = [-1 + 2 * j / 4 for j in range(5)]
            for i in range(6):
                strip_i = i // 2
                m = cols[(strip_i + a + (0 if s > 0 else 1)) % 3]
                for j in range(4):
                    q = [S(ps[i], qs[j]), S(ps[i + 1], qs[j]), S(ps[i + 1], qs[j + 1]), S(ps[i], qs[j + 1])]
                    cen = sum(q, Vector()) / 4
                    if (i + j) % 2:
                        p.face([q[0], q[1], q[2]], m, hint=cen, jit=0.1)
                        p.face([q[0], q[2], q[3]], m, hint=cen, jit=0.1)
                    else:
                        p.face([q[0], q[1], q[3]], m, hint=cen, jit=0.1)
                        p.face([q[1], q[2], q[3]], m, hint=cen, jit=0.1)
    return p.build()


def build_flag():
    """Linienrichterfahne: Stab 0,5 m (Ursprung = Griff, Stab von -0,06 bis 0,44 m),
    Tuch 0,4 x 0,4 m rot/gelb kariert (4 x 4), leicht gewellt, doppelseitig, haengt nach +x."""
    p = Part("flag")
    cyl(p, V(0, -0.06, 0), V(0, 0.44, 0), 0.011, 0.011, 6, "flag_stick")
    cyl(p, V(0, 0.44, 0), V(0, 0.455, 0), 0.014, 0.008, 6, "flag_stick")
    cyl(p, V(0, -0.07, 0), V(0, 0.08, 0), 0.015, 0.015, 6, "rubber")  # Griff
    n = 4
    s = 0.1

    def P(i, j):
        x = 0.012 + i * s
        y = 0.04 + j * s
        return V(x, y, 0.018 * math.sin(i * 1.3 + j * 0.4) * (i / n))
    for i in range(n):
        for j in range(n):
            m = "flag_red" if (i + j) % 2 == 0 else "flag_yellow"
            q = [P(i, j), P(i + 1, j), P(i + 1, j + 1), P(i, j + 1)]
            for sgn in (1, -1):
                off = V(0, 0, 0.0015 * sgn)
                p.face([q[0] + off, q[1] + off, q[2] + off], m, hint=V(0, 0, sgn), jit=0.08)
                p.face([q[0] + off, q[2] + off, q[3] + off], m, hint=V(0, 0, sgn), jit=0.08)
    return p.build()


def ring_loft(p, rings, mat, shades, caps=(True, True)):
    """Verbindet gleich grosse Ringe (Listen von Punkten) zu einer Roehre."""
    for k, (a, b) in enumerate(zip(rings, rings[1:])):
        n = len(a)
        ca = sum(a, Vector()) / n
        cb = sum(b, Vector()) / n
        for i in range(n):
            j = (i + 1) % n
            q = [a[i], a[j], b[j], b[i]]
            cen = sum(q, Vector()) / 4
            axis = (cb - ca).normalized()
            out = cen - (ca + cb) / 2
            out -= axis * out.dot(axis)
            sh = shades[k](cen) if callable(shades[k]) else shades[k]
            p.face(q, mat, hint=out, shade=sh)
    if caps[0]:
        a = rings[0]
        sh = shades[0](sum(a, Vector()) / len(a)) if callable(shades[0]) else shades[0]
        p.face(a, mat, hint=sum(a, Vector()) / len(a) - sum(rings[1], Vector()) / len(rings[1]), shade=sh)
    if caps[1]:
        a = rings[-1]
        sh = shades[-1](sum(a, Vector()) / len(a)) if callable(shades[-1]) else shades[-1]
        p.face(a, mat, hint=sum(a, Vector()) / len(a) - sum(rings[-2], Vector()) / len(rings[-2]), shade=sh)


def ring(c, rx, rz, seg, phase=0.0, axis="y"):
    out = []
    for i in range(seg):
        a = phase + i / seg * math.tau
        if axis == "y":
            out.append(c + V(math.cos(a) * rx, 0, math.sin(a) * rz))
        else:
            out.append(c + V(math.cos(a) * rx, math.sin(a) * rz, 0))
    return out


def build_fans():
    """Zuschauer-Bausteine fuer die MultiMesh-Menge, alle mit EINEM weissen Material
    ("fan"), Farbe kommt pro Instanz. Die Vertexfarbe traegt Facetten-Streuung und dunkelt
    Hose/Schuhe (Beine) und Haare ab, damit eine Tönung pro Instanz trotzdem lebendig wirkt.
    Schaut nach -z (Godot) = +Y (Blender)."""
    out = []
    PANTS = (0.42, 0.43, 0.48)
    SHOE = (0.25, 0.25, 0.27)
    # --- Koerper: Ursprung = Mitte der Sitzflaeche; Rumpf bis Hals 0,64 m, Fuesse bei -0,42
    b = Part("fan_body")
    torso = [
        ring(V(0, 0.0, 0.02), 0.17, 0.12, 6, math.pi / 6),
        ring(V(0, 0.24, 0.02), 0.15, 0.105, 6, math.pi / 6),
        ring(V(0, 0.46, 0.01), 0.19, 0.115, 6, math.pi / 6),
        ring(V(0, 0.58, 0.015), 0.2, 0.1, 6, math.pi / 6),
        ring(V(0, 0.65, 0.02), 0.07, 0.06, 6, math.pi / 6),
    ]
    ring_loft(b, torso, "fan", [1.0, 1.0, 1.0, 1.0], caps=(True, True))
    for s in (-1, 1):
        x = s * 0.09
        hip = V(x, 0.08, 0.0)
        knee = V(x * 1.05, 0.1, -0.44)
        ankle = V(x * 1.05, -0.36, -0.48)
        # Oberschenkel (5-eckig, ohne Deckel), Unterschenkel, Fuss
        cyl(b, hip, knee, 0.085, 0.065, 5, "fan", caps=(False, True), shade=PANTS)
        cyl(b, knee, ankle, 0.062, 0.05, 5, "fan", caps=(True, False), shade=PANTS)
        box(b, V(x * 1.05, -0.39, -0.53), (0.1, 0.07, 0.22), "fan", skip=("ny",), shade=SHOE)
    out.append(b.build())
    # --- Kopf: Ursprung am Hals, Kopf ~0,25 m hoch, Nase nach -z. Haare sind die oberen und
    # hinteren Facetten (dunkle Vertexfarbe), vorn bleibt eine Stirn frei.
    h = Part("fan_head")
    HAIR = (0.3, 0.26, 0.23)

    def hair(c):
        if c.y > 0.2 or (c.y > 0.13 and c.z > -0.06) or (c.y > 0.07 and c.z > 0.05):
            return HAIR
        return 1.0
    rings = []
    prof = [(0.0, 0.045), (0.04, 0.085), (0.11, 0.1), (0.18, 0.092), (0.235, 0.055)]
    for y, r in prof:
        rings.append(ring(V(0, y, 0.0), r, r * 1.1, 7, 0.0))
    # Hinterkopf etwas ausladender, Kinn nach vorn
    for v in rings[2] + rings[3]:
        if v.z > 0.03:
            v.z += 0.012
    for v in rings[1]:
        if v.z < -0.03:
            v.z -= 0.01
    ring_loft(h, rings, "fan", [hair] * 4, caps=(True, False))
    tip = V(0, 0.262, 0.01)
    last = rings[-1]
    for i in range(7):
        a_, b_ = last[i], last[(i + 1) % 7]
        h.face([a_, b_, tip], "fan", hint=(a_ + b_) / 2 - V(0, 0.12, 0), shade=HAIR)
    # Nase
    nb = V(0, 0.12, -0.108)
    h.face([nb + V(-0.018, 0.0, 0.01), nb + V(0.018, 0.0, 0.01), nb + V(0, 0.04, 0.012)], "fan", hint=V(0, 0, -1))
    h.face([nb + V(-0.018, 0.0, 0.01), nb + V(0, 0.04, 0.012), nb + V(0, 0.01, -0.025)], "fan", hint=V(-1, 0, -1))
    h.face([nb + V(0.018, 0.0, 0.01), nb + V(0, 0.01, -0.025), nb + V(0, 0.04, 0.012)], "fan", hint=V(1, 0, -1))
    out.append(h.build())
    # --- Arm: Ursprung an der Schulter, haengt nach unten (-y Godot = -Z Blender), 0,58 m
    a = Part("fan_arm")
    arm = [ring(V(0, 0.0, 0), 0.052, 0.052, 5, 0.3), ring(V(0, -0.3, 0.005), 0.042, 0.042, 5, 0.3),
           ring(V(0, -0.58, 0.0), 0.034, 0.03, 5, 0.3)]
    ring_loft(a, arm, "fan", [1.0, 1.0], caps=(True, True))
    out.append(a.build())
    return out


# ------------------------------------------------------------------ Export, Vorschau
def export(path, objs=None):
    bpy.ops.object.select_all(action="DESELECT")
    if objs is None:
        objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_apply=False, export_animations=False, export_yup=True,
                              export_vertex_color="NAME", export_vertex_color_name="Col",
                              export_all_vertex_colors=False, export_materials="EXPORT",
                              export_extras=False)


def tris(objs):
    return sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)


def preview_materials():
    """Nur fuer die Vorschau: Vertexfarbe "Col" mit der Grundfarbe multiplizieren."""
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        nt = m.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        if bsdf is None or bsdf.inputs["Base Color"].is_linked:
            continue
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs[0].default_value = 1.0
        mix.inputs[6].default_value = bsdf.inputs["Base Color"].default_value
        nt.links.new(attr.outputs["Color"], mix.inputs[7])
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])


def setup_render(res=(int(os.environ.get("RESX", "1280")), int(os.environ.get("RESY", "720"))), samples=int(os.environ.get("SPP", "48"))):
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    scn.cycles.device = "CPU"
    scn.cycles.samples = samples
    scn.cycles.use_denoising = True
    scn.cycles.max_bounces = 4
    scn.cycles.diffuse_bounces = 3
    scn.cycles.glossy_bounces = 1
    scn.cycles.transmission_bounces = 0
    scn.cycles.transparent_max_bounces = 2
    scn.render.resolution_x, scn.render.resolution_y = res
    scn.render.resolution_percentage = 100
    scn.view_settings.view_transform = "AgX"
    scn.view_settings.look = "AgX - Base Contrast" if False else "None"
    if scn.world is None:
        scn.world = bpy.data.worlds.new("w")
    scn.world.use_nodes = True
    return scn


def camera(scn, name, pos_g, target_g, fov=52.0):
    cam = bpy.data.objects.get(name)
    if cam is None:
        cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
        scn.collection.objects.link(cam)
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle_y = math.radians(fov)
    cam.data.clip_end = 300
    cam.location = G(pos_g)
    d = G(target_g) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scn.camera = cam
    return cam


def render(scn, path):
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("Vorschau:", path)


def hall_lights(scn):
    """Vorschau-Licht in der geschlossenen Halle: grosse Flaechenlichter unter der Decke
    (weich, wie in der Vorlage) plus etwas Umgebungslicht."""
    scn.world.node_tree.nodes["Background"].inputs[0].default_value = (0.5, 0.52, 0.56, 1)
    scn.world.node_tree.nodes["Background"].inputs[1].default_value = 0.0
    for xi in range(3):
        for zi in range(3):
            ld = bpy.data.lights.new("area%d%d" % (xi, zi), "AREA")
            ld.shape = "RECTANGLE"
            ld.size, ld.size_y = 14.0, 11.0
            ld.energy = float(os.environ.get("LIGHT", "900"))
            ld.color = (1.0, 0.97, 0.92)
            ob = bpy.data.objects.new(ld.name, ld)
            ob.location = G(V(-16 + xi * 16, 12.4, -13 + zi * 13))
            scn.collection.objects.link(ob)
    # Sonne von schraeg oben fuer klare Facetten-Schattierung; die Decke wirft dafuer
    # in der Vorschau keinen Schatten (nur Vorschau, aendert den Export nicht).
    for name in ("ceiling", "lamp_housings", "trusses"):
        ob = bpy.data.objects.get(name)
        if ob:
            ob.visible_shadow = False
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = float(os.environ.get("SUN", "4.0"))
    sun.data.angle = math.radians(8)
    sun.data.color = (1.0, 0.96, 0.9)
    sun.rotation_euler = (math.radians(32), math.radians(-18), math.radians(-30))
    scn.collection.objects.link(sun)
    # Werbebanden in der Vorschau mit ruhigen Farbflaechen (im Spiel kommt Text darauf)
    for k in range(16):
        ob = bpy.data.objects.get("adscreen_%d" % k)
        if ob is None:
            continue
        hexes = ["#3E5878", "#6E3A45", "#4E6E68", "#8A6A3E", "#45506A", "#5C4A6A"]
        m = bpy.data.materials.new("prev_ad_%d" % k)
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        c = srgb(hexes[k % len(hexes)])
        b.inputs["Base Color"].default_value = c
        b.inputs["Emission Color"].default_value = c
        b.inputs["Emission Strength"].default_value = 0.8
        ob.data.materials[0] = m


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    # ---------------- Arena
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objs = []
    objs += build_floor()
    objs += build_net()
    objs += build_referee_stand()
    objs += build_officials()
    objs += build_stands()
    objs += build_ad_boards()
    objs += build_scoreboards()
    objs += build_hall()
    export(os.path.join(OUT_DIR, "arena.glb"), objs)
    print("ARENA Dreiecke:", tris(objs))
    for o in sorted(objs, key=lambda o: -tris([o])):
        print("   %-20s %6d  %s" % (o.name, tris([o]), [m.name for m in o.data.materials]))
    if PREVIEW:
        os.makedirs(PREVIEW, exist_ok=True)
        preview_materials()
        scn = setup_render()
        hall_lights(scn)
        views = {
            "overview": (V(-16, 7, 0), V(1.5, 1, 0), 52),
            "net_referee": (V(-3.6, 2.4, -2.2), V(0, 1.4, -5.9), 50),
            "officials": (V(0.5, 3.2, 2.0), V(0, 0.5, 9.0), 68),
            "hall": (V(-21, 5.5, 9), V(14, 6.5, -12), 62),
            "stand": (V(-6, 3.0, 8.5), V(-9, 1.6, 14), 55),
        }
        only = os.environ.get("VIEWS")
        for name, (pos, tgt, fov) in views.items():
            if only and name not in only.split(","):
                continue
            camera(scn, "cam_" + name, pos, tgt, fov)
            render(scn, os.path.join(PREVIEW, "arena_%s.png" % name))

    # ---------------- Einzelteile (Ball, Fahne, Zuschauer)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ball = build_ball()
    export(os.path.join(OUT_DIR, "ball.glb"), [ball])
    flag = build_flag()
    export(os.path.join(OUT_DIR, "flag.glb"), [flag])
    fans = build_fans()
    export(os.path.join(OUT_DIR, "fan.glb"), fans)
    print("BALL Dreiecke:", tris([ball]), " FLAG:", tris([flag]),
          " FAN:", {o.name: tris([o]) for o in fans})
    if PREVIEW and not os.environ.get("VIEWS"):
        preview_materials()
        scn = setup_render((1200, 700), 64)
        scn.world.node_tree.nodes["Background"].inputs[0].default_value = (0.13, 0.135, 0.145, 1)
        scn.world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
        sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
        sun.data.energy = 3.0
        sun.rotation_euler = (math.radians(40), math.radians(15), math.radians(-35))
        scn.collection.objects.link(sun)
        # Teile nebeneinander aufstellen (nur fuer das Bild, Export ist schon fertig)
        ball.location = G(V(-0.9, 0.62, 0))
        ball.scale = (2.6, 2.6, 2.6)
        flag.location = G(V(-0.45, 0.35, 0))
        flag.scale = (1.4, 1.4, 1.4)
        body, head, arm = fans
        for o in fans:
            o.location = G(V(0.55, 0.45, 0))
        head.location = G(V(0.55, 0.45 + 0.65, 0.02))
        arm.location = G(V(0.55 + 0.22, 0.45 + 0.57, 0.0))
        arm2 = arm.copy()
        bpy.context.collection.objects.link(arm2)
        arm2.location = G(V(0.55 - 0.22, 0.45 + 0.57, 0.0))
        body.rotation_euler = (0, 0, math.radians(-150))
        head.rotation_euler = body.rotation_euler
        arm.rotation_euler = body.rotation_euler
        arm2.rotation_euler = body.rotation_euler
        # Arme um den Koerper mitdrehen
        for o, sx in ((arm, 0.22), (arm2, -0.22)):
            rel = Matrix.Rotation(math.radians(-150), 3, "Z") @ G(V(sx, 0, 0))
            o.location = G(V(0.55, 0.45 + 0.57, 0.0)) + rel
        # Bodenplatte
        bm = bmesh.new()
        bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=6)
        me = bpy.data.meshes.new("ground")
        bm.to_mesh(me)
        g = bpy.data.objects.new("ground", me)
        g.data.materials.append(material("free_zone"))
        scn.collection.objects.link(g)
        g.location = (0, 0, -0.0)
        camera(scn, "cam_parts", V(0.0, 1.3, 2.6), V(0.0, 0.6, 0), 32)
        render(scn, os.path.join(PREVIEW, "parts.png"))
    print("FERTIG", OUT_DIR)


main()
