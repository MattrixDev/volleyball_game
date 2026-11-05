#!/usr/bin/env python3
"""Bildbogen und Video je gefilmter Stelle: python3 tools/lab/sheet.py ordner [bilder_pro_bogen=8]
Legt je Stelle sNN_bogen.jpg (Nahkameras, Zeitfolge) und sNN.mp4 (Spielkamera + Nahkameras, halbe Geschwindigkeit) an."""
import sys, os, glob, re, subprocess
from PIL import Image
d = sys.argv[1]
per = int(sys.argv[2]) if len(sys.argv) > 2 else 8
shots = sorted({re.match(r"(s\d+)_", os.path.basename(f)).group(1) for f in glob.glob(f"{d}/s*_main.jpg")})
for s in shots:
    frames = sorted({int(re.search(r"_(\d+)_main", f).group(1)) for f in glob.glob(f"{d}/{s}_*_main.jpg")})
    if not frames:
        continue
    # Video: oben Spielkamera, unten Seite + vorn
    tmp = f"{d}/_{s}"
    os.makedirs(tmp, exist_ok=True)
    for i, fr in enumerate(frames):
        m = Image.open(f"{d}/{s}_{fr:04d}_main.jpg")
        a = Image.open(f"{d}/{s}_{fr:04d}_side.jpg")
        b = Image.open(f"{d}/{s}_{fr:04d}_front.jpg")
        w = a.width + b.width
        mh = int(m.height * w / m.width)
        c = Image.new("RGB", (w, mh + a.height))
        c.paste(m.resize((w, mh)), (0, 0))
        c.paste(a, (0, mh))
        c.paste(b, (a.width, mh))
        c.save(f"{tmp}/{i:04d}.jpg", quality=88)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-framerate", "15", "-i", f"{tmp}/%04d.jpg", "-pix_fmt", "yuv420p",
                    "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", "-c:v", "libx264", "-crf", "23", f"{d}/{s}.mp4"], check=True)
    for f in glob.glob(f"{tmp}/*.jpg"):
        os.remove(f)
    os.rmdir(tmp)
    # Bogen: 2 Reihen (Seite, vorn) x per Bilder
    pick = [frames[round(i * (len(frames) - 1) / max(per - 1, 1))] for i in range(per)]
    tw = 270
    sheet = Image.new("RGB", (tw * per, tw * 2), "black")
    for i, fr in enumerate(pick):
        for r, cam in enumerate(["side", "front"]):
            im = Image.open(f"{d}/{s}_{fr:04d}_{cam}.jpg").resize((tw, tw))
            sheet.paste(im, (i * tw, r * tw))
    sheet.save(f"{d}/{s}_bogen.jpg", quality=90)
    print(f"{s}: {len(frames)} Bilder -> {s}.mp4, {s}_bogen.jpg")
