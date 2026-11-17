"""The MuJoCo side of the reference-engine comparison (tools/mjref).

Reads params.json and cases.json (tools/mjref/export.lua), builds one MJCF
model per case from the game's own geometry, masses, inertias and material
numbers, runs it in MuJoCo and writes mj.jsonl: the same trace format as
ours.jsonl (tools/mjref/ours.lua), once per solver variant:

  ref    dt 1/9600 s, solref timeconst 0.002 s (the reference)
  dt2    dt 1/19200 s, timeconst 0.002 s (half the step)
  stiff  dt 1/9600 s, timeconst 0.001 s (stiffer contact)
  soft   dt 1/9600 s, timeconst 0.004 s (softer contact)

Restitution: MuJoCo has no coefficient of restitution. A soft contact is a
damped spring (solref = timeconst, dampratio), and the bounce it gives falls
with the damping ratio. For each variant and each target e (the surfaces' e
and pairE) the damping ratio is found by bisection on a drop test, a kubb
lying flat landing at 2 m/s (calibrate below), and written to calib.json.

  python3 tools/mjref/mjsim.py build/mjref [--only prefix] [--jobs n]
"""
import json
import math
import multiprocessing as mp
import os
import sys
import time

import mujoco
import numpy as np

VARIANTS = {
    "ref": {"dt": 1 / 9600, "tc": 0.002},
    "dt2": {"dt": 1 / 19200, "tc": 0.002},
    "stiff": {"dt": 1 / 9600, "tc": 0.001},
    "soft": {"dt": 1 / 9600, "tc": 0.004},
}
SOLIMP = "0.99 0.999 0.001 0.5 2"
SAMPLE_HZ = 120  # ours.lua writes every second 240 Hz step

P = None  # params.json, set in each process


def fmt(v):
    return " ".join("%.10g" % x for x in v)


def geom_xml(name, kind):
    k = P["kinds"][kind]
    if k["shape"] == "box":
        return '<geom name="%s" type="box" size="%s" contype="0" conaffinity="0"/>' % (
            name, fmt([k["hx"], k["hy"], k["hz"]]))
    return '<geom name="%s" type="capsule" size="%s" fromto="0 0 %.10g 0 0 %.10g" contype="0" conaffinity="0"/>' % (
        name, fmt([k["r"]]), -k["hl"], k["hl"])


def build(case, var, calib, static_box=False):
    """The MJCF of a case: the ground plane, a free body per piece, and an
    explicit contact pair for every pair of geoms that can meet."""
    surf = P["surfaces"][case["surface"]]
    w = P["world"]
    dr = calib[var]
    tc = VARIANTS[var]["tc"]
    bodies = []
    for b in case["bodies"]:
        k = P["kinds"][b["kind"]]
        bodies.append(
            '<body name="%s" pos="%s" quat="%s"><freejoint/>'
            '<inertial pos="0 0 0" mass="%.10g" diaginertia="%s"/>%s</body>'
            % (b["id"], fmt(b["pos"]), fmt(b["quat"]), k["mass"], fmt(k["inertia"]), geom_xml("g_" + b["id"], b["kind"])))
    if static_box:
        kb = P["kinds"]["kubb"]
        bodies.append('<geom name="g_static" type="box" pos="0 1 %.10g" size="%s" contype="0" conaffinity="0"/>' % (
            -kb["hz"], fmt([0.3, 0.3, kb["hz"]])))
    pairs = []
    ground_e = "%.6g" % surf["e"]
    pair_e = "%.6g" % w["pairE"]
    for b in case["bodies"]:
        g = "g_" + b["id"]
        if static_box:
            pairs.append('<pair geom1="%s" geom2="g_static" condim="3" friction="%s" solref="%.6g %.10g" solimp="%s"/>' % (
                g, fmt([w["pairMu"], w["pairMu"], 0, 0, 0]), tc, dr[pair_e], SOLIMP))
            continue
        if b["kind"] == "baton":
            roll = surf["roll"]
            fr = [surf["mu"], surf["mu"], roll * w["batonTurnHold"], roll, roll]
            pairs.append('<pair geom1="%s" geom2="floor" condim="6" friction="%s" solref="%.6g %.10g" solimp="%s"/>' % (
                g, fmt(fr), tc, dr[ground_e], SOLIMP))
        else:
            pairs.append('<pair geom1="%s" geom2="floor" condim="3" friction="%s" solref="%.6g %.10g" solimp="%s"/>' % (
                g, fmt([surf["mu"], surf["mu"], 0, 0, 0]), tc, dr[ground_e], SOLIMP))
    ids = [b["id"] for b in case["bodies"]]
    for i in range(len(ids)):
        for j in range(i + 1, len(ids)):
            pairs.append('<pair geom1="g_%s" geom2="g_%s" condim="3" friction="%s" solref="%.6g %.10g" solimp="%s"/>' % (
                ids[i], ids[j], fmt([w["pairMu"], w["pairMu"], 0, 0, 0]), tc, dr[pair_e], SOLIMP))
    return """<mujoco>
<option timestep="%.10g" gravity="0 0 -%.10g" cone="elliptic" impratio="10" solver="Newton"
  iterations="200" ls_iterations="50" tolerance="1e-12" integrator="implicitfast">
  <flag gravity="enable"/>
</option>
<worldbody>
<geom name="floor" type="plane" size="0 0 1" contype="0" conaffinity="0"/>
%s
</worldbody>
<contact>%s</contact>
</mujoco>""" % (VARIANTS[var]["dt"], w["g"], "\n".join(bodies), "\n".join(pairs))


