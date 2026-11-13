#!/usr/bin/env python3
"""Make the game's 1-bit art and display fonts (docs/design/README.md, "Type"
and "Launcher").

    python3 tools/art/build.py [--preview DIR]

Renders with headless Google Chrome (canvas, so nothing is installed) and
writes pure black and white PNGs at 1x:

  source/fonts/ThrowingWoodDisplay-16.fnt   + its -table-W-H.png  (cap 16 px)
  source/fonts/ThrowingWoodDisplay-32.fnt   + its -table-W-H.png  (cap 32 px)
  source/images/title.png                   the title without its menu
  source/images/winner.png                  the winner card's burst
  source/launcher/card.png, card-highlighted/1..4.png, icon.png,
  source/launcher/launchImage.png

The display face is a bitmap rendering of Londrina Solid Black
(tools/art/LondrinaSolid-Black.ttf, SIL Open Font License 1.1, tools/art/OFL.txt).
A rendering is a Modified Version under the OFL, and "Londrina Solid" is a
Reserved Font Name, so the bitmap fonts are named Throwing Wood Display and
ship with the licence (source/fonts/OFL.txt).

The shapes are the SVG of docs/design/src/*.html (Title, Launcher, Winner) in
screen pixels. Every pixel is thresholded: darker than half is black.
--preview DIR also writes each font's glyphs and a sample line at 4x there
(for the hand check), never into the repo.
"""
import base64
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
import zlib

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(ROOT, "source")
FONT_TTF = os.path.join(HERE, "LondrinaSolid-Black.ttf")
FONT_NAME = "ThrowingWoodDisplay"

# Capitals, digits and the punctuation the boards use, plus ' and ? for names.
CHARS = list("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789") + list("!.·%°+-:,/'?") + [" "]
FONTS = [
    # cap: cap height in px; tracking: the .fnt tracking (board letter-spacing 1)
    {"cap": 16, "tracking": 1, "threshold": 200},
    {"cap": 32, "tracking": 2, "threshold": 176},
]

# Hand-cut glyphs at cap 16, where the rendering fills the counters (M, N
# and W came out as blocks, 8 the same as B). Cap rows only, top to bottom,
# drawn from the cell's second column; the number is the advance.
OVERRIDES = {16: {
    "M": (12, ["###.....###", "####...####", "#####.#####", "###########", "###.###.###", "###..#..###",
               "###.....###", "###.....###", "###.....###", "###.....###", "###.....###", "###.....###",
               "###.....###", "###.....###", "###.....###", "###.....###"]),
    "N": (11, ["###....###", "####...###", "####...###", "#####..###", "#####..###", "######.###",
               "######.###", "###.######", "###.######", "###..#####", "###..#####", "###...####",
               "###...####", "###....###", "###....###", "###....###"]),
    "W": (12, ["###.....###", "###.....###", "###.....###", "###.....###", "###.....###", "###.....###",
               "###.....###", "###.....###", "###..#..###", "###..#..###", "###.###.###", "###.###.###",
               "###########", "#####.#####", "####...####", "###.....###"]),
    "8": (11, ["..######..", ".########.", "###....###", "###....###", "###....###", ".########.",
               "..######..", ".########.", "###....###", "###....###", "###....###", "###....###",
               "###....###", "##########", ".########.", "..######.."]),
}}

# --------------------------------------------------------------------------
# Shapes (docs/design/src), screen pixels.

