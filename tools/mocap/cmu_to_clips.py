"""Echte Bewegungsdaten (CMU-Motion-Capture, BVH) auf das Spielskelett uebertragen.

Aufruf:  python3 cmu_to_clips.py <ausgabe.json> [--trim] <name>=<datei.bvh>[:von:bis] ...
(--trim: bei Spruengen nur das Stueck um den Sprung behalten)

Fuer jedes Spielgelenk wird ein CMU-Knochen gewaehlt (Tabelle MAP). Uebertragen wird die
Drehung gegenueber der Ruhehaltung ("Rest-Delta"): Die Ruhehaltungen beider Skelette sind
verschieden (CMU: Arme waagerecht, Spiel: Arme haengen), deshalb dreht eine feste Korrektur C je
Knochen die Knochenrichtung der Spielfigur auf die des CMU-Skeletts. Fuer jedes Bild gilt dann
    Welt(Spielgelenk) = Welt(CMU-Knochen) * C
und daraus die Drehung gegenueber dem Elterngelenk, wie in player_clips.json (Achsen der Figur:
x rechts, y oben, z hinten; Ruhehaltung = keine Drehung).
Die Blickrichtung des ersten Bildes wird herausgerechnet (die Figur schaut nach vorn), die
Hueftverschiebung wird nicht gespeichert (wie bei den Meshy-Clips), nur ihre Hoehe zur Auswertung.
Erkannt werden ausserdem Absprung und Landung (beide Fuesse in der Luft / wieder am Boden).
Ausgabe: {name: {fps, frames: [{gelenk: [x, y, z, w]}], hip_y: [...], ev: {...}}}
"""
import json
import math
import sys

import numpy as np

FPS_OUT = 60.0
TRIM = "--trim" in sys.argv
# Spielgelenk -> (CMU-Knochen, Kind fuer die Knochenrichtung)
MAP = {"hips": ("root", "upperback"), "chest": ("thorax", "lowerneck"), "head": ("head", None)}
for sd in "lr":
    MAP.update({"sh_" + sd: (sd + "humerus", sd + "radius"), "el_" + sd: (sd + "radius", sd + "wrist"),
                "wr_" + sd: (sd + "hand", sd + "fingers"), "hip_" + sd: (sd + "femur", sd + "tibia"),
                "kn_" + sd: (sd + "tibia", sd + "foot"), "an_" + sd: (sd + "foot", sd + "toes")})
PARENT = {"hips": None, "chest": "hips", "head": "chest"}
for sd in "lr":
    PARENT.update({"sh_" + sd: "chest", "el_" + sd: "sh_" + sd, "wr_" + sd: "el_" + sd,
                   "hip_" + sd: "hips", "kn_" + sd: "hip_" + sd, "an_" + sd: "kn_" + sd})
ORDER = ["hips", "chest", "head", "sh_l", "el_l", "wr_l", "sh_r", "el_r", "wr_r",
         "hip_l", "kn_l", "an_l", "hip_r", "kn_r", "an_r"]
# Knochenrichtungen der Spielfigur in Ruhe (aus HumanFigure._rest_pos; Fuss: Knoechel -> Spitze,
# Hand: Handgelenk -> Mittelfinger, Kopf: senkrecht)
REST = {"hips": [-0.004, 1.068, -0.008], "chest": [-0.004, 1.208, 0.0], "head": [-0.004, 1.553, 0.019],
        "sh_l": [-0.190, 1.516, 0.033], "el_l": [-0.198, 1.285, 0.033], "wr_l": [-0.206, 1.062, 0.033],
        "sh_r": [0.190, 1.516, 0.033], "el_r": [0.198, 1.285, 0.033], "wr_r": [0.206, 1.062, 0.033],
        "hip_l": [-0.108, 0.973, -0.007], "kn_l": [-0.150, 0.591, 0.0], "an_l": [-0.191, 0.095, 0.053],
        "hip_r": [0.097, 0.973, -0.007], "kn_r": [0.138, 0.591, -0.001], "an_r": [0.187, 0.095, 0.055]}
CHILD = {"hips": "chest", "chest": "head", "sh_l": "el_l", "el_l": "wr_l", "sh_r": "el_r", "el_r": "wr_r",
         "hip_l": "kn_l", "kn_l": "an_l", "hip_r": "kn_r", "kn_r": "an_r"}


# ---------------------------------------------------------------- Quaternionen [w, x, y, z]
def qmul(a, b):
    w1, x1, y1, z1 = a
    w2, x2, y2, z2 = b
    return np.array([w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2, w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2,
                     w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2, w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2])