def set_state(m, d, case):
    for i, b in enumerate(case["bodies"]):
        adr = m.jnt_qposadr[i]
        vadr = m.jnt_dofadr[i]
        d.qpos[adr:adr + 3] = b["pos"]
        d.qpos[adr + 3:adr + 7] = b["quat"]
        R = np.zeros(9)
        mujoco.mju_quat2Mat(R, np.array(b["quat"], dtype=float))
        R = R.reshape(3, 3)
        d.qvel[vadr:vadr + 3] = b["vel"]
        # a free joint's angular velocity is in the body's own frame
        d.qvel[vadr + 3:vadr + 6] = R.T @ np.array(b["angvel"], dtype=float)
    mujoco.mj_forward(m, d)


def contacts(m, d, gids, floor):
    """Per body: touching the ground; and whether the projectile touches anything."""
    ground = [False] * len(gids)
    anyc = [False] * len(gids)
    with_ = [None] * len(gids)
    for c in d.contact[:d.ncon]:
        if c.dist > 0:
            continue
        for k, g in enumerate(gids):
            if c.geom1 == g or c.geom2 == g:
                other = c.geom2 if c.geom1 == g else c.geom1
                anyc[k] = True
                if other == floor:
                    ground[k] = True
                    with_[k] = with_[k] or "ground"
                else:
                    with_[k] = with_[k] or other
    return ground, anyc, with_