def wordmark_title(b_angle=16):
    """KUBB as on the title board (src/Title.html), the last B tipped b_angle."""
    k = "58,40 76,40 76,68 94,40 114,40 92,76 114,116 94,116 76,88 76,116 58,116"
    u = "126,40 144,40 144,98 164,98 164,40 182,40 182,116 126,116"
    b = "194,40 242,40 250,48 250,72 244,78 250,84 250,108 242,116 194,116"
    return f'''
<path d="M22 116l-3 -6M22 116v-7M22 116l3 -6M40 116l-2 -4M40 116v-5M40 116l2 -4M352 116l-2 -4M352 116v-5M352 116l2 -4M376 116l-3 -6M376 116v-7M376 116l3 -6" stroke="#000" stroke-width="2" fill="none"/>
<g transform="translate(6 0)">
<polygon points="{k}" fill="#000" stroke="#000" stroke-width="3"/>
<polygon points="{u}" fill="#000" stroke="#000" stroke-width="3"/>
<polygon points="{b}" fill="#000" stroke="#000" stroke-width="3"/>
</g>
<polygon points="{k}" fill="#fff" stroke="#000" stroke-width="3"/>
<path d="M64 48v60M70 56v52M100 46l-14 22M98 104l-10 -18" stroke="#000" stroke-width="1"/>
<polygon points="{u}" fill="#fff" stroke="#000" stroke-width="3"/>
<path d="M132 48v58M138 60v44M170 48v58M176 56v44" stroke="#000" stroke-width="1"/>
<polygon points="{b}" fill="#fff" stroke="#000" stroke-width="3"/>
<rect x="212" y="54" width="20" height="14" fill="#000"/><rect x="212" y="86" width="20" height="16" fill="#000"/>
<path d="M200 48v60M206 58v44" stroke="#000" stroke-width="1"/>
<polygon points="318,116 326,112 368,112 360,116" fill="#000"/>
<g transform="rotate({b_angle} 318 116)">
<polygon points="268,40 316,40 324,48 324,72 318,78 324,84 324,108 316,116 268,116" fill="#000" stroke="#000" stroke-width="3"/>
<polygon points="262,40 310,40 318,48 318,72 312,78 318,84 318,108 310,116 262,116" fill="#fff" stroke="#000" stroke-width="3"/>
<rect x="280" y="54" width="20" height="14" fill="#000"/><rect x="280" y="86" width="20" height="16" fill="#000"/>
<path d="M268 48v60M274 58v44" stroke="#000" stroke-width="1"/>
</g>
<path d="M196 18h30M206 26h24M212 10h20" stroke="#000" stroke-width="2"/>
<g transform="rotate(-18 258 22)">
<rect x="236" y="17" width="44" height="10" rx="2" fill="#fff" stroke="#000" stroke-width="2"/>
<rect x="242" y="17" width="5" height="10" fill="#000"/><rect x="269" y="17" width="5" height="10" fill="#000"/>
</g>
<polygon points="300,26 292,29 296,37 288,34 284,42 280,34 272,38 276,30 268,26 277,23 274,15 282,19 286,11 290,20 298,16 294,24" fill="#000"/>
'''


def wordmark_card(b_angle=16):
    """The launcher card's wordmark (src/Launcher.html #wm), the last B tipped b_angle."""
    k = "58,40 76,40 76,68 94,40 114,40 92,76 114,116 94,116 76,88 76,116 58,116"
    u = "126,40 144,40 144,98 164,98 164,40 182,40 182,116 126,116"
    b = "194,40 242,40 250,48 250,72 244,78 250,84 250,108 242,116 194,116"
    lb = "262,40 310,40 318,48 318,72 312,78 318,84 318,108 310,116 262,116"
    rot = f"rotate({b_angle} 318 116)"
    return f'''
<g fill="#000" transform="translate(6,0)">
<polygon points="{k}"/><polygon points="{u}"/><polygon points="{b}"/>
<polygon transform="{rot}" points="{lb}"/>
</g>
<g fill="#fff" stroke="#000" stroke-width="2">
<polygon points="{k}"/><polygon points="{u}"/><polygon points="{b}"/>
<polygon transform="{rot}" points="{lb}"/>
</g>
<rect x="212" y="54" width="20" height="16" fill="#000"/><rect x="212" y="86" width="20" height="16" fill="#000"/>
<g transform="{rot}"><rect x="280" y="54" width="20" height="16" fill="#000"/><rect x="280" y="86" width="20" height="16" fill="#000"/></g>
<g transform="rotate(-38 300 30)">
<rect x="262" y="24" width="64" height="12" rx="3" fill="#fff" stroke="#000" stroke-width="2"/>
<rect x="274" y="24" width="4" height="12" fill="#000"/><rect x="310" y="24" width="4" height="12" fill="#000"/>
</g>
<polygon points="286,36 279,39 284,45 276,43 275,51 269,46 264,51 262,43 255,45 259,39 252,36 259,33 255,26 262,29 264,21 269,27 275,21 276,29 284,26 279,33" fill="#000"/>
'''


