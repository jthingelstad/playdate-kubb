# Cut filmed self-test frames into one reel (tools/film.sh runs this).
# The Simulator writes every frame of a scenario run with film=1 as
# <dir>/<scenario>-f00001.png and on, at the scripted input's 50 frames a
# second. REEL lists what plays, in order: (scenario, first, last) plays those
# frames; (scenario, frame, seconds, 'hold') holds one frame as a still.
# Writes <dir>/reel/r00001.png and on; ffmpeg encodes them.
# python3 tools/film.py <dir>
import os
import shutil
import sys

FPS = 50

REEL = [
    ('title', 1, 2.0, 'hold'),
    ('howto-play', 1, 2.5, 'hold'),       # HOW TO PLAY's first card
    ('match-opening', 1, 1.5, 'hold'),    # the hand-off card
    ('match-opening', 30, 300),           # the first baton: wind-up, flight, TOK!, rest
    ('field', 1, 181),                    # KLAK! two field kubbs with one baton
    ('clock-drill', 1, 240),              # a drilled kubb with a tap of spin
    ('king', 1, 160),                     # KING!
    ('cards', 1811, 3.0, 'hold'),         # the winner card
]

SCENES = sorted({item[0] for item in REEL})


def main(src):
    out = os.path.join(src, 'reel')
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    n = 0

    def put(scene, f):
        nonlocal n
        n += 1
        shutil.copyfile(os.path.join(src, '%s-f%05d.png' % (scene, f)), os.path.join(out, 'r%05d.png' % n))

    for item in REEL:
        if len(item) == 4:
            scene, f, secs, _ = item
            for _ in range(int(secs * FPS)):
                put(scene, f)
        else:
            scene, a, b = item
            have = [int(x[len(scene) + 2:len(scene) + 7]) for x in os.listdir(src)
                    if x.startswith(scene + '-f') and x.endswith('.png')]
            for f in range(a, min(b, max(have)) + 1):
                put(scene, f)
    print('%d frames, %.1f s' % (n, n / FPS))


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--scenes':
        print(' '.join(SCENES))
    else:
        main(sys.argv[1])