def simulate(case, var, calib):
    m = mujoco.MjModel.from_xml_string(build(case, var, calib))
    d = mujoco.MjData(m)
    set_state(m, d, case)
    w = P["world"]
    dt = VARIANTS[var]["dt"]
    per = int(round(1 / (SAMPLE_HZ * dt)))
    nb = len(case["bodies"])
    gids = [mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_GEOM, "g_" + b["id"]) for b in case["bodies"]]
    gname = {g: b["id"] for g, b in zip(gids, case["bodies"])}
    floor = mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_GEOM, "floor")
    proj = next((i for i, b in enumerate(case["bodies"]) if b.get("projectile")), None)
    pb = proj + 1 if proj is not None else None
    dragK = P["dragK"][case["bodies"][proj]["kind"]] if proj is not None else 0
    aeroK = w["aeroK"] if proj is not None and case["bodies"][proj].get("aero") else 0
    mass = [P["kinds"][b["kind"]]["mass"] for b in case["bodies"]]
    first_contact = None
    first_hit = None
    traces = [[] for _ in range(nb)]
    pressed = [False] * nb
    rest_for = 0.0

    def sample():
        for k in range(nb):
            bi = k + 1
            adr = m.jnt_qposadr[k]
            vadr = m.jnt_dofadr[k]
            R = d.xmat[bi].reshape(3, 3)
            wv = R @ d.qvel[vadr + 3:vadr + 6]
            q = d.qpos[adr + 3:adr + 7]
            traces[k].extend([*d.qpos[adr:adr + 3], *q, *d.qvel[vadr:vadr + 3], *wv, 1 if pressed[k] else 0])
            pressed[k] = False

    sample()
    steps = int(round(case["duration"] / dt))
    s = 0
    while s < steps:
        if pb is not None and first_contact is None:
            # the air's drag and turn on the projectile until its first contact,
            # as world.airDrag and world.aeroTurn (recomputed every step)
            vadr = m.jnt_dofadr[proj]
            v = d.qvel[vadr:vadr + 3].copy()
            sp = float(np.linalg.norm(v))
            f = -mass[proj] * dragK * sp * v
            tq = np.zeros(3)
            if aeroK:
                z = d.xmat[pb].reshape(3, 3)[:, 2]
                tq = aeroK * float(v @ z) * np.cross(v, z)
            d.xfrc_applied[pb, :3] = f
            d.xfrc_applied[pb, 3:] = tq
            mujoco.mj_step(m, d)
            s += 1
        else:
            if pb is not None:
                d.xfrc_applied[pb, :] = 0
            mujoco.mj_step(m, d)
            s += 1
        ground, anyc, with_ = contacts(m, d, gids, floor)
        for k in range(nb):
            if ground[k]:
                pressed[k] = True
        if proj is not None and anyc[proj]:
            wth = with_[proj]
            name = "ground" if wth == "ground" else gname.get(wth, "other")
            if first_contact is None:
                first_contact = {"t": d.time, "with": name, "x": float(d.xpos[pb][0]), "y": float(d.xpos[pb][1]),
                                 "z": float(d.xpos[pb][2])}
            if first_hit is None and name != "ground":
                first_hit = {"t": d.time, "with": name}
            elif first_hit is None:
                for c in d.contact[:d.ncon]:
                    if c.dist <= 0 and gids[proj] in (c.geom1, c.geom2):
                        o = c.geom2 if c.geom1 == gids[proj] else c.geom1
                        if o != floor:
                            first_hit = {"t": d.time, "with": gname.get(o, "other")}
                            break
        if s % per == 0:
            sample()
            # at rest: every body slower than the game's sleep thresholds for its sleep time
            calm = True
            for k in range(nb):
                vadr = m.jnt_dofadr[k]
                if np.linalg.norm(d.qvel[vadr:vadr + 3]) >= w["sleepLin"] or np.linalg.norm(
                        d.qvel[vadr + 3:vadr + 6]) >= w["sleepAng"]:
                    calm = False
                    break
            rest_for = rest_for + per * dt if calm else 0.0
            if rest_for >= w["sleepTime"]:
                break
    return {
        "id": case["id"], "variant": var, "dt": per * dt, "steps": s,
        "firstContact": first_contact or False, "firstHit": first_hit or False,
        "ids": [b["id"] for b in case["bodies"]], "traces": [[float("%.6g" % x) for x in t] for t in traces],
    }


# ---------------------------------------------------------------------------
# Restitution calibration

def drop_bounce(var, dr, e_key, v0=2.0, on_box=False, kind="kubb"):
    """The bounce (rebound vz over impact vz) of a flat piece landing at v0:
    the mean over four starting gaps a quarter step apart, as the bounce of a
    soft contact a few steps long depends a little on where in a step it starts."""
    dt = VARIANTS[var]["dt"]
    return sum(drop_bounce1(var, dr, e_key, v0, on_box, kind, 0.0005 + v0 * dt * i / 4) for i in range(4)) / 4


