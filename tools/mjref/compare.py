"""Compares the game's engine (ours.jsonl) with MuJoCo (mj.jsonl), case by
case, and writes report.md and report.json (tools/mjref).

Every metric is computed from the traces by the same function for both
engines, so the definitions cannot drift apart. A case counts only when
MuJoCo agrees with itself across its four solver variants (mjsim.py): every
discrete outcome the same and every continuous metric's spread within half
its scale. The divergence of a case is the mean over its metrics of
min(1, |ours - MuJoCo| / scale), a discrete mismatch counting 1.

  python3 tools/mjref/compare.py build/mjref
"""
import json
import math
import os
import sys
from collections import defaultdict

import numpy as np

G = 9.81
SIN_TOPPLE = math.sin(math.radians(5))
EARLY = 0.05  # s after the first touch for the "kept" ratios

# metric -> (scale, kind, plain description)
SCALES = {
    "e": (0.05, "c", "bounce: rebound speed over impact speed"),
    "apex": (0.02, "c", "highest the lowest point rises after the first touch (m)"),
    "spinKept": (0.2, "c", "share of the spin left 0.05 s after the first touch"),
    "speedKept": (0.2, "c", "share of the ground speed left 0.05 s after the first touch"),
    "reboundDeg": (15, "c", "angle of the fastest rise after the touch (deg above the ground)"),
    "runOn": (0.10, "c", "distance along the throw from the first touch to rest (m)"),
    "restYaw": (15, "c", "long axis at rest against the line of the throw (deg, 0..90)"),
    "toppled": (1, "d", "the target toppled"),
    "peakTilt": (15, "c", "the target's largest tilt from upright (deg)"),
    "travel": (0.10, "c", "how far the target's centre ended from where it stood (m)"),
    "batonBack": (0.2, "c", "baton speed along the throw 0.05 s after the hit, over its speed before"),
    "first": (1, "d", "what the baton met first: kubb, ground then kubb, or ground only"),
    "bToppled": (1, "d", "the second kubb toppled"),
    "cToppled": (1, "d", "the third kubb toppled"),
    "bTilt": (15, "c", "the second kubb's largest tilt (deg)"),
    "landY": (0.10, "c", "where it first touched, along the throw (m)"),
    "noseDeg": (15, "c", "long axis below the horizontal in flight, the last sample before the touch (deg)"),
    "fromMark": (0.10, "c", "rest distance from the mark (m)"),
    "pose": (1, "d", "final pose: standing or lying"),
    "crossY": (0.05, "c", "distance when the centre comes down through 0.3 m (m)"),
    "crossT": (0.01, "c", "time of that crossing (s)"),
}
THRESH_SCALE = 0.20  # a tip threshold differing by 20 percent counts fully


def load(path, key):
    out = {}
    with open(path) as f:
        for line in f:
            r = json.loads(line)
            out[(r["id"], r[key])] = r
    return out


class Trace:
    def __init__(self, rec, kinds):
        self.rec = rec
        self.dt = rec["dt"]
        self.a = [np.array(t, dtype=float).reshape(-1, 14) for t in rec["traces"]]
        self.kinds = kinds

    def body(self, k):
        return self.a[k]


def axis(a):
    """World direction of each sample's local z (the long axis)."""
    w, x, y, z = a[:, 3], a[:, 4], a[:, 5], a[:, 6]
    return np.stack([2 * (x * z + w * y), 2 * (y * z - w * x), 1 - 2 * (x * x + y * y)], axis=1)


def rowcol(a):
    """r31, r32, r33 (the world z row) of each sample."""
    w, x, y, z = a[:, 3], a[:, 4], a[:, 5], a[:, 6]
    return 2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)


def lowest(a, k):
    r31, r32, r33 = rowcol(a)
    if k["shape"] == "box":
        return a[:, 2] - (k["hx"] * abs(r31) + k["hy"] * abs(r32) + k["hz"] * abs(r33))
    return a[:, 2] - k["hl"] * abs(r33) - k["r"]


def tilt_deg(a):
    _, _, r33 = rowcol(a)
    return np.degrees(np.arccos(np.clip(abs(r33), 0, 1)))