def svg(w, h, body, bg="#fff"):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" '
            f'shape-rendering="crispEdges"><rect width="{w}" height="{h}" fill="{bg}"/>{body}</svg>')


# The title without its menu (src/Title.html): the wordmark, the black band
# from y 117, THROWING WOOD and the rule under it. The menu and the A START
# line are drawn by scenes/title over this image. The launch image is this
# same picture, so loading ends with no jump.
TITLE_BODY = wordmark_title() + '<rect x="0" y="117" width="400" height="123" fill="#000"/>' \
    '<rect x="58" y="162" width="284" height="2" fill="#fff"/>'
TITLE_TEXT = [{"text": "THROWING WOOD", "x": 200, "y": 152, "size": 30, "spacing": 4, "fill": "#fff"}]


def card(angle):
    body = f'<g transform="translate(4,-22) scale(0.9)">{wordmark_card(angle)}</g>' \
        '<rect x="0" y="108" width="350" height="47" fill="#000"/>'
    return {"w": 350, "h": 155, "svg": svg(350, 155, body),
            "texts": [{"text": "THROWING WOOD", "x": 175, "y": 141, "size": 28, "spacing": 4, "fill": "#fff"}]}


ICON = '''
<polygon points="9,13 9,4 13,8 16,3 19,8 23,4 23,13" fill="#fff"/>
<rect x="9" y="14" width="14" height="2" fill="#000"/>
<rect x="9" y="16" width="14" height="13" fill="#fff"/>
<rect x="20" y="16" width="3" height="13" fill="#000"/><rect x="20" y="16" width="1" height="13" fill="#fff"/>
<rect x="9" y="19" width="11" height="1" fill="#000"/>
<polygon points="14,24 16,22 18,24 16,26" fill="#000"/>
<rect x="6" y="29" width="20" height="1" fill="#fff"/>
'''

# The winner card's burst with the toppled king (src/Winner.html), on black.
WINNER = '''
<polygon points="382,104 350,117 371,145 337,141 341,175 313,154 300,186 287,154 259,175 263,141 229,145 250,117 218,104 250,91 229,63 263,67 259,33 287,54 300,22 313,54 341,33 337,67 371,63 350,91" fill="#fff"/>
<g transform="rotate(72 300 104) translate(109 20)">
<polygon points="202,58 208,52 208,118 202,124" fill="#000"/>
<rect x="180" y="58" width="22" height="66" fill="#fff" stroke="#000" stroke-width="2"/>
<polygon points="180,58 180,44 184,50 188,42 191,50 195,42 198,50 202,44 202,58" fill="#fff" stroke="#000" stroke-width="2"/>
<polygon points="202,58 202,44 205,46 208,40 208,52" fill="#000"/>
<rect x="180" y="62" width="22" height="4" fill="#000"/><rect x="180" y="74" width="22" height="2" fill="#000"/>
<path d="M186 84l5 6l5 -6l-5 -6z" fill="#000"/><path d="M185 96v22M191 100v20M197 96v24" stroke="#000" stroke-width="1"/>
</g>
<rect x="262" y="122" width="78" height="3" fill="#000"/>
'''