def qinv(q):
    return np.array([q[0], -q[1], -q[2], -q[3]])


def qaxis(ax, ang):
    ax = np.asarray(ax, float) / np.linalg.norm(ax)
    return np.concatenate([[math.cos(ang / 2)], ax * math.sin(ang / 2)])


def qrot(q, v):
    return qmul(qmul(q, np.concatenate([[0.0], v])), qinv(q))[1:]


def qarc(a, b):
    a = np.asarray(a, float) / np.linalg.norm(a)
    b = np.asarray(b, float) / np.linalg.norm(b)
    c = np.cross(a, b)
    d = float(a @ b)
    if d < -0.9999:
        ax = np.cross(a, [0, 1, 0] if abs(a[1]) < 0.9 else [1, 0, 0])
        return qaxis(ax, math.pi)
    q = np.array([1.0 + d, c[0], c[1], c[2]])
    return q / np.linalg.norm(q)


AX = {"X": [1, 0, 0], "Y": [0, 1, 0], "Z": [0, 0, 1]}
# CMU: links = +x, vorn = +z. Spiel: rechts = +x, vorn = -z. Halbe Drehung um die Hochachse.
K = qaxis([0, 1, 0], math.pi)


def parse_bvh(path):
    toks = open(path).read().split()
    i = 0
    joints, stack, order = {}, [], []
    while toks[i] != "MOTION":
        t = toks[i]
        if t in ("ROOT", "JOINT"):
            name = toks[i + 1]
            joints[name] = {"parent": stack[-1] if stack else None, "off": None, "ch": []}
            order.append(name)
            cur = name
            i += 2
        elif t == "End":
            cur = None
            i += 2
        elif t == "{":
            stack.append(cur)
            i += 1
        elif t == "}":
            stack.pop()
            i += 1
        elif t == "OFFSET":
            off = np.array([float(x) for x in toks[i + 1:i + 4]])
            if cur is not None:
                joints[cur]["off"] = off
            else:  # End Site: Endpunkt des Elterngelenks
                joints[stack[-2]]["end"] = off
            i += 4
        elif t == "CHANNELS":
            n = int(toks[i + 1])
            joints[cur]["ch"] = toks[i + 2:i + 2 + n]
            i += 2 + n
        else:
            i += 1
    nfr = int(toks[i + 2])
    dt = float(toks[i + 5])
    data = np.array([float(x) for x in toks[i + 6:]]).reshape(nfr, -1)
    return joints, order, data, dt


def fk(joints, order, row):
    """Weltdrehung und -position je CMU-Gelenk fuer ein Bild (in Spielachsen)."""
    g, p = {}, {}
    c = 0
    for n in order:
        jn = joints[n]
        loc = np.array([1.0, 0, 0, 0])
        pos = np.zeros(3)
        for ch in jn["ch"]:
            v = row[c]
            c += 1
            if ch.endswith("position"):
                pos[{"X": 0, "Y": 1, "Z": 2}[ch[0]]] = v
            else:
                loc = qmul(loc, qaxis(AX[ch[0]], math.radians(v)))
        par = jn["parent"]
        if par is None:
            g[n] = loc
            p[n] = pos + jn["off"]
        else:
            g[n] = qmul(g[par], loc)
            p[n] = p[par] + qrot(g[par], jn["off"])
    return {n: qmul(qmul(K, q), qinv(K)) for n, q in g.items()}, {n: qrot(K, v) for n, v in p.items()}


