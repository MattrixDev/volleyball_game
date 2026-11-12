"""Aus einem Video gelesene Gelenke (video_pose.py) auf das Spielskelett uebertragen.

Aufruf:  python3 video_to_clip.py <pose.json> <ausgabe.json> <name> [von_s] [bis_s] [glaettung_bilder] [blick_glaettung_s]

MediaPipe liefert je Bild 33 Punkte in Metern (um die Huefte). Daraus wird je Spielgelenk eine
Weltdrehung gebaut:
  - Becken und Brust: aus Huefte- bzw. Schulterlinie (seitlich) und Wirbelsaeule (oben),
  - Arme und Beine: kuerzeste Drehung der Ruhe-Knochenrichtung auf die gemessene Richtung, dazu
    eine Drehung um den Oberarm/Oberschenkel, sodass Ellbogen und Knie in ihrer Ebene beugen,
  - Hand und Fuss: Richtung Handgelenk -> Finger bzw. Ferse -> Zehen.
Die Blickrichtung wird langsam (Gauss, blick_glaettung_s, Standard 0,35 s) herausgerechnet: Die
Kamera schwenkt im Video, schnelle Rumpfdrehungen (Schlag) bleiben erhalten. Bei Zeitlupe den
Wert groesser waehlen, sonst wird auch die Rumpfdrehung des Schlags herausgerechnet. Die Punkte werden vorher zeitlich
geglaettet (Gauss), danach auf 60 Bilder/s gebracht. Ausgabe wie cmu_to_clips.py.
"""
import json
import math
import sys

import numpy as np

sys.argv, _argv = sys.argv[:1], sys.argv  # cmu_to_clips liest beim Import keine Argumente
from cmu_to_clips import ORDER, PARENT, REST, CHILD, qmul, qinv, qrot, qarc, qaxis  # noqa: E402
sys.argv = _argv

FPS_OUT = 60.0
# MediaPipe-Punkte
NOSE, EAR_L, EAR_R = 0, 7, 8
SH = {"l": 11, "r": 12}
EL = {"l": 13, "r": 14}
WR = {"l": 15, "r": 16}
PINKY = {"l": 17, "r": 18}
INDEX = {"l": 19, "r": 20}
HIP = {"l": 23, "r": 24}
KN = {"l": 25, "r": 26}
AN = {"l": 27, "r": 28}
HEEL = {"l": 29, "r": 30}
TOE = {"l": 31, "r": 32}


def nrm(v):
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else v


