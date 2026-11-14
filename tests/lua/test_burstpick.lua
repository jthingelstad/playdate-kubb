-- core/burstpick: which hit burst a throw shows, and when.
import "core/burstpick"
import "core/world"
import "core/bench"

local pick, world = tw.burstpick, tw.world

local function fake(list)
	local w = { bodies = {}, n = #list }
	for i, b in ipairs(list) do w.bodies[i] = b end
	return w
end

test("burstpick: nothing until the first topple is on screen", function()
	local w = fake { { kind = "baton" }, { kind = "kubb", id = "b3", toppleT = 1.0 } }
	expect.eq(pick.pick(w, 0.99), nil)
	local kind, a, b = pick.pick(w, 1.0)
	expect.eq(kind, "clean")
	expect.eq(a.id, "b3")
	expect.eq(b, nil)
end)

test("burstpick: a miss or a touch that leaves the kubb standing gets nothing", function()
	local w = fake { { kind = "baton" }, { kind = "kubb", id = "b3" }, { kind = "stake", id = "stake1" } }
	expect.eq(pick.pick(w, 10), nil)
end)

test("burstpick: a second kubb inside the window is a double, outside it is not", function()
	local w = fake { { kind = "kubb", id = "b2", toppleT = 1.3 }, { kind = "kubb", id = "b3", toppleT = 1.0 } }
	local kind, a, b = pick.pick(w, 1.0)
	expect.eq(kind, "double")
	expect.eq(a.id, "b3")
	expect.eq(b.id, "b2")
	w.bodies[1].toppleT = 1.0 + pick.tune.window + 0.01
	expect.eq((pick.pick(w, 1.0)), "clean")
end)

test("burstpick: the king toppled is the king burst, first or not", function()
	local w = fake { { kind = "kubb", id = "b3", toppleT = 1.0 }, { kind = "king", id = "king", toppleT = 1.2 } }
	local kind, a = pick.pick(w, 1.0)
	expect.eq(kind, "king")
	expect.eq(a.id, "king")
	w.bodies[1].toppleT = nil
	expect.eq((pick.pick(w, 1.1)), nil)
	expect.eq((pick.pick(w, 1.2)), "king")
end)

test("burstpick: a king that falls after the window is the king burst once it is on screen", function()
	local w = fake { { kind = "kubb", id = "b3", toppleT = 1.0 }, { kind = "king", id = "king", toppleT = 1.5 } }
	expect.eq((pick.pick(w, 1.0)), "clean")
	expect.eq((pick.pick(w, 1.49)), "clean")
	local kind, a = pick.pick(w, 1.5)
	expect.eq(kind, "king")
	expect.eq(a.id, "king")
end)

local function mover(id, touchT, v, extra)
	local b = { kind = "kubb", id = id, touchT = touchT, awake = true, vx = v, vy = 0, vz = 0, wx = 0, wy = 0, wz = 0 }
	for k, x in pairs(extra or {}) do b[k] = x end
	return b
end

test("burstpick: a hard strike is falling at its impact, before the topple is computed", function()
	-- the physics has run to 1.02 s: b3 struck at 1.00 s at 2 m/s, not yet down
	local w = fake { { kind = "baton" }, mover("b3", 1.0, 2.0) }
	w.time = 1.02
	local kind, a, _, sure = pick.pick(w, 1.0)
	expect.eq(kind, "clean"); expect.eq(a.id, "b3"); expect.eq(sure, false)
	-- a soft touch (0.2 m/s) waits for the topple
	local w2 = fake { mover("b3", 1.0, 0.2) }
	w2.time = 1.02
	expect.eq((pick.pick(w2, 1.0)), nil)
	-- a piece already down before the throw never counts, however hard it is hit
	local w3 = fake { mover("d1", 1.0, 3.0, { toppled = true }) }
	w3.time = 1.02
	expect.eq((pick.pick(w3, 1.0)), nil)
	-- once down it is sure; left standing (asleep, no topple) its burst is taken back
	local b = mover("b3", 1.0, 2.0, { toppleT = 1.3 })
	w = fake { b }; w.time = 1.4
	expect.eq(select(4, pick.pick(w, 1.0)), true)
	expect.eq(pick.stoodUp(mover("b3", 1.0, 0, { awake = false }), false), true)
	expect.eq(pick.stoodUp(mover("b3", 1.0, 2.0), false), false)
end)

test("burstpick: the burst comes at the impact, not when the piece is down", function()
	-- b3 struck at 1.00 s, down at 1.35 s
	local w = fake { { kind = "baton" }, { kind = "kubb", id = "b3", touchT = 1.0, toppleT = 1.35 } }
	expect.eq((pick.pick(w, 0.99)), nil)
	expect.eq((pick.pick(w, 1.0)), "clean", "on screen at the impact")
	-- a kubb struck but still standing (and still) gets nothing
	local w2 = fake { { kind = "kubb", id = "b2", touchT = 1.0, awake = false } }
	w2.time = 5
	expect.eq((pick.pick(w2, 5)), nil)
	-- the double's window runs from impact to impact
	local w3 = fake { { kind = "kubb", id = "b3", touchT = 1.0, toppleT = 1.3 },
		{ kind = "kubb", id = "b4", touchT = 1.3, toppleT = 1.9 } }
	local kind, a, b = pick.pick(w3, 1.0)
	expect.eq(kind, "double"); expect.eq(a.id, "b3"); expect.eq(b.id, "b4")
end)

test("burstpick: the physics times a topple (world bodies carry toppleT)", function()
	-- core/bench's scenario: a baton into five field kubbs (it topples one)
	local w = tw.bench.world()
	world.run(w, tw.bench.seconds)
	local down = 0
	for i = 1, w.n do
		local b = w.bodies[i]
		if b.toppled and b.kind == "kubb" then
			down = down + 1
			expect.truthy(b.toppleT and b.toppleT > 0, b.id .. " has a topple time")
			expect.truthy(b.touchT and b.touchT <= b.toppleT, b.id .. " was struck before it fell")
			expect.truthy(w.firstHit and b.toppleT >= w.firstHit.t, b.id .. " topples after the first hit")
		end
	end
	expect.truthy(down >= 1, "the bench throw topples a kubb")
end)

test("burstpick: a king is judged only once it has toppled; pushed, it gets no burst", function()
	local w = fake {
		{ kind = "kubb", id = "b3", toppleT = 1.0 },
		{ kind = "king", id = "king", touchT = 1.1, awake = true, vx = 1, vy = 0, vz = 0, wx = 9, wy = 0, wz = 0 },
	}
	w.time = 1.2
	local kind, a = pick.pick(w, 1.1)
	expect.eq(kind, "clean", "a king struck and moving but not toppled is not the king burst")
	expect.eq(a.id, "b3")
	w.bodies[2].toppleT = 1.15
	local sure
	kind, a, _, sure = pick.pick(w, 1.2)
	expect.eq(kind, "king")
	expect.eq(sure, true)
end)

test("burstpick: a graze then a later topple is timed at the topple", function()
	local b = { kind = "kubb", id = "b2", touchT = 0.3, toppleT = 1.5 }
	expect.eq(pick.hitTime(b), 1.5)
	b.toppleT = 0.5
	expect.eq(pick.hitTime(b), 0.3)
end)

test("burstpick: a double carries the second kubb's own certainty", function()
	local w = fake {
		{ kind = "kubb", id = "b3", toppleT = 1.0 },
		{ kind = "kubb", id = "b2", touchT = 1.1, awake = true, vx = 1, vy = 0, vz = 0, wx = 0, wy = 0, wz = 0 },
	}
	w.time = 1.2
	local kind, a, b, sure, sure2 = pick.pick(w, 1.0)
	expect.eq(kind, "double")
	expect.eq(a.id, "b3")
	expect.eq(b.id, "b2")
	expect.eq(sure, true)
	expect.eq(sure2, false, "the second has not toppled")
	w.bodies[2].toppleT = 1.15
	kind, a, b, sure, sure2 = pick.pick(w, 1.0)
	expect.eq(sure2, true)
end)
