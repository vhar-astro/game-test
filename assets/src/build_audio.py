"""Original synthesized score and effects, reproducible with Python's standard library."""
from pathlib import Path
import math
import random
import wave
import struct

OUT = Path(__file__).resolve().parents[1] / "audio"
OUT.mkdir(exist_ok=True)
RATE = 22050
random.seed(118)


def save(name, samples):
    with wave.open(str(OUT / (name + ".wav")), "wb") as out:
        out.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        out.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32760)) for s in samples))


def ambient(name, notes, pulse):
    duration = 16
    samples = []
    for i in range(RATE * duration):
        t = i / RATE
        # Integer periods across the full loop avoid clicks at wraparound.
        value = 0
        for n, freq in enumerate(notes):
            freq = round(freq * duration) / duration
            breath = .65 + .25 * math.sin(math.tau * t / duration + n)
            value += math.sin(math.tau * freq * t + .15 * math.sin(math.tau*t/duration)) * .085 * breath
            value += math.sin(math.tau * freq * 2 * t) * .012
        if pulse:
            envelope = max(0, math.sin(math.tau * t * pulse)) ** 12
            value += math.sin(math.tau * 55 * t) * .13 * envelope
        samples.append(value)
    save(name, samples)


ambient("explore", [110, 164.8125, 220, 277.1875], 0)
ambient("puzzle", [220, 329.625, 440, 554.375], .5)
ambient("alert", [55, 82.375, 116.5625], 2)
ambient("boss", [55, 61.75, 110], 4)

for name, duration, start, end, noise in [
    ("step",.11,105,60,.35),("jump",.28,160,290,.04),("land",.23,100,40,.3),
    ("rotate",.22,560,310,.03),("blade",.28,390,80,.16),("hit",.20,180,45,.32),
    ("puzzle",1.1,330,660,0),("defeat",.75,170,35,.13),
    ("artifact",1.2,220,880,0),("crystal",1.8,330,990,0),
    ("resonance",1.15,120,620,.03),("portal",1.4,60,240,.05),
    ("ui",.07,660,880,0),("ship",2.0,50,60,.03),
]:
    samples = []
    phase = 0
    for i in range(int(RATE * duration)):
        t = i / RATE
        frac = t / duration
        freq = start + (end - start) * frac
        phase += math.tau * freq / RATE
        envelope = min(1, t / .015) * (1-frac)**1.8
        value = (math.sin(phase) * .26 + math.sin(phase*1.5)*.10 + random.uniform(-1,1)*noise) * envelope
        samples.append(value)
    save(name, samples)
print("AUDIO_OK")
