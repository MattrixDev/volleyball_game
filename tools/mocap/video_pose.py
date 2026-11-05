"""Gelenke aus einem Volleyball-Video lesen (MediaPipe Pose, Apache 2.0).

Aufruf:  python3 video_pose.py <video.mp4> <modell.task> <ausgabe.json> [von_s] [bis_s] [overlay.mp4]

Pro Bild: 33 Bildpunkte (x, y in 0..1, Sichtbarkeit) und 33 Weltpunkte (Meter, Ursprung zwischen
den Hueften, MediaPipe-Achsen: x rechts im Bild, y nach unten, z zur Kamera hin negativ).
Mit overlay.mp4 wird das Video mit eingezeichneter Strichfigur ausgegeben (zum Pruefen).
Nur Videos mit freier Lizenz verwenden (z. B. Pexels); das Video selbst kommt nicht ins Spiel.
"""
import json
import sys

import cv2
import mediapipe as mp
from mediapipe.tasks import python as mpt
from mediapipe.tasks.python import vision

BONES = [(11, 12), (11, 13), (13, 15), (12, 14), (14, 16), (11, 23), (12, 24), (23, 24),
         (23, 25), (25, 27), (27, 31), (24, 26), (26, 28), (28, 32), (0, 11), (0, 12)]


def main() -> None:
    a = sys.argv
    video, model, out = a[1], a[2], a[3]
    t0 = float(a[4]) if len(a) > 4 else 0.0
    t1 = float(a[5]) if len(a) > 5 else 1e9
    ov = a[6] if len(a) > 6 else ""
    opts = vision.PoseLandmarkerOptions(
        base_options=mpt.BaseOptions(model_asset_path=model),
        running_mode=vision.RunningMode.VIDEO, num_poses=1,
        min_pose_detection_confidence=0.5, min_tracking_confidence=0.5)
    det = vision.PoseLandmarker.create_from_options(opts)
    cap = cv2.VideoCapture(video)
    fps = cap.get(cv2.CAP_PROP_FPS)
    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    wr = None
    if ov:
        wr = cv2.VideoWriter(ov, cv2.VideoWriter_fourcc(*"mp4v"), fps, (w // 2, h // 2))
    frames = []
    i = 0
    while True:
        ok, img = cap.read()
        if not ok:
            break
        t = i / fps
        i += 1
        if t < t0 or t > t1:
            continue
        rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        res = det.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb), int(t * 1000))
        fr = {"t": round(t - t0, 4)}
        if res.pose_landmarks:
            lm = res.pose_landmarks[0]
            wl = res.pose_world_landmarks[0]
            fr["img"] = [[round(p.x, 4), round(p.y, 4), round(p.visibility, 3)] for p in lm]
            fr["world"] = [[round(p.x, 4), round(p.y, 4), round(p.z, 4)] for p in wl]
            if wr is not None:
                for b0, b1 in BONES:
                    p0 = (int(lm[b0].x * w), int(lm[b0].y * h))
                    p1 = (int(lm[b1].x * w), int(lm[b1].y * h))
                    cv2.line(img, p0, p1, (0, 255, 255), 4)
        if wr is not None:
            wr.write(cv2.resize(img, (w // 2, h // 2)))
        frames.append(fr)
    if wr is not None:
        wr.release()
    json.dump({"fps": fps, "size": [w, h], "src": video.split("/")[-1], "frames": frames}, open(out, "w"))
    print(len(frames), "Bilder,", sum(1 for f in frames if "world" in f), "mit Person")


if __name__ == "__main__":
    main()