# B tipping 0 to 16 degrees over four frames
HIGHLIGHT_ANGLES = [0, 16 / 3, 32 / 3, 16]
# the B stands, tips over in three frames, then holds tipped (SDK: card-highlighted/animation.txt)
ANIMATION_TXT = "frames = 1x8, 2, 3, 4x30\n"


def images():
    out = {
        "images/title": {"w": 400, "h": 240, "svg": svg(400, 240, TITLE_BODY), "texts": TITLE_TEXT},
        "launcher/launchImage": {"w": 400, "h": 240, "svg": svg(400, 240, TITLE_BODY), "texts": TITLE_TEXT},
        "images/winner": {"w": 400, "h": 240, "svg": svg(400, 240, WINNER, bg="#000"), "texts": []},
        "launcher/icon": {"w": 32, "h": 32, "svg": svg(32, 32, ICON, bg="#000"), "texts": []},
        "launcher/card": card(16),
    }
    for i, a in enumerate(HIGHLIGHT_ANGLES):
        out[f"launcher/card-highlighted/{i + 1}"] = card(a)
    return out


# --------------------------------------------------------------------------
# The page Chrome runs: renders every font glyph and image on a canvas and
# writes the thresholded pixels as JSON into the DOM (--dump-dom).

PAGE = r"""<!doctype html><html><body><pre id="out">pending</pre><script>
const FONT_B64 = "__FONT__";
const JOBS = __JOBS__;
let THR = 128;
const ink = (d, i) => d[i + 3] >= THR;   // coverage at least THR/255
async function main() {
  const face = new FontFace("D", "url(data:font/ttf;base64," + FONT_B64 + ")");
  await face.load(); document.fonts.add(face);
  const out = { fonts: [], images: {} };
  const c = document.createElement("canvas"); const x = c.getContext("2d", { willReadFrequently: true });
  // the rows of ink of one glyph drawn at size s (pen x0, baseline B)
  function glyph(ch, s, W, H, x0, B) {
    c.width = W; c.height = H; x.clearRect(0, 0, W, H);
    x.font = s + "px D"; x.fillStyle = "#000"; x.textBaseline = "alphabetic"; x.letterSpacing = "0px";
    x.fillText(ch, x0, B);
    const d = x.getImageData(0, 0, W, H).data;
    const rows = []; let minx = W, maxx = -1, miny = H, maxy = -1;
    for (let y = 0; y < H; y++) { let r = "";
      for (let xx = 0; xx < W; xx++) { const on = ink(d, (y * W + xx) * 4); r += on ? "1" : "0";
        if (on) { minx = Math.min(minx, xx); maxx = Math.max(maxx, xx); miny = Math.min(miny, y); maxy = Math.max(maxy, y); } }
      rows.push(r); }
    return { rows, minx, maxx, miny, maxy, adv: x.measureText(ch).width };
  }
  for (const f of JOBS.fonts) {
    THR = f.threshold;
    const W = f.cap * 4, H = f.cap * 3, x0 = f.cap, B = f.cap * 2;
    // the font size whose H is exactly cap rows of ink (middle of the range)
    const ok = [];
    for (let s = f.cap; s <= f.cap * 2.2; s += 0.125) { const g = glyph("H", s, W, H, x0, B); if (g.maxy - g.miny + 1 === f.cap && g.maxy === B - 1) ok.push(s); }
    const size = ok[Math.floor(ok.length / 2)];
    const glyphs = f.chars.map(ch => Object.assign({ ch }, glyph(ch, size, W, H, x0, B)));
    out.fonts.push({ cap: f.cap, size, x0, B, glyphs });
  }
  for (const [name, im] of Object.entries(JOBS.images)) {
    c.width = im.w; c.height = im.h;
    const img = new Image(); img.src = "data:image/svg+xml;base64," + btoa(im.svg); await img.decode();
    x.drawImage(img, 0, 0);
    for (const t of im.texts) {
      x.font = t.size + "px D"; x.fillStyle = t.fill; x.textBaseline = "alphabetic";
      x.letterSpacing = (t.spacing || 0) + "px"; x.textAlign = "left";
      const w = x.measureText(t.text).width - (t.spacing || 0);   // no spacing after the last letter
      x.fillText(t.text, Math.round(t.x - w / 2), t.y);
    }
    const d = x.getImageData(0, 0, im.w, im.h).data; const rows = [];
    for (let y = 0; y < im.h; y++) { let r = ""; for (let xx = 0; xx < im.w; xx++) r += d[(y * im.w + xx) * 4] < 128 ? "1" : "0"; rows.push(r); }
    out.images[name] = { w: im.w, h: im.h, rows };
  }
  document.getElementById("out").textContent = JSON.stringify(out);
}
main().catch(e => { document.getElementById("out").textContent = "ERROR " + e; });
</script></body></html>"""


