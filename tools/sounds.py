#!/usr/bin/env python3
"""Cut the knock samples (source/sounds/knock-N.wav) from a recording of kubb hits.

    python3 tools/sounds.py <recording.aiff|wav> [out_dir]

Jamie recorded a baton hitting a kubb again and again (2026-11-14). The raw take
stays out of the repo (5 MB); this makes the game's samples from it:

1. ffmpeg: mono, the rumble under the take (wind and handling, below about
   300 Hz) taken out by two 160 Hz high-pass filters, a 10 kHz low-pass, 22050 Hz
   16-bit (the Playdate's speaker loses nothing above that).
2. Each hit is a sample over `THRESH` after half a second of quiet. A rumble that
   gets through the filters is much quieter than any hit, so onsets more than
   `KEEP_DB` under the loudest are dropped.
3. Each is cut from 4 ms before the onset for `LENGTH` s, faded in over those 4 ms
   and out (squared) after `FADE_FROM` s, so the tail ends in silence.
4. Levelled: each gets the gain that brings its first 80 ms to the same RMS, then
   all one gain so the loudest peak is -1 dBFS.

Needs ffmpeg (Homebrew) and Python's standard library only.
"""
import array, math, os, subprocess, sys, tempfile, wave

SR, THRESH, GAP, KEEP_DB = 22050, 3000, 0.5, 10.0
PRE, LENGTH, FADE_FROM, RMS_WIN, PEAK_DB = 0.004, 0.36, 0.10, 0.08, -1.0


def main():
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "..", "source", "sounds")
    with tempfile.TemporaryDirectory() as tmp:
        hp = os.path.join(tmp, "hp.wav")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-ac", "1",
                        "-af", "highpass=f=160,highpass=f=160,lowpass=f=10000,volume=0.8",
                        "-ar", str(SR), "-c:a", "pcm_s16le", hp], check=True)
        w = wave.open(hp)
        a = array.array("h", w.readframes(w.getnframes()))
    gap, last, ons = int(GAP * SR), -int(GAP * SR), []
    for i, x in enumerate(a):
        if abs(x) > THRESH:
            if i - last >= gap:
                ons.append(i)
            last = i
    pre, length, fade = int(PRE * SR), int(LENGTH * SR), int(FADE_FROM * SR)
    clips = []
    for o in ons:
        c = [float(x) for x in a[o - pre:o - pre + length]]
        if len(c) < length:
            continue
        for i in range(pre):
            c[i] *= i / pre
        for i in range(fade, length):
            c[i] *= (1 - (i - fade) / (length - fade)) ** 2
        n = int(RMS_WIN * SR)
        rms = math.sqrt(sum(x * x for x in c[:n]) / n)
        clips.append((o / SR, c, rms, max(abs(x) for x in c)))
    top = max(p for *_, p in clips)
    clips = [c for c in clips if 20 * math.log10(top / c[3]) <= KEEP_DB]
    gains = [1 / r for _, _, r, _ in clips]
    k = 32768 * 10 ** (PEAK_DB / 20) / max(p * g for (*_, p), g in zip(clips, gains))
    os.makedirs(out, exist_ok=True)
    for n, ((t, c, _, p), g) in enumerate(zip(clips, gains), 1):
        s = array.array("h", [int(max(-32767, min(32767, round(x * g * k)))) for x in c])
        f = wave.open(os.path.join(out, f"knock-{n}.wav"), "w")
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR); f.writeframes(s.tobytes()); f.close()
        print(f"knock-{n}: {t:6.3f} s in the take, gain {20 * math.log10(g * k):+.1f} dB, "
              f"peak {20 * math.log10(p * g * k / 32768):.1f} dBFS")


if __name__ == "__main__":
    main()