def toppled(a, k):
    _, _, r33 = rowcol(a)
    if (abs(r33) <= SIN_TOPPLE).any():
        return True
    r31, r32, r33 = rowcol(a[-1:])
    up = abs(r33[0])
    return bool(k["hz"] * abs(r31[0]) > k["hx"] * up or k["hz"] * abs(r32[0]) > k["hy"] * up)


def first_ground(a):
    idx = np.nonzero(a[:, 13] > 0)[0]
    return int(idx[0]) if len(idx) else None


def moved_at(a, lin=0.02, ang=0.2):
    v = np.linalg.norm(a[:, 7:10], axis=1)
    w = np.linalg.norm(a[:, 10:13], axis=1)
    idx = np.nonzero((v > lin) | (w > ang))[0]
    return int(idx[0]) if len(idx) else None


def at(a, i):
    return a[min(i, len(a) - 1)]


def metrics(case, tr, P):
    """The metrics of one run of a case (either engine)."""
    s = case["scen"]
    K = P["kinds"]
    dt = tr.dt
    n_early = max(1, int(round(EARLY / dt)))
    m = {}
    if s == "drop":
        b = case["bodies"][0]
        a = tr.body(0)
        k = K[b["kind"]]
        half = k["hy"] if k["shape"] == "box" else k["r"]
        vin = math.sqrt(b["vel"][2] ** 2 + 2 * G * (b["pos"][2] - half))
        i0 = first_ground(a)
        if i0 is None:
            return None
        lp = lowest(a, k)
        rise = max(0.0, float(lp[i0:i0 + int(0.5 / dt)].max() - lp[-1]))
        m["e"] = math.sqrt(2 * G * rise) / vin
    elif s == "landing":
        k = K["baton"]
        a = tr.body(0)
        i0 = first_ground(a)
        if i0 is None:
            return None
        lp = lowest(a, k)
        m["apex"] = float(lp[i0:].max() - lp[-1])
        w0 = np.linalg.norm(a[0, 10:13])
        m["spinKept"] = float(np.linalg.norm(at(a, i0 + n_early)[10:13]) / w0)
        m["speedKept"] = float(np.linalg.norm(at(a, i0 + n_early)[7:9]) / np.linalg.norm(a[i0 - 1 if i0 else 0, 7:9]))
        win = a[i0:i0 + int(0.1 / dt)]
        j = int(np.argmax(win[:, 9]))
        m["reboundDeg"] = float(math.degrees(math.atan2(max(0.0, win[j, 9]), max(1e-6, abs(win[j, 8])))))
        m["runOn"] = float(a[-1, 1] - a[i0, 1])
        u = axis(a[-1:])[0]
        m["restYaw"] = float(math.degrees(math.atan2(abs(u[0]), abs(u[1]))))
    elif s in ("broadside", "king", "endon"):
        tk = K[case["bodies"][0]["kind"]]
        t = tr.body(0)
        bt = tr.body(1)
        m["toppled"] = toppled(t, tk)
        m["peakTilt"] = float(min(90.0, tilt_deg(t).max()))
        m["travel"] = float(np.linalg.norm(t[-1, :2] - t[0, :2]))
        ih = moved_at(t)
        if s == "endon":
            # from the engines' own contact events, not the 120 Hz samples: a
            # ground touch and a hit within one sample would read as the hit
            fc, fh = tr.rec.get("firstContact"), tr.rec.get("firstHit")
            tid = case["bodies"][0]["id"]
            if not fh or fh.get("with") != tid:
                m["first"] = "ground"
            elif not fc or fc.get("with") == tid or fc["t"] >= fh["t"]:
                m["first"] = "kubb"
            else:
                m["first"] = "ground+kubb"
        else:
            vin = case["bodies"][1]["vel"][1]
            m["batonBack"] = float(at(bt, ih + n_early)[8] / vin) if ih is not None else 1.0
    elif s == "tip":
        a = tr.body(0)
        m["toppled"] = toppled(a, K["kubb"])
        m["peakTilt"] = float(min(90.0, tilt_deg(a).max()))
    elif s == "domino":
        m["toppled"] = toppled(tr.body(0), K["kubb"])
        m["bToppled"] = toppled(tr.body(1), K["kubb"])
        m["bTilt"] = float(min(90.0, tilt_deg(tr.body(1)).max()))
        if len(tr.a) > 2:
            m["cToppled"] = toppled(tr.body(2), K["kubb"])
    elif s == "drill":
        k = K["kubb"]
        a = tr.body(0)
        i0 = first_ground(a)
        if i0 is None:
            return None
        m["landY"] = float(a[i0, 1])
        # the attitude in flight: the last sample before the touch (both
        # engines sample at SAMPLE_HZ). The first sample that touched comes up
        # to 8 ms after it, when ours has already turned the kubb with the
        # whole impact of one step and MuJoCo's soft contact only begun to
        ia = max(i0 - 1, 0)
        u = axis(a[ia:ia + 1])[0]
        m["noseDeg"] = float(math.degrees(math.asin(min(1.0, abs(u[2])))))
        lp = lowest(a, k)
        m["apex"] = float(lp[i0:].max() - lp[-1])
        m["runOn"] = float(a[-1, 1] - a[i0, 1])
        ex = case["extra"]
        m["fromMark"] = float(math.hypot(a[-1, 0] - ex["markX"], a[-1, 1] - ex["markY"]))
        _, _, r33 = rowcol(a[-1:])
        m["pose"] = "standing" if abs(r33[0]) > math.cos(math.radians(25)) else "lying"
    elif s == "flight":
        a = tr.body(0)
        zc = case["extra"]["zCross"]
        z = a[:, 2]
        idx = np.nonzero((z[:-1] >= zc) & (z[1:] < zc) & (a[1:, 9] < 0))[0]
        if not len(idx):
            return None
        i = int(idx[0])
        f = (z[i] - zc) / (z[i] - z[i + 1])
        m["crossY"] = float(a[i, 1] + f * (a[i + 1, 1] - a[i, 1]))
        m["crossT"] = float((i + f) * dt)
    return m