def render(jobs):
    with open(FONT_TTF, "rb") as f:
        font = base64.b64encode(f.read()).decode()
    page = PAGE.replace("__FONT__", font).replace("__JOBS__", json.dumps(jobs))
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "art.html")
        with open(path, "w") as f:
            f.write(page)
        dom = subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                              "--user-data-dir=" + os.path.join(tmp, "profile"),
                              "--virtual-time-budget=20000", "--dump-dom", "file://" + path],
                             capture_output=True, text=True, timeout=180).stdout
    m = re.search(r'<pre id="out">(.*?)</pre>', dom, re.S)
    if not m or not m.group(1).startswith("{"):
        sys.exit("Chrome did not render the art: " + (m.group(1)[:200] if m else dom[:200]))
    return json.loads(m.group(1).replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"'))


# --------------------------------------------------------------------------
# 1-bit PNGs.

def write_png(path, rows, transparent=False):
    """rows: strings of '1' (black) and '0' (white). transparent: white is
    transparent (a 1-bit palette with tRNS, for font tables); otherwise a
    1-bit greyscale image (0 = black)."""
    h, w = len(rows), len(rows[0])
    raw = bytearray()
    for r in rows:
        raw.append(0)
        bits = r if transparent else r.translate(str.maketrans("01", "10"))
        bits = bits + "0" * (-len(bits) % 8)
        raw.extend(int(bits[i:i + 8], 2) for i in range(0, len(bits), 8))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n"
    if transparent:
        png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 1, 3, 0, 0, 0))
        png += chunk(b"PLTE", bytes([255, 255, 255, 0, 0, 0]))
        png += chunk(b"tRNS", bytes([0]))
    else:
        png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 1, 0, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


def fnt_name(ch):
    return "space" if ch == " " else ch


