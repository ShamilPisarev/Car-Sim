"""Original action music for the 30 s trailer, synthesised from scratch (no samples, no licence
needed). 140 bpm, A minor: riser under the title, drums + driving bass + saw stabs from the
start lights, a hit and a slow-motion breakdown on the crash, a final boom on the end card.

python tools/make_music.py out.wav [length_seconds]
"""
import sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter

SR = 48000
BPM = 140.0
BEAT = 60.0 / BPM
out_path = sys.argv[1]
LEN = float(sys.argv[2]) if len(sys.argv) > 2 else 28.4

# timeline of the trailer (seconds)
T_DROP = 1.6       # start lights: the beat comes in
T_CRASH = 19.7     # slow-motion crash: hit, then a breakdown
T_BACK = 21.9      # replay: full beat again
T_END = 25.7       # end card: final boom

n = int(LEN * SR)
mix = np.zeros((n, 2))
rng = np.random.default_rng(3)


def t_arr(dur):
    return np.arange(int(dur * SR)) / SR


def add(sig, at, gain=1.0, pan=0.0):
    i = int(at * SR)
    if i >= n:
        return
    sig = sig[: n - i]
    l = gain * np.cos((pan + 1) * np.pi / 4)
    r = gain * np.sin((pan + 1) * np.pi / 4)
    if sig.ndim == 1:
        mix[i:i + len(sig), 0] += sig * l * 1.414
        mix[i:i + len(sig), 1] += sig * r * 1.414
    else:
        mix[i:i + len(sig)] += sig * gain


def lp(x, f, order=2):
    b, a = butter(order, min(f / (SR / 2), 0.99), "low")
    return lfilter(b, a, x)


def hp(x, f, order=2):
    b, a = butter(order, min(f / (SR / 2), 0.99), "high")
    return lfilter(b, a, x)


def kick():
    t = t_arr(0.45)
    f = 45 + 110 * np.exp(-t * 28)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t * 7)
    click = rng.standard_normal(len(t)) * np.exp(-t * 400) * 0.3
    return np.tanh((body + click) * 2.2) * 0.9


def snare():
    t = t_arr(0.3)
    tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 25) * 0.5
    noise = hp(rng.standard_normal(len(t)), 1500) * np.exp(-t * 16) * 0.7
    return np.tanh((tone + noise) * 1.5) * 0.7


def hat(open_=False):
    t = t_arr(0.25 if open_ else 0.06)
    x = hp(rng.standard_normal(len(t)), 7000) * np.exp(-t * (14 if open_ else 70))
    return x * 0.25


def saw(freq, dur, detune=0.007, cutoff=2500, env_decay=6.0):
    t = t_arr(dur)
    x = np.zeros(len(t))
    for d in (-detune, 0.0, detune):
        f = freq * (1 + d)
        x += 2 * ((t * f) % 1.0) - 1
    x /= 3
    x = lp(x, cutoff)
    env = np.minimum(t / 0.005, 1) * np.exp(-t * env_decay)
    return x * env


def bass_note(freq, dur):
    t = t_arr(dur)
    x = 2 * ((t * freq) % 1.0) - 1
    dark = lp(x, 450)
    x = dark + (lp(x, 1600) - dark) * np.exp(-t * 18)     # a bright pluck that closes quickly
    x += np.sin(2 * np.pi * freq * t) * 0.6
    env = np.minimum(t / 0.004, 1) * np.exp(-t * 3.0)
    return np.tanh(x * env * 1.8) * 0.55


def boom(dur=2.5):
    t = t_arr(dur)
    f = 30 + 70 * np.exp(-t * 6)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t * 1.6)
    noise = lp(rng.standard_normal(len(t)), 900) * np.exp(-t * 5) * 0.6
    return np.tanh((body + noise) * 2.0) * 0.95


def riser(dur):
    t = t_arr(dur)
    noise = rng.standard_normal(len(t))
    out = np.zeros(len(t))
    # sweep a band of noise upwards, louder towards the end
    blocks = 40
    for k in range(blocks):
        a, b = k * len(t) // blocks, (k + 1) * len(t) // blocks
        f = 300 + 6000 * (k / blocks) ** 2
        seg = hp(lp(noise[max(0, a - 2000):b], f * 1.6), f * 0.6)[-(b - a):]
        out[a:b] = seg
    tone = np.sin(2 * np.pi * np.cumsum(110 + 330 * (t / dur) ** 2) / SR) * 0.25
    return (out * 0.35 + tone) * (t / dur) ** 1.5


# A minor: Am - F - C - G, one chord per bar
ROOTS = [55.0, 43.65, 65.41, 49.0]                 # A1 F1 C2 G1
CHORDS = [[220.0, 261.63, 329.63], [174.61, 220.0, 261.63], [261.63, 329.63, 392.0], [196.0, 246.94, 293.66]]
BAR = 4 * BEAT

# --- intro riser into the drop
add(riser(T_DROP), 0.0, 0.7)
add(boom(1.5), T_DROP, 0.8)


def section(t0, t1, full=True):
    step = BEAT / 4                                  # 16th notes
    k = 0
    t = t0
    while t < t1 - 1e-6:
        beat_pos = k % 16
        bar_i = int((t - T_DROP) / BAR) % 4
        if beat_pos in (0, 8) or (full and beat_pos == 10):
            add(kick(), t, 0.95)
        if beat_pos in (4, 12):
            add(snare(), t, 0.8, 0.05)
        add(hat(open_=(beat_pos % 4 == 2)), t, 0.6 if beat_pos % 2 else 0.35, 0.3)
        if beat_pos % 2 == 0:
            f = ROOTS[bar_i] * (2 if beat_pos % 4 == 2 else 1)
            add(bass_note(f, step * 2), t, 0.75)
        if full and beat_pos in (0, 3, 6, 10, 12):
            for j, cf in enumerate(CHORDS[bar_i]):
                add(saw(cf, step * 1.8, cutoff=3200), t, 0.11, -0.4 + 0.4 * j)
        t += step
        k += 1


section(T_DROP, T_CRASH)
# crash: a big hit, the beat drops out, a slow sub pulse and a riser back in
add(boom(2.2), T_CRASH, 1.0)
for i in range(4):
    add(bass_note(ROOTS[0], BEAT * 0.9), T_CRASH + 0.5 + i * BEAT, 0.5)
add(riser(T_BACK - T_CRASH - 0.3), T_CRASH + 0.3, 0.5)
section(T_BACK, T_END)
# end card: final boom and a held chord fading out
add(boom(2.8), T_END, 1.0)
for j, cf in enumerate(CHORDS[0]):
    add(saw(cf, LEN - T_END, cutoff=1800, env_decay=1.2), T_END, 0.12, -0.4 + 0.4 * j)

# master: gentle glue compression, fade, normalise to -1 dBFS
mix = np.tanh(mix * 1.2) / np.tanh(1.2)
fade = np.ones(n)
fade[-int(0.6 * SR):] = np.linspace(1, 0, int(0.6 * SR))
mix *= fade[:, None]
mix *= 0.89 / np.max(np.abs(mix))
wavfile.write(out_path, SR, (mix * 32767).astype(np.int16))
print("music", out_path, LEN, "s")