def drop_bounce1(var, dr, e_key, v0, on_box, kind, gap):
    k = P["kinds"][kind]
    half = k["hy"] if k["shape"] == "box" else k["r"]
    base = 0.0
    case = {"surface": "grass", "bodies": [{
        "id": "k", "kind": kind, "pos": [0, 1, base + half + gap], "quat": [0.5, 0.5, 0.5, 0.5],
        "vel": [0, 0, -v0], "angvel": [0, 0, 0]}]}
    calib = {var: {e_key: dr, ("%.6g" % P["surfaces"]["grass"]["e"]): dr, ("%.6g" % P["world"]["pairE"]): dr}}
    m = mujoco.MjModel.from_xml_string(build(case, var, calib, static_box=on_box))
    d = mujoco.MjData(m)
    set_state(m, d, case)
    # the bounce from its height, as compare.py measures it: rebound speed
    # sqrt(2 g rise), rise from where it comes to rest (a soft contact rests a
    # little sunk) to the top of the bounce
    vin = None
    top = -1e9
    while d.time < 0.4:
        vz_before = d.qvel[2]
        mujoco.mj_step(m, d)
        if vin is None and d.ncon > 0:
            vin = -vz_before
        if vin is not None:
            top = max(top, d.qpos[2])
    rise = max(0.0, top - d.qpos[2])
    return math.sqrt(2 * P["world"]["g"] * rise) / vin


def calibrate_one(args):
    var, e_target, pair = args
    key = "%.6g" % e_target
    lo, hi = 0.01, 10.0
    for _ in range(40):
        mid = 0.5 * (lo + hi)
        e = drop_bounce(var, mid, key, on_box=pair)
        if e > e_target:
            lo = mid
        else:
            hi = mid
    dr = 0.5 * (lo + hi)
    return var, key, dr, drop_bounce(var, dr, key, on_box=pair)


def init(params):
    global P
    P = params


def run_one(args):
    case, var, calib = args
    try:
        return simulate(case, var, calib)
    except Exception as ex:  # a case that fails to build or run is reported, not fatal
        return {"id": case["id"], "variant": var, "error": repr(ex)}


def main():
    out = sys.argv[1]
    only = None
    jobs = os.cpu_count() or 4
    a = sys.argv[2:]
    while a:
        if a[0] == "--only":
            only = a[1]
            a = a[2:]
        elif a[0] == "--jobs":
            jobs = int(a[1])
            a = a[2:]
        else:
            raise SystemExit("unknown option " + a[0])
    params = json.load(open(os.path.join(out, "params.json")))
    cases = json.load(open(os.path.join(out, "cases.json")))
    if only:
        cases = [c for c in cases if c["id"].startswith(only)]
    init(params)
    t0 = time.time()
    targets = sorted({s["e"] for s in params["surfaces"].values()})
    jobs_c = [(v, e, False) for v in VARIANTS for e in targets] + [(v, params["world"]["pairE"], True) for v in VARIANTS]
    calib = {v: {} for v in VARIANTS}
    check = {v: {} for v in VARIANTS}
    with mp.Pool(jobs, initializer=init, initargs=(params,)) as pool:
        for var, key, dr, e in pool.map(calibrate_one, jobs_c):
            calib[var][key] = dr
            check[var][key] = e
        # a pair calibration shares the key of an equal ground e only if equal: pairE differs here
        t1 = time.time()
        work = [(c, v, calib) for c in cases for v in VARIANTS]
        results = pool.map(run_one, work, chunksize=4)
    t2 = time.time()
    json.dump({"dampratio": calib, "bounce": check, "solimp": SOLIMP,
               "timeconst": {v: VARIANTS[v]["tc"] for v in VARIANTS},
               "dt": {v: VARIANTS[v]["dt"] for v in VARIANTS},
               "seconds": {"calibrate": t1 - t0, "simulate": t2 - t1}}, open(os.path.join(out, "calib.json"), "w"),
              indent=1)
    with open(os.path.join(out, "mj.jsonl"), "w") as f:
        for r in results:
            f.write(json.dumps(r, separators=(",", ":")) + "\n")
    errs = [r for r in results if "error" in r]
    print("mjsim: %d cases x %d variants in %.1f s (calibration %.1f s), %d errors -> %s/mj.jsonl" % (
        len(cases), len(VARIANTS), t2 - t0, t1 - t0, len(errs), out))
    for r in errs[:5]:
        print("  error", r["id"], r["variant"], r["error"])


if __name__ == "__main__":
    main()