def write_font(f, tracking, preview):
    cap, glyphs = f["cap"], f["glyphs"]
    top = f["B"] - cap - 1                 # one row above the caps for round overshoots
    height = cap + 1 + max(3, cap // 4)    # and room below the baseline for , and /
    left = min([f["x0"]] + [g["minx"] for g in glyphs if g["maxx"] >= 0])
    width = max(g["maxx"] for g in glyphs) - left + 1
    for g in glyphs:
        if g["maxx"] >= 0 and (g["miny"] < top or g["maxy"] >= top + height):
            sys.exit(f"glyph {g['ch']!r} at cap {cap} does not fit its cell")
    cols = 16
    nrows = (len(glyphs) + cols - 1) // cols
    table = [["0"] * (cols * width) for _ in range(nrows * height)]
    lines = [f"-- Throwing Wood Display, cap height {cap} px: a 1-bit rendering of Londrina Solid Black",
             "-- (Copyright 2011 The Londrina Solid Authors, https://github.com/marcelommp/Londrina-Typeface,",
             '-- with Reserved Font Name "Londrina Solid"). SIL Open Font License 1.1: see OFL.txt.',
             "-- Made by tools/art/build.py; do not edit by hand.",
             f"tracking={tracking}", ""]
    for g in glyphs:
        hand = OVERRIDES.get(cap, {}).get(g["ch"])
        if hand:
            adv, cut = hand
            rows = [list("0" * len(g["rows"][0])) for _ in g["rows"]]
            for y, r in enumerate(cut):
                for xx, c in enumerate(r):
                    if c == "#":
                        rows[top + 1 + y][left + 1 + xx] = "1"
            g["rows"] = ["".join(r) for r in rows]
            g["adv"] = adv - (f["x0"] - left)
    for i, g in enumerate(glyphs):
        r0, c0 = (i // cols) * height, (i % cols) * width
        for y in range(height):
            src = g["rows"][top + y]
            for xx in range(width):
                if src[left + xx] == "1":
                    table[r0 + y][c0 + xx] = "1"
        adv = round(g["adv"]) + (f["x0"] - left)
        if g["ch"] == " ":
            adv = max(adv, cap // 3)
        lines.append(f"{fnt_name(g['ch'])}\t\t{adv}")
        g["cell"] = [g["rows"][top + y][left:left + width] for y in range(height)]
        g["advance"] = adv
    base = os.path.join(SRC, "fonts", f"{FONT_NAME}-{cap}")
    for old in os.listdir(os.path.join(SRC, "fonts")) if os.path.isdir(os.path.join(SRC, "fonts")) else []:
        if old.startswith(f"{FONT_NAME}-{cap}-table-"):
            os.remove(os.path.join(SRC, "fonts", old))
    write_png(f"{base}-table-{width}-{height}.png", ["".join(r) for r in table], transparent=True)
    with open(base + ".fnt", "w") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"font cap {cap}: size {f['size']} px, cell {width} x {height}, {len(glyphs)} glyphs")
    if preview:
        preview_font(f, glyphs, tracking, height, preview)


def preview_font(f, glyphs, tracking, height, outdir):
    """Every glyph's cell side by side, then sample lines, at 4x (black on white)."""
    by = {g["ch"]: g for g in glyphs}

    def line(text):
        rows = [""] * height
        for ch in text:
            g = by[ch]
            for y in range(height):
                cell = g["cell"][y][:g["advance"]].ljust(g["advance"], "0")
                rows[y] += cell + "0" * tracking
        return rows
    blocks = [line("".join(g["ch"] for g in glyphs[:24])), line("".join(g["ch"] for g in glyphs[24:]))]
    for t in ["THEN 6 BATONS", "3 KUBBS IN", "TEAM B WINS!", "PASS + PLAY", "12% 90° 4:05 A/B 1,2 · X?"]:
        blocks.append(line(t))
    w = max(len(b[0]) for b in blocks) + 8
    rows = []
    for b in blocks:
        for r in b:
            rows.append(("0000" + r).ljust(w, "0"))
        rows.extend(["0" * w] * 4)
    big = []
    for r in rows:
        rr = "".join(c * 4 for c in r)
        big.extend([rr] * 4)
    write_png(os.path.join(outdir, f"font-{f['cap']}-preview.png"), big)


def main():
    preview = None
    if "--preview" in sys.argv:
        preview = sys.argv[sys.argv.index("--preview") + 1]
        os.makedirs(preview, exist_ok=True)
    ims = images()
    res = render({"fonts": [{"cap": f["cap"], "chars": CHARS, "threshold": f["threshold"]} for f in FONTS], "images": ims})
    os.makedirs(os.path.join(SRC, "fonts"), exist_ok=True)
    for f, spec in zip(res["fonts"], FONTS):
        write_font(f, spec["tracking"], preview)
    for name, im in res["images"].items():
        write_png(os.path.join(SRC, name + ".png"), im["rows"])
        print(f"{name}.png {im['w']} x {im['h']}")
    with open(os.path.join(SRC, "launcher", "card-highlighted", "animation.txt"), "w") as fh:
        fh.write(ANIMATION_TXT)


if __name__ == "__main__":
    main()