def convert(path, t0=None, t1=None):
    joints, order, data, dt = parse_bvh(path)
    # Korrektur je Spielgelenk: Spiel-Knochenrichtung -> CMU-Knochenrichtung (Ruhehaltung)
    C = {}
    for gj, (cb, cc) in MAP.items():
        if gj in ("hips", "head") or cc is None:
            d_cmu = qrot(K, joints[cc]["off"]) if cc else np.array([0, 1.0, 0])
        else:
            d_cmu = qrot(K, joints[cc]["off"])
        if gj.startswith("an_"):
            # Fuss: nur die waagerechte Richtung angleichen (flacher Fuss bleibt flach)
            d_cmu = np.array([d_cmu[0], 0.0, d_cmu[2]])
            d_our = np.array([0.0, 0.0, -1.0])
        elif gj.startswith("wr_"):
            d_our = np.array([0.0, -1.0, 0.0])
        elif gj in CHILD:
            d_our = np.array(REST[CHILD[gj]]) - np.array(REST[gj])
        else:
            d_our = np.array([0.0, 1.0, 0.0])
        if gj == "hips":
            C[gj] = np.array([1.0, 0, 0, 0])  # Becken: beide Ruhehaltungen stehen aufrecht
        else:
            C[gj] = qarc(d_our, d_cmu)
    nfr = data.shape[0]
    f0 = 0 if t0 is None else max(0, int(round(t0 / dt)))
    f1 = nfr - 1 if t1 is None else min(nfr - 1, int(round(t1 / dt)))
    # Blickrichtung des ersten Bildes herausrechnen
    g0, _ = fk(joints, order, data[f0])
    fwd = qrot(g0["root"], [0, 0, -1.0])
    yaw0 = math.atan2(-fwd[0], -fwd[2])
    Y = qaxis([0, 1, 0], -yaw0)
    frames, hip_y, feet = [], [], []
    n_out = int((f1 - f0) * dt * FPS_OUT) + 1
    for k in range(n_out):
        fi = f0 + k / FPS_OUT / dt
        a = int(math.floor(fi))
        b = min(a + 1, f1)
        w = fi - a
        row = data[a] * (1 - w) + data[b] * w if b != a else data[a]  # Kanaele linear (fein genug bei 120 Hz)
        g, p = fk(joints, order, row)
        G = {gj: qmul(Y, qmul(g[cb], C[gj])) for gj, (cb, _) in MAP.items()}
        fr = {}
        for gj in ORDER:
            par = PARENT[gj]
            L = G[gj] if par is None else qmul(qinv(G[par]), G[gj])
            if L[0] < 0:
                L = -L
            fr[gj] = [round(float(L[1]), 5), round(float(L[2]), 5), round(float(L[3]), 5), round(float(L[0]), 5)]
        frames.append(fr)
        hip_y.append(float(p["root"][1]))
        feet.append((float(min(p["ltoes"][1], p["lfoot"][1])), float(min(p["rtoes"][1], p["rfoot"][1]))))
    # Absprung und Landung aus der Hueftbahn (die ist ballistisch korrekt: im Flug faellt sie mit
    # etwa 9,8 m/s^2). Absprung = schnellste Aufwaertsbewegung vor dem hoechsten Punkt (danach bremst
    # die Schwerkraft), Landung = schnellste Abwaertsbewegung danach (dann fangen die Beine ab).
    # (Die Fuesse taugen dafuer nicht: in tiefer Hocke schweben sie in den Daten ueber dem Boden.)
    hy = np.array(hip_y)
    hip_y = [round(float(v), 4) for v in hy]
    ev = {}
    stand = float(np.median(hy[:max(5, len(hy) // 10)]))
    k = int(np.argmax(hy))
    if hy[k] - stand > 0.12:
        v = np.gradient(hy) * FPS_OUT
        w = int(0.6 * FPS_OUT)
        a0 = max(1, k - w)
        to = a0 + int(np.argmax(v[a0:k + 1]))
        la = k + int(np.argmin(v[k:min(len(v), k + w)]))
        lo = int(np.argmin(hy[max(0, to - w):to + 1])) + max(0, to - w)  # tiefster Punkt vor dem Absprung
        ev = {"crouch": lo, "takeoff": to, "peak": k, "land": la, "rise": round(float(hy[k] - stand), 3),
              "dip": round(float(stand - hy[lo]), 3)}
    if ev and TRIM:
        # Nur der Sprung: 0,7 s vor dem tiefsten Punkt bis 0,9 s nach der Landung
        a = max(0, ev["crouch"] - int(0.7 * FPS_OUT))
        b = min(len(frames), ev["land"] + int(0.9 * FPS_OUT))
        frames, hip_y = frames[a:b], hip_y[a:b]
        for k in ("crouch", "takeoff", "peak", "land"):
            ev[k] -= a
        ev["stand"] = round(stand, 4)
    return {"fps": FPS_OUT, "frames": frames, "hip_y": hip_y, "ev": ev, "src": path.split("/")[-1]}


if __name__ == "__main__":
    out = {}
    for arg in [x for x in sys.argv[2:] if not x.startswith("--")]:
        name, spec = arg.split("=", 1)
        parts = spec.split(":")
        t0 = float(parts[1]) if len(parts) > 1 else None
        t1 = float(parts[2]) if len(parts) > 2 else None
        out[name] = convert(parts[0], t0, t1)
        print(name, len(out[name]["frames"]), out[name]["ev"])
    json.dump(out, open(sys.argv[1], "w"), separators=(",", ":"))
