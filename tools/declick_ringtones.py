#!/usr/bin/env python3
"""Remove the click/pop artefacts from Stopwatch's notification sounds.

Several of the ringtones gate their beeps on and off instantly: the waveform
jumps from digital silence straight to full amplitude and back again. Each of
those steps radiates a broadband click, which is audible at the start and end
of every beep, at the end of the file, and — because the alarm concatenates the
file 2-5 times for repeat playback — at every loop seam as well.

This pass locates those edges and slews them with a short raised-cosine ramp.
Only the samples inside a ramp are rewritten; everything else is copied through
bit for bit, so each ringtone keeps its original character.

The pass is idempotent. A file whose edges are already smooth is reported as
clean and written back byte-identical, so it is safe to re-run after adding or
regenerating a sound.
"""

from __future__ import annotations

import math
import random
import struct
import sys
import wave
from pathlib import Path


SOUNDS_DIRECTORY = Path(__file__).resolve().parents[1] / "Stopwatch" / "Sounds"

FULL_SCALE = 32_767

# Anything quieter than this counts as silence when looking for gate edges.
SILENCE_FLOOR = 0.0015 * FULL_SCALE
# An edge only needs repairing when the waveform steps across this much at once.
STEP_TOLERANCE = 0.006 * FULL_SCALE
# Shorter gaps than this are part of the waveform, not a gate.
MIN_SILENCE = 0.004
# Ramp lengths. The attack stays short so beeps still read as crisp.
FADE_IN = 0.003
FADE_OUT = 0.008
# How much of the signal before an edge is inspected. Long enough to span a
# full cycle of the lowest content, so a zero crossing right on the boundary
# cannot hide a tail that is still ringing.
EDGE_WINDOW = 0.005
# ...compared against the very last moment before the edge. A gated beep is
# still at full level when it stops (measured 0.94-0.98 of the window peak),
# while a tone that is genuinely releasing has already fallen away (0.31).
EDGE_TAIL = 0.001
SUSTAINED_RATIO = 0.6
# Digital silence guaranteed at the end of every file, so loop seams are clean.
TAIL_SILENCE = 0.030


def read_wav(path: Path) -> tuple[list[int], int]:
    with wave.open(str(path), "rb") as source:
        if source.getnchannels() != 1 or source.getsampwidth() != 2:
            raise ValueError(f"{path.name}: expected 16-bit mono PCM")
        frames = source.readframes(source.getnframes())
        return list(struct.unpack(f"<{len(frames) // 2}h", frames)), source.getframerate()


def write_wav(path: Path, samples: list[int], sample_rate: int) -> None:
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes(struct.pack(f"<{len(samples)}h", *samples))


def silence_runs(samples: list[int], minimum: int) -> list[tuple[int, int]]:
    """Half-open ranges of at least `minimum` consecutive near-silent samples."""
    runs: list[tuple[int, int]] = []
    start: int | None = None
    for index, value in enumerate(samples):
        if abs(value) <= SILENCE_FLOOR:
            if start is None:
                start = index
        elif start is not None:
            if index - start >= minimum:
                runs.append((start, index))
            start = None
    if start is not None and len(samples) - start >= minimum:
        runs.append((start, len(samples)))
    return runs


def sounding_spans(total: int, runs: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """The stretches between the silences — one per beep."""
    spans: list[tuple[int, int]] = []
    cursor = 0
    for start, end in runs:
        if start > cursor:
            spans.append((cursor, start))
        cursor = end
    if cursor < total:
        spans.append((cursor, total))
    return spans


def plan_ramps(samples: list[int], sample_rate: int) -> tuple[list[float], list[str]]:
    """Gain curve that smooths every hard edge, plus a human-readable report."""
    total = len(samples)
    gain = [1.0] * total
    report: list[str] = []

    fade_in = int(FADE_IN * sample_rate)
    fade_out = int(FADE_OUT * sample_rate)
    window = int(EDGE_WINDOW * sample_rate)
    tail = int(EDGE_TAIL * sample_rate)
    spans = sounding_spans(total, silence_runs(samples, int(MIN_SILENCE * sample_rate)))

    for start, end in spans:
        length = end - start

        # Onset: silence straight into a live waveform is a step, and the size
        # of that step is simply how far the first sample sits from zero.
        if start > 0:
            step = max(abs(samples[start]), abs(samples[min(start + 1, end - 1)]))
            if step > STEP_TOLERANCE:
                count = min(fade_in, length // 2)
                if count > 1:
                    for offset in range(count):
                        gain[start + offset] *= 0.5 - 0.5 * math.cos(math.pi * offset / count)
                    report.append(f"onset {start / sample_rate:6.3f}s step {step:6d}")

        # Offset: a beep that is cut off mid-waveform, or a file that simply
        # runs out of buffer while the sound is still ringing.
        edge = max(abs(value) for value in samples[max(start, end - window):end])
        sustained = max(abs(value) for value in samples[max(start, end - tail):end])
        at_end = end == total
        # Ending on the file boundary is a truncation however the waveform
        # happens to land, because nothing follows it to decay into.
        cut = at_end or sustained > SUSTAINED_RATIO * edge
        if edge > STEP_TOLERANCE and cut:
            count = min(fade_out, length // 2)
            if count > 1:
                base = end - count
                for offset in range(count):
                    gain[base + offset] *= 0.5 + 0.5 * math.cos(math.pi * (offset + 1) / count)
                where = "end  " if at_end else "offset"
                report.append(f"{where} {end / sample_rate:6.3f}s level {edge:6d}")

    return gain, report


def apply_ramps(samples: list[int], gain: list[float]) -> list[int]:
    """Rewrite only the ramped samples, dithering the fractional values."""
    noise = random.Random(0x5709)
    result = list(samples)
    for index, factor in enumerate(gain):
        if factor == 1.0:
            continue
        shaped = samples[index] * factor
        # TPDF dither keeps the quantisation error uncorrelated with the signal,
        # so long ramp tails fade out smoothly instead of turning granular.
        shaped += noise.random() - noise.random()
        result[index] = max(-32_768, min(32_767, int(round(shaped))))
    return result


def pad_tail(samples: list[int], sample_rate: int) -> tuple[list[int], bool]:
    required = int(TAIL_SILENCE * sample_rate)
    existing = 0
    for value in reversed(samples):
        if value != 0:
            break
        existing += 1
    if existing >= required:
        return samples, False
    return samples + [0] * (required - existing), True


def declick(path: Path) -> bool:
    samples, sample_rate = read_wav(path)
    gain, report = plan_ramps(samples, sample_rate)
    repaired = apply_ramps(samples, gain)
    repaired, padded = pad_tail(repaired, sample_rate)

    if not report and not padded:
        print(f"{path.name:16s} clean")
        return False

    write_wav(path, repaired, sample_rate)
    notes = list(report)
    if padded:
        notes.append(f"padded to {TAIL_SILENCE * 1000:.0f}ms of silence")
    print(f"{path.name:16s} repaired")
    for note in notes:
        print(f"{'':16s}   {note}")
    return True


def main() -> int:
    paths = sorted(SOUNDS_DIRECTORY.glob("*.wav"))
    if not paths:
        print(f"no ringtones found in {SOUNDS_DIRECTORY}", file=sys.stderr)
        return 1
    changed = sum(declick(path) for path in paths)
    print(f"\n{changed} of {len(paths)} ringtones repaired")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