def diff(name, x, y):
    scale, kind, _ = SCALES[name]
    if kind == "d":
        return 0.0 if x == y else 1.0
    return min(1.0, abs(x - y) / scale)


def spread_ok(name, vals, ours=None):
    """MuJoCo agrees with itself on a metric: every variant within half the
    metric's scale of the others (a discrete one: all the same); or, for a
    continuous one, every variant on the same side of ours and their spread
    under half their distance from it (they disagree on how much, not on the
    direction or rough size of the gap)."""
    scale, kind, _ = SCALES[name]
    if kind == "d":
        return len(set(vals)) == 1
    spread = max(vals) - min(vals)
    if spread <= 0.5 * scale:
        return True
    if ours is None:
        return False
    if all(v > ours for v in vals) or all(v < ours for v in vals):
        return spread <= 0.5 * min(abs(v - ours) for v in vals)
    return False


def fnum(v, nd=3):
    if isinstance(v, bool):
        return "yes" if v else "no"
    if isinstance(v, str):
        return v
    if v is None:
        return "-"
    return ("%." + str(nd) + "f") % v


def main():
    out = sys.argv[1]
    P = json.load(open(os.path.join(out, "params.json")))
    cases = json.load(open(os.path.join(out, "cases.json")))
    calib = json.load(open(os.path.join(out, "calib.json")))
    ours = load(os.path.join(out, "ours.jsonl"), "mode")
    mj = load(os.path.join(out, "mj.jsonl"), "variant")
    variants = list(calib["timeconst"].keys())
    rows = []
    for c in cases:
        if (c["id"], "ref") not in mj:
            continue
        res = {}
        for mode in ("mech", "game"):
            res[mode] = metrics(c, Trace(ours[(c["id"], mode)], P), P)
        for v in variants:
            r = mj[(c["id"], v)]
            res[v] = None if "error" in r else metrics(c, Trace(r, P), P)
        row = {"id": c["id"], "scen": c["scen"], "group": c["group"], "params": c["params"], "res": res,
               "extra": c.get("extra"),
               "converged": True, "unconverged": []}
        if any(res[v] is None for v in variants) or res["mech"] is None:
            row["converged"] = False
            row["unconverged"].append("no result")
        else:
            for name in res["ref"]:
                vals = [res[v][name] for v in variants]
                if not spread_ok(name, vals, res["mech"][name]):
                    row["unconverged"].append(name)
            # metrics MuJoCo does not agree with itself on are left out; a case
            # with none left, or with a discrete outcome in doubt, is left out whole
            good = [nm for nm in res["ref"] if nm not in row["unconverged"]]
            if not good or any(SCALES[nm][1] == "d" for nm in row["unconverged"]):
                row["converged"] = False
            # each metric's divergence against the MuJoCo variant nearest ours
            ds = {name: min(diff(name, res["mech"][name], res[v][name]) for v in variants) for name in good}
            row["d"] = ds
            row["D"] = sum(ds.values()) / len(ds) if ds else None
            if res["game"] is not None and ds:
                row["Dgame"] = sum(min(diff(nm, res["game"][nm], res[v][nm]) for v in variants) for nm in ds) / len(ds)
        rows.append(row)

    # tip thresholds per group: the smallest J that topples
    tips = defaultdict(list)
    for r in rows:
        if r["scen"] == "tip":
            tips[r["group"]].append(r)
    thresholds = []
    for g, rs in tips.items():
        rs.sort(key=lambda r: r["params"]["J"])
        h = rs[0]["params"]["h"]
        entry = {"group": g, "h": h}
        for who in ["mech", "game"] + variants:
            J = next((r["params"]["J"] for r in rs if r["res"][who] and r["res"][who]["toppled"]), None)
            entry[who] = J
        k = P["kinds"]["kubb"]
        Ix = P["kinds"]["kubb"]["inertia"][0]
        Ip = Ix + k["mass"] * (k["hy"] ** 2 + k["hz"] ** 2)
        dE = k["mass"] * G * (math.hypot(k["hy"], k["hz"]) - k["hz"])
        entry["pivot"] = math.sqrt(2 * Ip * dE) / h
        vals = [entry[v] for v in variants]
        entry["converged"] = None not in vals and (max(vals) / min(vals) - 1) <= 0.5 * THRESH_SCALE
        if entry["mech"] and entry["ref"]:
            entry["ratio"] = entry["mech"] / entry["ref"]
            entry["D"] = min(1.0, abs(entry["ratio"] - 1) / THRESH_SCALE)
        thresholds.append(entry)

    # rank groups by their mean divergence over converged cases
    groups = defaultdict(list)
    for r in rows:
        groups[(r["scen"], r["group"])].append(r)
    ranked = []
    for (s, g), rs in groups.items():
        conv = [r for r in rs if r["converged"]]
        if not conv:
            ranked.append({"scen": s, "group": g, "n": len(rs), "conv": 0, "D": None})
            continue
        mean = sum(r["D"] for r in conv) / len(conv)
        per = defaultdict(float)
        for r in conv:
            for nm, v in r["d"].items():
                per[nm] += v / len(conv)
        top = sorted(per.items(), key=lambda kv: -kv[1])[:2]
        dg = [r["Dgame"] for r in conv if "Dgame" in r]
        ranked.append({"scen": s, "group": g, "n": len(rs), "conv": len(conv), "D": mean,
                       "Dgame": sum(dg) / len(dg) if dg else None, "top": top})
    for t in thresholds:
        if t.get("D") is not None:
            ranked.append({"scen": "tip threshold", "group": t["group"], "n": 1, "conv": 1 if t["converged"] else 0,
                           "D": t["D"] if t["converged"] else None,
                           "top": [("threshold J", t["D"])]})
    ranked.sort(key=lambda r: -(r["D"] if r["D"] is not None else -1))

    json.dump({"rows": rows, "thresholds": thresholds, "ranked": ranked, "calib": calib},
              open(os.path.join(out, "report.json"), "w"), default=str)
    write_md(out, P, rows, thresholds, ranked, calib, variants)
    nconv = sum(r["converged"] for r in rows)
    print("compare: %d cases, %d converged -> %s/report.md" % (len(rows), nconv, out))


