"""Synthesises Consigliere's interface sounds as small WAV files. No samples, no downloads: every sound is
a few sine waves with a soft attack and a natural decay, so they are glassy and quiet rather than beepy.

Writes App/Consigliere/Resources/sounds/<name>.wav. The phone prototype plays these same files, so what you
hear on the phone is exactly what ships on the Mac.
"""
import math, pathlib, struct, wave

RATE = 44100
OUT = pathlib.Path(__file__).resolve().parent.parent / 'App' / 'Consigliere' / 'Resources' / 'sounds'

def voice(length, start, f0, f1, tau, amp, partials=((1, 1.0),), glide=None):
    """One decaying tone. f0 -> f1 is a pitch glide over `glide` seconds (default: the whole tone)."""
    n = int(length * RATE)
    out = [0.0] * n
    glide = glide or length
    phase = [0.0] * len(partials)
    for i in range(n):
        t = i / RATE
        if t < start: continue
        u = t - start
        k = min(1.0, u / glide)
        f = f0 + (f1 - f0) * (1 - (1 - k) * (1 - k))        # ease-out glide
        env = (1 - math.exp(-u / 0.003)) * math.exp(-u / tau)
        s = 0.0
        for p, (mult, a) in enumerate(partials):
            phase[p] += 2 * math.pi * f * mult / RATE
            s += a * math.sin(phase[p])
        out[i] = amp * env * s
    return out

def mix(*layers):
    n = max(len(l) for l in layers)
    return [sum(l[i] for l in layers if i < len(l)) for i in range(n)]

def write(name, samples):
    n = len(samples)
    fade = int(0.012 * RATE)
    for i in range(min(fade, n)):                          # never end on a click
        samples[n - 1 - i] *= i / fade
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = min(1.0, 0.5 / peak)                           # keep every sound at or under -6 dBFS
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f'{name}.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, s * scale)) * 32767)) for s in samples))
    print(f'{name:8s} {n / RATE * 1000:5.0f} ms')

BELL = ((1, 1.0), (2.76, 0.32), (5.4, 0.12))
SOFT = ((1, 1.0), (2, 0.18))

write('open',   voice(0.16, 0, 1046.5, 1568.0, 0.045, 0.30, SOFT, glide=0.05))
write('close',  voice(0.14, 0, 1318.5, 880.0, 0.040, 0.24, SOFT, glide=0.05))
write('save',   voice(0.24, 0, 440.0, 150.0, 0.070, 0.42, ((1, 1.0), (2, 0.3)), glide=0.14))
write('pull',   mix(voice(0.26, 0, 659.3, 987.8, 0.060, 0.30, SOFT, glide=0.06),
                    voice(0.26, 0.07, 1318.5, 1318.5, 0.070, 0.18, SOFT)))
write('nope',   voice(0.20, 0, 165.0, 150.0, 0.050, 0.45, ((1, 1.0), (1.5, 0.4))))
write('answer', voice(0.12, 0, 880.0, 932.3, 0.025, 0.24, SOFT))
write('lock',   mix(voice(0.60, 0, 1318.5, 1318.5, 0.20, 0.30, BELL),
                    voice(0.60, 0.05, 1975.5, 1975.5, 0.16, 0.16, BELL)))
write('done',   mix(voice(1.00, 0.00, 1046.5, 1046.5, 0.24, 0.28, BELL),
                    voice(1.00, 0.12, 1318.5, 1318.5, 0.24, 0.28, BELL),
                    voice(1.00, 0.24, 1568.0, 1568.0, 0.30, 0.30, BELL)))
