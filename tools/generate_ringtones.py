#!/usr/bin/env python3
"""Generate Stopwatch's original notification sounds using only math.

The output is deterministic 44.1 kHz, mono, 16-bit linear PCM WAV. No samples,
recordings, MIDI files, or third-party audio are used.
"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path


SAMPLE_RATE = 44_100
TAU = math.tau
PEAK_TARGET = 27_524 / 32_767
OUTPUT_DIRECTORY = Path(__file__).resolve().parents[1] / "Stopwatch" / "Sounds"


def envelope(time: float, duration: float, attack: float, release: float) -> float:
    if time < 0 or time >= duration:
        return 0.0
    attack_gain = min(time / max(attack, 1e-6), 1.0)
    release_gain = min((duration - time) / max(release, 1e-6), 1.0)
    return math.sin(attack_gain * math.pi / 2) * math.sin(release_gain * math.pi / 2)


def add_tone(
    samples: list[float],
    start: float,
    duration: float,
    frequency: float,
    amplitude: float,
    *,
    attack: float = 0.008,
    release: float = 0.12,
    decay: float = 1.8,
    partials: tuple[tuple[float, float], ...] = ((1.0, 1.0),),
    glide: float = 0.0,
    vibrato_depth: float = 0.0,
    vibrato_rate: float = 5.0,
) -> None:
    first = int(start * SAMPLE_RATE)
    count = int(duration * SAMPLE_RATE)
    phase = 0.0
    for offset in range(count):
        index = first + offset
        if index >= len(samples):
            break
        time = offset / SAMPLE_RATE
        progress = time / duration
        current_frequency = frequency * (1.0 + glide * progress)
        current_frequency *= 1.0 + vibrato_depth * math.sin(TAU * vibrato_rate * time)
        phase += TAU * current_frequency / SAMPLE_RATE
        color = sum(gain * math.sin(phase * multiplier) for multiplier, gain in partials)
        gain = envelope(time, duration, attack, release) * math.exp(-decay * time)
        samples[index] += amplitude * gain * color


def blank(duration: float) -> list[float]:
    return [0.0] * int(duration * SAMPLE_RATE)


def silver_bell() -> list[float]:
    result = blank(1.85)
    partials = ((1.0, 1.0), (2.01, 0.38), (3.92, 0.18), (5.43, 0.08))
    add_tone(result, 0.02, 1.72, 880.0, 0.48, release=0.35, decay=1.4, partials=partials)
    add_tone(result, 0.18, 1.48, 1_174.66, 0.28, release=0.32, decay=1.6, partials=partials)
    return result


def crystal() -> list[float]:
    result = blank(1.65)
    partials = ((1.0, 1.0), (2.0, 0.22), (3.0, 0.08))
    for start, frequency, amplitude in ((0.02, 1_318.51, 0.38), (0.19, 1_567.98, 0.34), (0.36, 2_093.00, 0.30)):
        add_tone(result, start, 1.12, frequency, amplitude, release=0.30, decay=2.2, partials=partials)
    return result


def breeze() -> list[float]:
    result = blank(2.25)
    partials = ((1.0, 1.0), (2.0, 0.08))
    for start, frequency, amplitude in ((0.02, 523.25, 0.28), (0.20, 659.25, 0.25), (0.40, 783.99, 0.23), (0.62, 1_046.50, 0.18)):
        add_tone(result, start, 1.35, frequency, amplitude, attack=0.06, release=0.48, decay=1.4, partials=partials, vibrato_depth=0.0015)
    return result


def sunrise() -> list[float]:
    result = blank(1.85)
    partials = ((1.0, 1.0), (2.0, 0.16), (3.0, 0.05))
    for start, frequency in ((0.02, 392.0), (0.19, 493.88), (0.36, 659.25), (0.54, 783.99)):
        add_tone(result, start, 0.90, frequency, 0.30, release=0.30, decay=2.1, partials=partials)
    return result


def moonlight() -> list[float]:
    result = blank(2.15)
    partials = ((1.0, 1.0), (2.0, 0.11))
    for frequency, amplitude in ((440.0, 0.27), (554.37, 0.22), (659.25, 0.18), (880.0, 0.10)):
        add_tone(result, 0.03, 1.98, frequency, amplitude, attack=0.12, release=0.58, decay=1.0, partials=partials, vibrato_depth=0.001)
    return result


def beacon() -> list[float]:
    result = blank(1.85)
    partials = ((1.0, 1.0), (2.0, 0.18))
    for start, frequency in ((0.03, 698.46), (0.27, 1_046.50), (0.78, 698.46), (1.02, 1_046.50)):
        add_tone(result, start, 0.42, frequency, 0.38, release=0.18, decay=2.8, partials=partials)
    return result


def sparkle() -> list[float]:
    result = blank(1.65)
    partials = ((1.0, 1.0), (2.0, 0.12), (3.01, 0.06))
    events = ((0.02, 1_567.98), (0.15, 2_093.00), (0.31, 1_760.00), (0.48, 2_637.02), (0.68, 2_093.00))
    for start, frequency in events:
        add_tone(result, start, 0.72, frequency, 0.26, attack=0.004, release=0.22, decay=3.2, partials=partials)
    return result


SOUNDS = {
    "silver-bell": silver_bell,
    "crystal": crystal,
    "breeze": breeze,
    "sunrise": sunrise,
    "moonlight": moonlight,
    "beacon": beacon,
    "sparkle": sparkle,
}


def write_wav(path: Path, samples: list[float]) -> None:
    # Normalise every ringtone to the same peak as the older hand-made set, so
    # no alarm sound arrives noticeably quieter than the one next to it in the
    # picker. (Clamping the scale at 1.0 used to leave the sparse sounds 4-5 dB
    # down, because their raw render never reached the target on its own.)
    peak = max(abs(sample) for sample in samples) or 1.0
    scale = PEAK_TARGET / peak
    # TPDF dither decorrelates the quantisation error from the signal, which
    # keeps the long decay tails smooth instead of granular.
    noise = random.Random(0x5709)
    pcm = b"".join(
        struct.pack(
            "<h",
            max(-32_768, min(32_767, round(
                max(-1.0, min(1.0, sample * scale)) * 32_767
                + noise.random() - noise.random()
            ))),
        )
        for sample in samples
    )
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(pcm)


def main() -> None:
    OUTPUT_DIRECTORY.mkdir(parents=True, exist_ok=True)
    for name, renderer in SOUNDS.items():
        destination = OUTPUT_DIRECTORY / f"{name}.wav"
        write_wav(destination, renderer())
        print(destination.relative_to(OUTPUT_DIRECTORY.parents[1]))


if __name__ == "__main__":
    main()