def sweep_table(rows, names, label_keys):
    """Rows: one per case, ours (mech) / MuJoCo (ref) / ours (game) per metric."""
    head = "| " + " | ".join(label_keys) + " | " + " | ".join(names) + " | D |"
    sep = "|" + "---|" * (len(label_keys) + len(names) + 1)
    out = [head, sep]
    for r in rows:
        cells = [fnum(r["params"][k], 3).rstrip("0").rstrip(".") if isinstance(r["params"][k], float) else str(
            r["params"][k]) for k in label_keys]
        if r["res"]["mech"] is None or r["res"]["ref"] is None:
            out.append("| " + " | ".join(cells) + " |" + " - |" * (len(names) + 1))
            continue
        for nm in names:
            o, mv, gv = r["res"]["mech"].get(nm), r["res"]["ref"].get(nm), r["res"]["game"].get(nm) if r["res"][
                "game"] else None
            nd = 0 if nm in ("peakTilt", "bTilt", "reboundDeg", "restYaw", "noseDeg") else 2
            cells.append("%s / %s / %s" % (fnum(o, nd), fnum(mv, nd), fnum(gv, nd)))
        d = fnum(r.get("D"), 2) if r["converged"] else "n/c"
        out.append("| " + " | ".join(cells) + " | " + d + " |")
    return "\n".join(out)