def frame_q(x, y):
    """Drehung aus seitlicher Achse x und Hochachse y (z = hinten)."""
    x = nrm(x)
    y = nrm(y - x * (x @ y))
    z = np.cross(x, y)
    m = np.stack([x, y, z], axis=1)
    # Matrix -> Quaternion [w, x, y, z]
    t = np.trace(m)
    if t > 0:
        s = math.sqrt(t + 1.0) * 2
        q = [0.25 * s, (m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = [(m[2, 1] - m[1, 2]) / s, 0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s]
    elif m[1, 1] > m[2, 2]:
        s = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = [(m[0, 2] - m[2, 0]) / s, (m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s]
    else:
        s = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = [(m[1, 0] - m[0, 1]) / s, (m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s]
    return nrm(np.array(q))


def rest_dir(j):
    if j.startswith("wr_"):
        return np.array([0.0, -1.0, 0.0])
    if j.startswith("an_"):
        return np.array([0.0, 0.0, -1.0])
    return nrm(np.array(REST[CHILD[j]]) - np.array(REST[j]))


def limb(gp, j, d, hinge=None):
    """Weltdrehung eines Gliedes: vom Elterngelenk aus geschwenkt, optional um die eigene Achse
    gedreht, damit die lokale x-Achse (Beugeachse des naechsten Gelenks) auf hinge zeigt."""
    r = qrot(gp, rest_dir(j))
    g = qmul(qarc(r, d), gp)
    if hinge is not None and np.linalg.norm(hinge) > 1e-3:
        x_now = qrot(g, [1.0, 0, 0])
        h = nrm(hinge - d * (hinge @ d))
        xn = nrm(x_now - d * (x_now @ d))
        ang = math.atan2(float(np.cross(xn, h) @ d), float(xn @ h))
        g = qmul(qaxis(d, ang), g)
    return g


def smooth(P, sigma):
    if sigma <= 0:
        return P
    r = int(3 * sigma)
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    pad = np.concatenate([np.repeat(P[:1], r, 0), P, np.repeat(P[-1:], r, 0)])
    out = np.zeros_like(P)
    for i, w in enumerate(k):
        out += w * pad[i:i + len(P)]
    return out


ARM_L, ARM_R = [11, 13, 15, 17, 19, 21], [12, 14, 16, 18, 20, 22]
LEG_L, LEG_R = [23, 25, 27, 29, 31], [24, 26, 28, 30, 32]


def fix_swaps(P):
    """MediaPipe vertauscht bei verdeckten Gliedern manchmal links und rechts fuer einzelne Bilder.
    Je Bild und Glied (Arm, Bein) wird die Zuordnung genommen, die naeher am Vorbild liegt."""
    P = P.copy()
    for a, b in [(ARM_L, ARM_R), (LEG_L, LEG_R)]:
        ends = [a[1], a[2]] if len(a) == 6 else [a[1], a[2]]
        ende = [b[1], b[2]]
        for i in range(1, len(P)):
            keep = np.linalg.norm(P[i, ends] - P[i - 1, ends]) + np.linalg.norm(P[i, ende] - P[i - 1, ende])
            swap = np.linalg.norm(P[i, ende] - P[i - 1, ends]) + np.linalg.norm(P[i, ends] - P[i - 1, ende])
            if swap < 0.6 * keep:
                P[i, a + b] = P[i, b + a]
    return P


def convert(path, t0=0.0, t1=1e9, sigma=1.5, yaw_s=0.35):
    d = json.load(open(path))
    F = [f for f in d["frames"] if "world" in f and t0 <= f["t"] <= t1]
    T = np.array([f["t"] for f in F])
    # MediaPipe: x rechts, y unten, z von der Kamera weg -> Spiel: y oben, z zur Kamera
    P = np.array([f["world"] for f in F]) * np.array([1.0, -1.0, -1.0])
    P = fix_swaps(P)
    P = smooth(P, sigma)
    # Blickrichtung je Bild (aus der Hueftlinie), langsam geglaettet
    lat = P[:, HIP["r"]] - P[:, HIP["l"]]
    yaw = np.unwrap(np.arctan2(-lat[:, 2], lat[:, 0]))  # Drehung der seitlichen Achse um y
    yaw_sm = smooth(yaw[:, None], yaw_s * d["fps"])[:, 0]
    frames = []
    n_out = int((T[-1] - T[0]) * FPS_OUT) + 1
    for k in range(n_out):
        t = T[0] + k / FPS_OUT
        i = min(int(np.searchsorted(T, t, side="right")) - 1, len(T) - 2)
        i = max(i, 0)
        w = (t - T[i]) / max(T[i + 1] - T[i], 1e-6)
        p = P[i] * (1 - w) + P[i + 1] * w
        yw = yaw_sm[i] * (1 - w) + yaw_sm[i + 1] * w
        Y = qaxis([0, 1, 0], -yw)
        p = np.array([qrot(Y, v) for v in p])
        mh = (p[HIP["l"]] + p[HIP["r"]]) / 2
        ms = (p[SH["l"]] + p[SH["r"]]) / 2
        G = {}
        G["hips"] = frame_q(p[HIP["r"]] - p[HIP["l"]], ms - mh)
        G["chest"] = frame_q(p[SH["r"]] - p[SH["l"]], ms - mh)
        head_up = (p[EAR_L] + p[EAR_R]) / 2 - ms
        G["head"] = qmul(qarc(qrot(G["chest"], [0, 1.0, 0]), nrm(head_up)), G["chest"])
        for sd in "lr":
            up_arm = nrm(p[EL[sd]] - p[SH[sd]])
            fore = nrm(p[WR[sd]] - p[EL[sd]])
            thigh = nrm(p[KN[sd]] - p[HIP[sd]])
            shin = nrm(p[AN[sd]] - p[KN[sd]])
            # Beugeachsen: Ellbogen und Knie beugen um die Normale der Ebene beider Glieder
            # (Vorzeichen so, dass sie zur seitlichen Achse des Elternteils passt)
            ha = np.cross(up_arm, fore)
            hk = np.cross(thigh, shin)
            xc = qrot(G["chest"], [1.0, 0, 0])
            xh = qrot(G["hips"], [1.0, 0, 0])
            if np.linalg.norm(ha) > 0.15:
                ha = ha if ha @ xc >= 0 else -ha
            else:
                ha = None
            hk = (hk if hk @ xh <= 0 else -hk) if np.linalg.norm(hk) > 0.15 else None
            G["sh_" + sd] = limb(G["chest"], "sh_" + sd, up_arm, ha)
            G["el_" + sd] = limb(G["sh_" + sd], "el_" + sd, fore)
            hand = nrm((p[INDEX[sd]] + p[PINKY[sd]]) / 2 - p[WR[sd]])
            G["wr_" + sd] = limb(G["el_" + sd], "wr_" + sd, hand)
            G["hip_" + sd] = limb(G["hips"], "hip_" + sd, thigh, hk)
            G["kn_" + sd] = limb(G["hip_" + sd], "kn_" + sd, shin)
            foot = nrm(p[TOE[sd]] - p[HEEL[sd]])
            G["an_" + sd] = limb(G["kn_" + sd], "an_" + sd, foot)
        fr = {}
        for gj in ORDER:
            par = PARENT[gj]
            L = G[gj] if par is None else qmul(qinv(G[par]), G[gj])
            if L[0] < 0:
                L = -L
            fr[gj] = [round(float(L[1]), 5), round(float(L[2]), 5), round(float(L[3]), 5), round(float(L[0]), 5)]
        frames.append(fr)
    return {"fps": FPS_OUT, "frames": frames, "ev": {}, "src": d.get("src", "")}


if __name__ == "__main__":
    a = sys.argv
    t0 = float(a[4]) if len(a) > 4 else 0.0
    t1 = float(a[5]) if len(a) > 5 else 1e9
    sg = float(a[6]) if len(a) > 6 else 1.5
    ys = float(a[7]) if len(a) > 7 else 0.35
    c = convert(a[1], t0, t1, sg, ys)
    json.dump({a[3]: c}, open(a[2], "w"), separators=(",", ":"))
    print(a[3], len(c["frames"]), "Bilder")
