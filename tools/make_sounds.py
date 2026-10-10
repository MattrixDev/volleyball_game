#!/usr/bin/env python3
"""Offline sound generator for the volleyball game.

Synthesizes all sound effects (referee whistle, ball contacts, net, shoe
squeaks, crowd) with physically inspired DSP and writes 16-bit mono WAVs
(44.1 kHz) to assets/sounds/. Deterministic: every sound uses a fixed seed.

Usage:  python3 tools/make_sounds.py
"""

import os
import zlib

import numpy as np
from scipy import signal
from scipy.io import wavfile
from scipy.ndimage import uniform_filter1d

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sounds")


# ---------------------------------------------------------------------------
# Basic helpers
# ---------------------------------------------------------------------------

def rng_for(name):
    """Stable per-sound random generator."""
    return np.random.default_rng(zlib.crc32(name.encode()) + 7)


def secs(s):
    return int(round(s * SR))


def tvec(n):
    return np.arange(n) / SR


def bandpass(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, min(hi, SR * 0.45)], btype="band", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lowpass(x, fc, order=2):
    sos = signal.butter(order, min(fc, SR * 0.45), btype="low", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def highpass(x, fc, order=2):
    sos = signal.butter(order, fc, btype="high", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def resonator(x, f, bw):
    """Klatt two-pole resonator with unity DC gain."""
    T = 1.0 / SR
    c = -np.exp(-2 * np.pi * bw * T)
    b = 2 * np.exp(-np.pi * bw * T) * np.cos(2 * np.pi * f * T)
    a = 1 - b - c
    return signal.lfilter([a], [1, -b, -c], x)


def smooth_noise(rng, n, fc):
    """Slowly varying random curve, roughly unit RMS."""
    x = lowpass(rng.standard_normal(n), fc, order=2)
    return x / (np.std(x) + 1e-12)


def place(dst, src, start):
    """Add src into dst at sample index start (clipped to dst)."""
    if start >= len(dst):
        return
    if start < 0:
        src = src[-start:]
        start = 0
    m = min(len(src), len(dst) - start)
    dst[start:start + m] += src[:m]


def fade(x, fin=0.001, fout=0.02):
    x = x.copy()
    ni, no = max(secs(fin), 1), max(secs(fout), 1)
    x[:ni] *= np.sin(0.5 * np.pi * np.linspace(0, 1, ni)) ** 2
    x[-no:] *= np.cos(0.5 * np.pi * np.linspace(0, 1, no)) ** 2
    return x


def normalize(x, peak_db):
    return x * (10 ** (peak_db / 20) / (np.max(np.abs(x)) + 1e-12))


def write(name, x):
    data = np.clip(np.round(x * 32767), -32768, 32767).astype(np.int16)
    wavfile.write(os.path.join(OUT_DIR, name + ".wav"), SR, data)
    print(f"{name + '.wav':24s} {len(x) / SR:5.2f} s  peak {20 * np.log10(np.max(np.abs(x)) + 1e-12):6.1f} dBFS")


# ---------------------------------------------------------------------------
# Hall reverb (one shared impulse response = one sports hall)
# ---------------------------------------------------------------------------

def make_hall_ir(rt60=1.5, length=2.4, seed=1):
    rng = np.random.default_rng(seed)
    n = secs(length)
    t = tvec(n)
    noise = rng.standard_normal(n)
    # Frequency dependent decay: lows ring longer, highs die faster (air + absorbers)
    low = lowpass(noise, 350, 4)
    high = highpass(noise, 4000, 4)
    mid = bandpass(noise, 350, 4000, 2)
    tail = (low * np.exp(-6.91 * t / (rt60 * 1.1))
            + mid * np.exp(-6.91 * t / rt60)
            + 0.7 * high * np.exp(-6.91 * t / (rt60 * 0.55)))
    # Diffuse tail starts after ~18 ms, builds up smoothly
    onset = np.clip((t - 0.018) / 0.06, 0, 1) ** 1.5
    tail *= onset
    tail = lowpass(tail, 9000)
    tail /= np.sqrt(np.sum(tail ** 2))
    # A few discrete early reflections (floor, side walls, ceiling, stands)
    er = np.zeros(n)
    for ms, g in [(6.5, 0.55), (11, 0.4), (17, -0.35), (23, 0.3), (31, -0.25),
                  (38, 0.22), (47, 0.18), (58, -0.15), (71, 0.12)]:
        er[secs(ms / 1000)] += g * rng.uniform(0.8, 1.1)
    er = lowpass(er, 6000)
    ir = tail + 0.35 * er / np.sqrt(np.sum(er ** 2))
    return ir / np.sqrt(np.sum(ir ** 2))


HALL_IR = make_hall_ir()


def hall(dry, total, wet, dry_gain=1.0):
    """Mix dry signal with the hall reverb, output length 'total' seconds."""
    n = secs(total)
    x = np.zeros(n)
    place(x, dry, 0)
    rev = signal.fftconvolve(highpass(x, 110), HALL_IR)[:n]
    return dry_gain * x + wet * rev


def finish(dry, total, wet, peak_db, fout=0.15, dry_gain=1.0):
    y = hall(dry, total, wet, dry_gain)
    return normalize(fade(y, 0.0005, fout), peak_db)


# ---------------------------------------------------------------------------
# Ball contacts: force pulse -> modal body + skin slap noise
# ---------------------------------------------------------------------------

def contact(rng, tc, modes, crack=0.0, crack_band=(1500, 8000), crack_tau=0.003,
            pad=0.0, pad_fc=1200, pad_tau=0.012, pop=0.0, length=0.35):
    """One impact. tc: contact time (short = brighter).
    modes: list of (freq, decay tau, amp) for ball/arm/hand body resonances."""
    n = secs(length)
    t = tvec(n)
    tc *= rng.uniform(0.9, 1.1)
    nc = max(secs(tc), 2)
    p = np.zeros(n)
    p[:nc] = np.sin(np.pi * np.arange(nc) / nc) ** 1.5
    p /= p.sum()
    # Modal body: impulse response of all modes, excited by the force pulse
    h = np.zeros(n)
    for f, tau, a in modes:
        f *= rng.uniform(0.95, 1.05)
        tau *= rng.uniform(0.85, 1.15)
        a *= rng.uniform(0.85, 1.15)
        h += a * np.exp(-t / tau) * np.sin(2 * np.pi * f * t + rng.uniform(0, 0.3))
    y = signal.fftconvolve(p, h)[:n]
    # Pressure "pop" of the deforming ball (derivative of force, smoothed)
    if pop:
        dp = np.diff(p, prepend=0.0)
        dp = lowpass(dp, 3000 / max(tc / 0.003, 1.0))
        y += pop * dp / (np.max(np.abs(dp)) + 1e-12)
    # Skin slap: very short band-passed noise burst
    if crack:
        env = np.exp(-t / (crack_tau * rng.uniform(0.85, 1.15)))
        env[:secs(0.0003)] *= np.linspace(0, 1, secs(0.0003))
        c = bandpass(rng.standard_normal(n), *crack_band) * env
        y += crack * c / (np.max(np.abs(c)) + 1e-12)
    # Padded flesh/leather rub: low-passed noise
    if pad:
        env = np.exp(-t / pad_tau) * np.clip(t / 0.002, 0, 1)
        c = lowpass(rng.standard_normal(n), pad_fc, 2) * env
        y += pad * c / (np.max(np.abs(c)) + 1e-12)
    return y


def ball_bump(rng):
    y = contact(rng, 0.010, [(165, 0.022, 1.0), (300, 0.016, 0.6), (560, 0.01, 0.3), (1050, 0.006, 0.12)],
                crack=0.08, crack_band=(1500, 5000), crack_tau=0.002,
                pad=0.35, pad_fc=900, pad_tau=0.015, pop=0.35)
    return lowpass(y, 3500)


def ball_set(rng):
    n = secs(0.35)
    y = np.zeros(n)
    gap = secs(rng.uniform(0.009, 0.018))
    for k, g in enumerate([1.0, rng.uniform(0.6, 0.85)]):
        c = contact(rng, 0.006, [(250, 0.012, 1.0), (520, 0.008, 0.5), (980, 0.005, 0.25)],
                    crack=0.25, crack_band=(1200, 5500), crack_tau=0.0018,
                    pad=0.3, pad_fc=1600, pad_tau=0.006, pop=0.3)
        place(y, g * c, k * gap)
    return y


def ball_spike(rng):
    y = contact(rng, 0.0025, [(150, 0.009, 1.3), (330, 0.008, 0.6), (820, 0.007, 0.35),
                              (1650, 0.008, 0.25), (2350, 0.02, 0.1), (3300, 0.004, 0.15)],
                crack=1.1, crack_band=(1200, 11000), crack_tau=0.0035,
                pad=0.25, pad_fc=1500, pad_tau=0.01, pop=0.9)
    return y


def ball_serve(rng):
    return contact(rng, 0.0045, [(160, 0.011, 1.2), (340, 0.009, 0.55), (760, 0.007, 0.3),
                                 (1500, 0.007, 0.18), (2350, 0.018, 0.07)],
                   crack=0.6, crack_band=(1200, 8000), crack_tau=0.003,
                   pad=0.3, pad_fc=1300, pad_tau=0.012, pop=0.6)


def ball_tip(rng):
    return contact(rng, 0.005, [(300, 0.009, 1.0), (650, 0.006, 0.45), (1300, 0.004, 0.2)],
                   crack=0.22, crack_band=(1500, 6000), crack_tau=0.0015,
                   pad=0.25, pad_fc=2000, pad_tau=0.005, pop=0.3, length=0.2)


def ball_block(rng):
    n = secs(0.4)
    y = np.zeros(n)
    # Two hands hit almost together (crack), ball rebounds off a second hand/finger
    for k in range(2):
        c = contact(rng, 0.003, [(180, 0.01, 1.2), (400, 0.008, 0.5), (900, 0.006, 0.3), (1800, 0.005, 0.2)],
                    crack=1.0, crack_band=(1200, 10000), crack_tau=0.003, pad=0.2, pop=0.8)
        place(y, c * (1.0 if k == 0 else 0.6), secs(rng.uniform(0.002, 0.006)) * k)
    c2 = contact(rng, 0.005, [(240, 0.016, 1.0), (500, 0.011, 0.4), (1000, 0.006, 0.2)],
                 crack=0.6, crack_band=(1000, 6000), crack_tau=0.0025, pad=0.3, pop=0.4)
    place(y, c2 * rng.uniform(0.3, 0.42), secs(rng.uniform(0.045, 0.08)))
    return y


def ball_floor(rng):
    n = secs(0.9)
    y = np.zeros(n)
    # Ball slaps the floor: short contact, strong pop + slap
    c = contact(rng, 0.0028, [(170, 0.01, 0.9), (360, 0.009, 0.45), (850, 0.007, 0.3),
                              (2350, 0.02, 0.12), (1700, 0.007, 0.2)],
                crack=1.0, crack_band=(1000, 10000), crack_tau=0.004, pad=0.15, pop=1.0, length=0.6)
    # Sprung wooden floor: low thump
    t = tvec(n)
    floor = np.zeros(n)
    for f, tau, a in [(68, 0.04, 1.0), (105, 0.028, 0.7), (190, 0.016, 0.35)]:
        f *= rng.uniform(0.94, 1.06)
        floor += a * np.exp(-t / tau) * np.sin(2 * np.pi * f * t)
    floor *= np.clip(t / 0.0015, 0, 1)
    place(y, c, 0)
    y += 0.9 * floor / np.max(np.abs(floor))
    # Much quieter second bounce later (ball came down from a high rebound)
    c2 = contact(rng, 0.004, [(170, 0.02, 0.8), (360, 0.015, 0.4), (850, 0.01, 0.2)],
                 crack=0.5, crack_band=(1000, 7000), pad=0.2, pop=0.6, length=0.3)
    place(y, 0.14 * c2, secs(rng.uniform(0.6, 0.7)))
    return y


# ---------------------------------------------------------------------------
# Net
# ---------------------------------------------------------------------------

def net_hit(rng):
    n = secs(0.75)
    t = tvec(n)
    y = np.zeros(n)
    # Ball sinks into the mesh: soft, damped thud
    thud = contact(rng, 0.016, [(150, 0.03, 1.0), (290, 0.02, 0.5), (600, 0.01, 0.2)],
                   pad=0.4, pad_fc=800, pad_tau=0.03, pop=0.2, length=0.3)
    place(y, 0.55 * lowpass(thud, 1500), 0)
    # Mesh rustle: many tiny rope/knot contacts (granular), net swings -> rattle
    grains = [bandpass(rng.standard_normal(secs(0.004)), fc / 1.6, fc * 1.6)
              * np.hanning(secs(0.004)) for fc in rng.uniform(1500, 7000, 24)]
    swing = rng.uniform(9, 15)
    lam = 900 * np.exp(-t / 0.13) * (1 + 0.85 * np.sin(2 * np.pi * swing * t)) * (t > 0.004)
    hits = np.nonzero(rng.random(n) < lam / SR)[0]
    rustle = np.zeros(n)
    for i in hits:
        place(rustle, grains[rng.integers(len(grains))] * rng.lognormal(0, 0.6), i)
    y += 0.35 * rustle / (np.max(np.abs(rustle)) + 1e-12)
    # Rope sliding swish
    sw = bandpass(rng.standard_normal(n), 400, 3500) * np.exp(-t / 0.09) * np.clip(t / 0.01, 0, 1)
    y += 0.12 * sw / np.max(np.abs(sw))
    # Top cable twang: stiff string, two polarizations beating
    f0 = rng.uniform(85, 110)
    tw = np.zeros(n)
    for k in range(1, 13):
        fk = k * f0 * np.sqrt(1 + 0.0008 * k * k)
        tau = 0.25 / (1 + 0.18 * k)
        for det in (0.0, 0.5):
            tw += (1 / k) * np.exp(-t / tau) * np.sin(2 * np.pi * (fk + det * k) * t + rng.uniform(0, 6.28))
    tw *= np.clip((t - 0.008) / 0.004, 0, 1)
    y += 0.16 * lowpass(tw, 2500) / np.max(np.abs(tw))
    # Faint metallic tick of the cable clamp
    tick = resonator(np.r_[np.zeros(secs(0.01)), 1.0, np.zeros(n)], rng.uniform(1100, 1500), 40)[:n]
    y += 0.08 * tick / np.max(np.abs(tick))
    return y


# ---------------------------------------------------------------------------
# Shoe squeak: rubber stick-slip -> harmonic chirp with jittery pitch
# ---------------------------------------------------------------------------

def squeak(rng, kind):
    d = rng.uniform(0.08, 0.2)
    n = secs(d)
    t = tvec(n)
    u = t / d
    f_a, f_b = rng.uniform(1000, 1600), rng.uniform(1900, 2900)
    if kind == 0:      # rising
        f = f_a + (f_b - f_a) * u ** 0.7
    elif kind == 1:    # falling
        f = f_b - (f_b - f_a) * u ** 1.3
    elif kind == 2:    # up then down
        f = f_a + (f_b - f_a) * np.sin(np.pi * u) ** 1.2
    else:              # mostly flat with a jump (chirp-chirp)
        f = f_a * 1.2 + (f_b - f_a * 1.2) * (u > 0.45) * 0.6
        f = uniform_filter1d(f, secs(0.01))
    f = f * (1 + 0.025 * smooth_noise(rng, n, 60)) * (1 + 0.015 * np.sin(2 * np.pi * rng.uniform(35, 70) * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.zeros(n)
    for k in range(1, 7):
        y += (k ** -1.3) * np.sin(k * ph + rng.uniform(0, 6.28)) * (k * f < 16000)
    y += 0.12 * bandpass(rng.standard_normal(n), 2000, 7000)
    env = (np.clip(t / rng.uniform(0.004, 0.009), 0, 1)
           * np.clip((d - t) / rng.uniform(0.02, 0.04), 0, 1)
           * np.clip(1 + 0.3 * smooth_noise(rng, n, 40), 0.3, 2))
    y = bandpass(y * env, 700, 10000)
    out = np.zeros(secs(d + 0.02))
    place(out, y, secs(0.01))
    return out


# ---------------------------------------------------------------------------
# Referee whistle (pealess, three chambers)
# ---------------------------------------------------------------------------

def whistle(rng, blast):
    n = secs(blast + 0.12)
    t = tvec(n)
    att, rel = 0.025, rng.uniform(0.05, 0.07)
    # Blowing pressure envelope: soft attack, sustain with small breath wobble, release
    a = np.clip(t / att, 0, 1)
    a = np.sin(0.5 * np.pi * a) ** 2
    r = np.clip(1 - (t - blast) / rel, 0, 1) ** 1.5
    press = a * r * (1 + 0.04 * smooth_noise(rng, n, 6))
    # Pitch: rises at onset, sags slightly during release (pressure drop)
    rise = 1 - 0.05 * np.exp(-t / 0.03)
    sag = 1 - 0.03 * (1 - r)
    y = np.zeros(n)
    base = np.array([2720.0, 3080.0, 3380.0]) * rng.uniform(0.985, 1.015)
    for f, amp in zip(base, [1.0, 0.8, 0.6]):
        fi = f * rise * sag * (1 + 0.003 * smooth_noise(rng, n, 25))
        ph = 2 * np.pi * np.cumsum(fi) / SR + rng.uniform(0, 6.28)
        tone = np.sin(ph) + 0.06 * np.sin(2 * ph) + 0.02 * np.sin(3 * ph)
        lock = np.clip((t - rng.uniform(0.003, 0.008)) / 0.02, 0, 1)  # chambers lock in at different times
        y += amp * tone * lock * (1 + 0.08 * smooth_noise(rng, n, 40))
    y *= press
    # Breath noise around the tones plus an onset "chiff"
    br = bandpass(rng.standard_normal(n), 2200, 4500, 2)
    chiff = np.exp(-np.maximum(t - 0.008, 0) / 0.015) * np.clip(t / 0.004, 0, 1)
    y += 0.12 * br * press + 0.25 * br * chiff * 0.5
    y += 0.05 * bandpass(rng.standard_normal(n), 600, 2000) * press
    return lowpass(y, 7000)


# ---------------------------------------------------------------------------
# Voices (crowd): Rosenberg glottal pulses -> cascade formant filters
# ---------------------------------------------------------------------------

VOWELS = {  # F1, F2, F3 (adult male), F4 fixed
    "a": (730, 1090, 2440), "e": (530, 1840, 2480), "i": (300, 2250, 3000),
    "o": (500, 830, 2400), "u": (320, 870, 2240), "ae": (660, 1700, 2410),
    "schwa": (500, 1500, 2500),
}
BANDW = (80, 100, 140, 220)


def glottal_source(rng, f0, tp=0.4, tn=0.16, breath=0.03):
    n = len(f0)
    f0 = f0 * (1 + 0.008 * smooth_noise(rng, n, 30))  # jitter
    ph = np.cumsum(f0) / SR % 1.0
    g = np.where(ph < tp, 0.5 * (1 - np.cos(np.pi * ph / tp)),
                 np.where(ph < tp + tn, np.cos(np.pi * (ph - tp) / (2 * tn)), 0.0))
    src = np.diff(g, prepend=0.0) * SR / 400.0      # lip radiation
    src += breath * rng.standard_normal(n) * (0.3 + g)
    return src


def formant(x, vowel, scale):
    f = list(VOWELS[vowel]) + [3400]
    y = x
    for fi, bw in zip(f, BANDW):
        y = resonator(y, fi * scale, bw * scale)
    return y


def render_voice(rng, f0, weights, env, scale, tp=0.4, tn=0.16, breath=0.03):
    """weights: dict vowel -> weight curve (same length as f0)."""
    src = glottal_source(rng, f0, tp, tn, breath)
    y = np.zeros(len(f0))
    for v, w in weights.items():
        if np.any(w > 1e-3):
            y += w * formant(src, v, scale)
    return y * env


def speaker(rng):
    female = rng.random() < 0.45
    f0 = rng.uniform(175, 245) if female else rng.uniform(90, 135)
    scale = (rng.uniform(1.12, 1.2) if female else 1.0) * rng.uniform(0.96, 1.04)
    return f0, scale


def distance(rng, y, near=0.35):
    """Random listener distance: level and air/absorption low-pass."""
    g = rng.uniform(near, 1.0)
    return lowpass(y, 2500 + 4000 * g) * g


def babble_voice(rng, n):
    f0b, scale = speaker(rng)
    names = ["a", "e", "i", "o", "u", "schwa"]
    label = np.full(n, 5)
    env = np.zeros(n)
    f0 = np.full(n, f0b)
    cons = np.zeros(n)
    cur = rng.uniform(-1.5, 0.5)
    while cur < n / SR:
        pdur = rng.uniform(1.0, 3.5)
        s = cur
        while s < cur + pdur:
            d = rng.uniform(0.11, 0.24)
            i0, i1 = secs(s), secs(s + d)
            if i1 > 0 and i0 < n:
                w = np.sin(np.pi * np.linspace(0, 1, i1 - i0)) ** 0.8 * rng.uniform(0.45, 1.0)
                a, b = max(i0, 0), min(i1, n)
                env[a:b] += w[a - i0:b - i0]
                label[a:b] = rng.integers(6)
                decl = 1.1 - 0.2 * (s - cur) / pdur
                f0[a:b] = f0b * decl * np.exp(rng.normal(0, 0.07))
                if rng.random() < 0.55:  # consonant before the vowel
                    if rng.random() < 0.5:
                        k = bandpass(rng.standard_normal(secs(0.06)), 3500, 8500) * np.hanning(secs(0.06)) * 0.12
                    else:
                        k = bandpass(rng.standard_normal(secs(0.012)), 900, 5000) * np.hanning(secs(0.012)) * 0.25
                    place(cons, k, i0 - len(k))
            s += d + rng.uniform(0.01, 0.06)
        cur += pdur + rng.uniform(0.3, 1.5)
    f0 = uniform_filter1d(f0, secs(0.04))
    env = uniform_filter1d(env, secs(0.01))
    sm = secs(0.03)
    weights = {v: uniform_filter1d((label == k).astype(float), sm) for k, v in enumerate(names)}
    return render_voice(rng, f0, weights, env, scale) + cons * np.max(np.abs(env))


def shout_voice(rng, n, t0, dur, vowel_path, f0_curve, peak_t=0.35, tp=0.36, tn=0.09, breath=0.04):
    """One crowd member shouting/groaning: vowel_path is [(vowel, fraction_of_dur)],
    f0_curve(u) gives the pitch factor over normalized time u in [0,1]."""
    f0b, scale = speaker(rng)
    f0b *= rng.uniform(1.3, 1.6) if tp < 0.4 else 1.0   # raised voice
    t = tvec(n)
    u = np.clip((t - t0) / dur, 0, 1)
    active = (t >= t0) & (t <= t0 + dur)
    env = np.where(u < peak_t * 0.4, np.sin(0.5 * np.pi * u / (peak_t * 0.4)) ** 2,
                   np.clip((1 - u) / (1 - peak_t * 0.4), 0, 1) ** 1.3) * active
    f0 = f0b * f0_curve(u) * np.exp(rng.normal(0, 0.05))
    weights = {}
    edges = np.cumsum([0] + [fr for _, fr in vowel_path])
    for (v, _), lo, hi in zip(vowel_path, edges[:-1], edges[1:]):
        weights[v] = weights.get(v, 0) + ((u >= lo) & (u < hi + (hi >= 1))).astype(float)
    weights = {v: uniform_filter1d(w, secs(0.04)) for v, w in weights.items()}
    y = render_voice(rng, f0, weights, env, scale, tp, tn, breath)
    return y / (np.max(np.abs(y)) + 1e-12)


def room_noise(rng, n):
    """Soft broadband hall noise (ventilation, shuffling), pinkish."""
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    spec /= np.sqrt(np.maximum(f, 20))
    x = lowpass(np.fft.irfft(spec, n), 4000)
    return x / np.std(x)


# ---------------------------------------------------------------------------
# Clapping
# ---------------------------------------------------------------------------

def clap_kernels(rng, k=3):
    """A few slightly different claps of one person (hand shape = spectrum)."""
    fc = rng.lognormal(np.log(1300), 0.35)
    bw = rng.uniform(0.7, 1.4)
    ks = []
    for _ in range(k):
        m = secs(0.03)
        t = tvec(m)
        e = np.exp(-t / rng.uniform(0.003, 0.007)) * np.clip(t / 0.0004, 0, 1)
        f = fc * rng.uniform(0.92, 1.08)
        c = bandpass(rng.standard_normal(m), f / 2 ** bw, f * 2 ** bw) * e
        c += 0.6 * resonator(c, f, f * 0.3)
        c = highpass(c, 300)
        ks.append(c / np.max(np.abs(c)))
    return ks


def clapping(rng, n, people, rate, start, stop, level_curve=None):
    out = np.zeros(n)
    for _ in range(people):
        ks = clap_kernels(rng)
        r = rng.uniform(*rate)
        s, e = rng.uniform(*start), rng.uniform(*stop)
        g = rng.uniform(0.35, 1.0)
        tc = s
        train = np.zeros(n)
        while tc < e:
            i = secs(tc)
            if i < n:
                amp = g * rng.uniform(0.75, 1.0)
                if level_curve is not None:
                    amp *= level_curve(tc)
                fade_out = np.clip((e - tc) / 0.4, 0.25, 1)
                place(train, ks[rng.integers(len(ks))] * amp * fade_out, i)
            tc += (1 / r) * rng.normal(1, 0.08)
        out += lowpass(train, 4000 + 5000 * g)
    return out


def finger_whistle(rng, n, t0):
    d = rng.uniform(0.3, 0.5)
    m = secs(d)
    t = tvec(m)
    u = t / d
    f = rng.uniform(2200, 2600) * (1 + 0.25 * np.sin(np.pi * np.clip(u * 1.3, 0, 1)))
    ph = 2 * np.pi * np.cumsum(f * (1 + 0.004 * smooth_noise(rng, m, 20))) / SR
    y = (np.sin(ph) + 0.03 * np.sin(2 * ph)) * np.sin(np.pi * u) ** 0.6
    y += 0.05 * bandpass(rng.standard_normal(m), 2000, 4000) * np.sin(np.pi * u)
    out = np.zeros(n)
    place(out, y, secs(t0))
    return out


# ---------------------------------------------------------------------------
# Crowd scenes
# ---------------------------------------------------------------------------

def crowd_murmur(rng, loop=10.0, xfade=1.0, pre=1.5, voices=48):
    total = pre + loop + xfade
    n = secs(total)
    y = np.zeros(n)
    for _ in range(voices):
        y += distance(rng, babble_voice(rng, n), near=0.45)
    y /= np.std(y)
    y = 3.0 * np.tanh(y / 3.0)  # tame single loud voices
    y += 0.25 * room_noise(rng, n)
    y = highpass(y, 80)
    w = hall(y, total, wet=1.0, dry_gain=0.45)
    seg = w[secs(pre):]
    L, X = secs(loop), secs(xfade)
    out = seg[:L].copy()
    ramp = np.linspace(0, 1, X)
    out[:X] = seg[:X] * np.sin(0.5 * np.pi * ramp) + seg[L:L + X] * np.cos(0.5 * np.pi * ramp)
    return out


def crowd_cheer(rng, length=3.5):
    n = secs(length)
    y = np.zeros(n)
    for _ in range(56):
        t0 = 0.03 + rng.gamma(2.0, 0.08)
        dur = rng.uniform(0.9, 2.3)
        r = rng.random()
        if r < 0.6:
            path = [("i", 0.05), ("e", 0.15), ("a", 0.8)]          # "yeah!"
        elif r < 0.8:
            path = [("u", 0.4), ("o", 0.6)]                        # "wooo"
        else:
            path = [("ae", 0.3), ("a", 0.7)]                       # "aaah"
        rise = rng.uniform(1.2, 1.5)
        curve = lambda u, rise=rise: 0.85 + (rise - 0.85) * np.minimum(u / 0.35, 1) - 0.12 * np.maximum(u - 0.6, 0)
        v = shout_voice(rng, n, t0, dur, path, curve, peak_t=rng.uniform(0.3, 0.6))
        y += distance(rng, v)
    y /= np.max(np.abs(y))
    level = lambda tt: np.clip(tt / 0.4, 0, 1) * np.exp(-max(tt - 0.8, 0) / 1.2)
    cl = clapping(rng, n, 40, (4.5, 6.5), (0.15, 0.5), (2.2, 3.3), level)
    y += 0.55 * cl / np.max(np.abs(cl))
    for _ in range(rng.integers(1, 3)):
        y += 0.12 * finger_whistle(rng, n, rng.uniform(0.5, 1.4))
    y += 0.03 * room_noise(rng, n)
    y = highpass(y, 90)
    return finish(y, length, wet=1.0, peak_db=-1.0, fout=0.5, dry_gain=0.55)


def crowd_groan(rng, length=2.0):
    n = secs(length)
    y = np.zeros(n)
    for _ in range(50):
        t0 = rng.uniform(0.0, 0.25)
        dur = rng.uniform(0.9, 1.5)
        path = [("o", 1.0)] if rng.random() < 0.8 else [("a", 0.3), ("o", 0.7)]   # "ohhh" / "aww"
        start = rng.uniform(1.15, 1.3)
        curve = lambda u, s=start: s - (s - 0.8) * u ** 0.8
        v = shout_voice(rng, n, t0, dur, path, curve, peak_t=rng.uniform(0.2, 0.4),
                        tp=0.42, tn=0.2, breath=0.07)
        y += distance(rng, v)
    y /= np.max(np.abs(y))
    y += 0.03 * room_noise(rng, n)
    y = highpass(y, 80)
    return finish(y, length, wet=1.0, peak_db=-1.0, fout=0.4, dry_gain=0.55)


def crowd_applause(rng, length=2.5):
    n = secs(length)
    y = clapping(rng, n, 26, (2.6, 4.0), (0.0, 0.25), (1.4, 2.2))
    y /= np.max(np.abs(y))
    y += 0.02 * room_noise(rng, n)
    return finish(y, length, wet=0.9, peak_db=-1.0, fout=0.4, dry_gain=0.65)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# (generator, file length s, reverb wet, peak dBFS): spike loudest, set/tip softer
HITS = {
    "bump":  (ball_bump, 0.9, 0.40, -3.0),
    "set":   (ball_set, 0.8, 0.40, -6.0),
    "spike": (ball_spike, 1.0, 0.38, -1.0),
    "serve": (ball_serve, 0.9, 0.38, -2.0),
    "tip":   (ball_tip, 0.7, 0.40, -9.0),
    "block": (ball_block, 1.0, 0.38, -1.5),
    "floor": (ball_floor, 1.5, 0.60, -1.0),
}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    for name, blast, length in [("whistle_short", 0.3, 0.9), ("whistle_long", 0.7, 1.3)]:
        write(name, finish(whistle(rng_for(name), blast), length, wet=0.5, peak_db=-7.0, fout=0.2))

    for base, (gen, length, wet, peak) in HITS.items():
        for v in (1, 2, 3):
            name = f"{base}_{v}"
            dry = np.r_[np.zeros(secs(0.002)), gen(rng_for(name))]
            write(name, finish(dry, length, wet, peak))

    for v in (1, 2):
        name = f"net_{v}"
        write(name, finish(net_hit(rng_for(name)), 1.0, 0.45, -2.0, fout=0.25))

    for v in range(1, 5):
        name = f"squeak_{v}"
        write(name, finish(squeak(rng_for(name), v - 1), 0.6, 0.3, -8.0, fout=0.2))

    m = crowd_murmur(rng_for("crowd_murmur"))
    write("crowd_murmur", normalize(m, -6.0))

    for v in (1, 2):
        write(f"crowd_cheer_{v}", crowd_cheer(rng_for(f"crowd_cheer_{v}")))
        write(f"crowd_groan_{v}", crowd_groan(rng_for(f"crowd_groan_{v}")))
        write(f"crowd_applause_{v}", crowd_applause(rng_for(f"crowd_applause_{v}")))


if __name__ == "__main__":
    main()