def write_md(out, P, rows, thresholds, ranked, calib, variants):
    L = []
    w = L.append
    w("# Reference-engine comparison: our engine against MuJoCo")
    w("")
    w("Generated by `make mjref` (tools/mjref). Ours is core/world on the flat plane with the turf's")
    w("dig and bite off (\"mech\"), the mechanics MuJoCo can model; \"game\" is the surface as played")
    w("(texture, dig, bite; ground seed 1), shown for context. Cells read ours / MuJoCo / game.")
    w("D is the case's divergence (0 same, 1 every metric a full scale apart) over the metrics")
    w("MuJoCo agrees with itself on across its four solver variants; n/c: none, or a discrete")
    w("outcome in doubt, so the case is left out.")
    w("")
    w("## Contact parameters")
    w("")
    w("MuJoCo: elliptic friction cones, impratio 10, Newton solver (200 iterations, tolerance 1e-12),")
    w("implicitfast integrator, an explicit contact pair for every pair of geoms. solimp `%s`." % calib["solimp"])
    w("Ground pairs: friction mu of the surface; a baton's pair has condim 6 with torsional")
    w("friction roll x batonTurnHold and rolling friction roll (both lengths, as surf.roll is).")
    w("Boxes on the ground and every pair of pieces: condim 3, pairMu.")
    w("")
    w("| variant | dt (s) | solref timeconst (s) | dampratio e=0.02 | e=0.03 | e=0.15 | pair e=0.35 |")
    w("|---|---|---|---|---|---|---|")
    for v in variants:
        dr = calib["dampratio"][v]
        w("| %s | 1/%d | %g | %.3f | %.3f | %.3f | %.3f |" % (v, round(1 / calib["dt"][v]), calib["timeconst"][v],
                                                              dr["0.02"], dr["0.03"], dr["0.15"], dr["0.35"]))
    w("")
    w("Restitution was mapped by bisection on the damping ratio: a kubb lying flat landing at 2 m/s")
    w("on the ground (or on a fixed box, for pairE) must rebound at e times its impact speed.")
    w("Drop checks (rebound from the bounce's height; ours / MuJoCo ref / game, target e):")
    w("")
    w("| drop | v (m/s) | target e | e ours | e MuJoCo | e game |")
    w("|---|---|---|---|---|---|")
    for r in rows:
        if r["scen"] == "drop":
            surf = r["id"].split("-")[2]
            e = P["surfaces"][surf]["e"]
            res = r["res"]
            w("| %s | %g | %.2f | %s | %s | %s |" % (r["group"], r["params"]["v"], e,
                                                      fnum(res["mech"] and res["mech"]["e"], 3),
                                                      fnum(res["ref"] and res["ref"]["e"], 3),
                                                      fnum(res["game"] and res["game"]["e"], 3)))
    w("")
    w("## Convergence")
    w("")
    by = defaultdict(lambda: [0, 0, defaultdict(int)])
    for r in rows:
        e = by[r["scen"]]
        e[0] += 1
        e[1] += r["converged"]
        for nm in r["unconverged"]:
            e[2][nm] += 1
    w("A metric converges when its spread over the four MuJoCo variants is within half its scale")
    w("(a discrete one: all four agree), or when all four sit on the same side of ours with a spread")
    w("under half their distance from it. A case's D uses, per metric, the variant nearest ours.")
    w("Counts of cases whose metric did not converge:")
    w("")
    w("| scenario | cases | counted | unconverged metrics |")
    w("|---|---|---|---|")
    for s, (n, c, u) in by.items():
        w("| %s | %d | %d | %s |" % (s, n, c, ", ".join("%s %d" % kv for kv in sorted(u.items(), key=lambda kv: -kv[1]))))
    w("")
    w("## Ranked divergences")
    w("")
    w("| rank | scenario | group | cases (conv.) | D mech | D game | largest parts |")
    w("|---|---|---|---|---|---|---|")
    for i, r in enumerate(ranked, 1):
        top = ", ".join("%s %.2f" % kv for kv in r.get("top", []))
        w("| %d | %s | %s | %d (%d) | %s | %s | %s |" % (i, r["scen"], r["group"], r["n"], r["conv"],
                                                        fnum(r["D"], 2), fnum(r.get("Dgame"), 2), top))
    w("")
    w("## Tip thresholds")
    w("")
    w("The smallest blow J (N s, a grid 8 percent apart) that topples a standing kubb, by the")
    w("height it is struck at; pivot is the rigid-pivot estimate sqrt(2 I_edge dE) / h.")
    w("")
    w("| group | ours | MuJoCo | game | pivot | ours/MuJoCo | MuJoCo variants |")
    w("|---|---|---|---|---|---|---|")
    for t in thresholds:
        w("| %s | %s | %s | %s | %.3f | %s | %s |" % (t["group"], fnum(t["mech"]), fnum(t["ref"]), fnum(t["game"]),
                                                     t["pivot"], fnum(t.get("ratio"), 2),
                                                     " ".join(fnum(t[v]) for v in variants)))
    w("")
    w("## Sweeps")
    names = {
        "landing": (["apex", "spinKept", "speedKept", "reboundDeg", "runOn"], ["phi", "gap"]),
        "broadside": (["toppled", "peakTilt", "travel", "batonBack"], ["h", "v"]),
        "king": (["toppled", "peakTilt", "travel", "batonBack"], ["h", "v"]),
        "endon": (["first", "toppled", "peakTilt", "travel"], ["short", "phi"]),
        "domino": (["bToppled", "cToppled", "bTilt"], ["J"]),
        "drill": (["landY", "noseDeg", "apex", "runOn", "fromMark", "pose"], ["taps", "nose"]),
        "flight": (["crossY", "crossT"], ["v"]),
    }
    for scen, (nm, keys) in names.items():
        w("")
        w("### " + scen)
        w("")
        w("Metrics: " + "; ".join("%s: %s" % (n, SCALES[n][2]) for n in nm) + ".")
        gs = defaultdict(list)
        for r in rows:
            if r["scen"] == scen:
                gs[r["group"]].append(r)
        for g, rs in gs.items():
            conv = [r for r in rs if r["converged"]]
            first = next((r for r in rs if r["converged"] and r["D"] > 0.3), None)
            w("")
            w("**%s**%s" % (g, (" (first D > 0.3 at %s)" % ", ".join(
                "%s %s" % (k, r_) for k, r_ in ((k, first["params"][k]) for k in keys))) if first else ""))
            w("")
            w(sweep_table(rs, nm, keys))
            if scen == "flight":
                w("")
                w("flight.carry, the aim's arithmetic (crossY, crossT): " + "; ".join(
                    "v %g: %.3f m, %.3f s" % (r["params"]["v"], r["extra"]["carryR"], r["extra"]["carryT"]) for r in rs))
    open(os.path.join(out, "report.md"), "w").write("\n".join(L) + "\n")


if __name__ == "__main__":
    main()
