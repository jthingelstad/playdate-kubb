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
			expect.truthy(w.firstHit and b.toppleT >= w.firstHit.t, b.id .. " topples after the first hit")
		end
	end
	expect.truthy(down >= 1, "the bench throw topples a kubb")
end)
