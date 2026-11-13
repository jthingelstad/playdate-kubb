-- Raising geometry (II.D) and punishment placement (II.D.11).
import "core/raising"
import "core/rect"
local raising, rect = tw.raising, tw.rect

local KING = { x = 0, y = 4, standing = true, angle = 0 }

local function lying(x, y, a) return { x = x, y = y, standing = false, angle = a or 0 } end
local function standing(x, y) return { x = x, y = y, standing = true, angle = 0 } end
local function ctx(half, others) return { half = half or "B", king = KING, others = others or {} } end

test("rect overlap, touching and distance", function()
	local a = rect.new(0, 0, 0, 0.5, 0.5)
	expect.truthy(rect.overlap(a, rect.new(0.9, 0, 0, 0.5, 0.5)), "overlapping")
	expect.eq(rect.overlap(a, rect.new(1.0, 0, 0, 0.5, 0.5)), false, "touching is not overlapping")
	expect.near(rect.distance(a, rect.new(2, 0, 0, 0.5, 0.5)), 1, 1e-9)
	expect.near(rect.distance(a, rect.new(1.5, 1.5, 0, 0.5, 0.5)), math.sqrt(0.5), 1e-9, "corner to corner")
	-- rotated 45 degrees, its corner reaches 0.707 out
	expect.truthy(rect.overlap(a, rect.new(1.2, 0, math.pi / 4, 0.5, 0.5)), "rotated overlap")
	expect.near(rect.pointDistance(a, 0.2, 0.1), 0, 1e-12, "inside")
end)

test("II.D.1 footprints: each end's square lies just beyond that end", function()
	local f = raising.footprints(lying(0, 6, 0))
	expect.near(f[1].x, 0.11, 1e-12); expect.near(f[1].y, 6, 1e-12)
	expect.near(f[2].x, -0.11, 1e-12)
	expect.truthy(f[1].standing and f[2].standing)
	local g = raising.footprints(lying(1, 6, math.pi / 2))
	expect.near(g[1].x, 1, 1e-12); expect.near(g[1].y, 6.11, 1e-12)
	expect.near(g[2].y, 5.89, 1e-12)
end)

test("II.D.3 free choice: both footprints clear and in bounds", function()
	local d = raising.options(lying(1, 6, 0), ctx())
	expect.eq(d.mode, "choice")
	expect.eq(#d.choices, 2)
end)

test("II.D.3 one end out of bounds: forced onto the other (sideline)", function()
	local d = raising.options(lying(2.42, 6, 0), ctx())  -- +x footprint center at 2.53
	expect.eq(d.mode, "forced")
	expect.eq(d.choices[1].which, 2)
	expect.truthy(d.ends[1].inBounds == false)
end)

test("II.D.3 one end over the centerline: forced into the defender's half", function()
	local d = raising.options(lying(-1, 4.05, math.pi / 2), ctx("B"))  -- -y footprint at 3.94
	expect.eq(d.mode, "forced")
	expect.eq(d.choices[1].which, 1)
	expect.near(d.choices[1].pose.y, 4.16, 1e-9)
end)

test("II.D.4 one end obstructed by the king: raised on the other", function()
	local d = raising.options(lying(0, 4.15, math.pi / 2), ctx("B"))  -- -y footprint 4.005 to 4.075, king to 4.045
	expect.eq(d.ends[2].obstructedBy, "king")
	expect.eq(d.mode, "forced")
	expect.eq(d.choices[1].which, 1)
end)

test("II.D.4 one end obstructed by a stake: raised on the other", function()
	-- along x near the right centerline stake; -x end clear
	local d = raising.options(lying(2.36, 4.03, 0), ctx("B"))
	expect.eq(d.ends[1].obstructedBy, "stake")
	expect.eq(d.mode, "forced")
	expect.eq(d.choices[1].which, 2)
end)

test("II.D.4 one end obstructed by another kubb: raised on the other", function()
	local d = raising.options(lying(1, 6, 0), ctx("B", { { id = "a3", pose = standing(1.15, 6) } }))
	expect.eq(d.ends[1].obstructedBy, "a3")
	expect.eq(d.mode, "forced")
	expect.eq(d.choices[1].which, 2)
end)

test("II.D.5 both ends obstructed: either end, touching the obstruction near its footprint", function()
	local others = { { id = "a1", pose = standing(1.15, 6) }, { id = "a2", pose = standing(0.85, 6) } }
	local c = ctx("B", others)
	local d = raising.options(lying(1, 6, 0), c)
	expect.eq(d.mode, "displaced")
	expect.eq(#d.choices, 2, "the defender picks the end")
	for _, ch in ipairs(d.choices) do
		expect.truthy(ch.displaced)
		expect.eq(raising.obstruction(ch.pose, c), nil, "clear after sliding")
		-- touching: within a millimeter of an obstruction
		local r = raising.kubbRect(ch.pose)
		local near = math.huge
		for _, o in ipairs(others) do near = math.min(near, rect.distance(r, raising.kubbRect(o.pose))) end
		expect.truthy(near < 1e-3, "touching, got " .. near)
		local fp = raising.footprints(lying(1, 6, 0))[ch.which]
		local moved = math.sqrt((ch.pose.x - fp.x) ^ 2 + (ch.pose.y - fp.y) ^ 2)
		expect.truthy(moved < 0.08, "close to its footprint, moved " .. moved)
	end
end)

test("II.D.5 one end out, the other obstructed: forced on the in-bounds end, touching", function()
	local c = ctx("B", { { id = "a1", pose = standing(2.27, 6) } })
	local d = raising.options(lying(2.42, 6, 0), c)
	expect.eq(d.mode, "displaced")
	expect.eq(#d.choices, 1)
	expect.eq(d.choices[1].which, 2)
	expect.truthy(raising.inBounds(d.choices[1].pose, "B"))
end)

test("II.D.2 a kubb standing on an end, 50% in bounds, is not moved", function()
	local d = raising.options(standing(2.5, 6), ctx())   -- center on the sideline: 50% in
	expect.eq(d.mode, "standing")
	expect.near(d.choices[1].pose.x, 2.5, 1e-12)
	expect.eq(raising.options(standing(2.51, 6), ctx()).mode, "out")
end)

test("II.D.3 can a kubb be raised in bounds: either footprint by its center", function()
	expect.truthy(raising.canRaise(lying(2.5, 6, 0), "B"), "the -x footprint is in")
	expect.eq(raising.canRaise(lying(2.6, 6, math.pi / 2), "B"), false, "parallel to the sideline, outside")
	expect.eq(raising.canRaise(lying(0, 3.9, 0), "B"), false, "short of the centerline")
	expect.truthy(raising.canRaise(lying(0, 3.95, math.pi / 2), "B"), "lying across the centerline")
end)

test("II.D.6 a kubb resting on another is lowered to the pitch touching it", function()
	local lower = lying(0, 6, 0)
	local p = raising.lower({ x = 0.02, y = 6.05, standing = false, angle = 0.3, onTop = "b1" }, lower)
	expect.eq(p.onTop, nil)
	expect.eq(p.standing, false)
	local d = rect.distance(raising.kubbRect(p), raising.kubbRect(lower))
	expect.truthy(d < 1e-3, "touching, got " .. d)
	expect.eq(rect.overlap(raising.kubbRect(p), raising.kubbRect(lower)), false)
	expect.truthy(p.y > 6.05, "moved away from the lower kubb's center")
	-- centers on top of each other: slides across the lower kubb's axis
	local q = raising.lower({ x = 0, y = 6, standing = false, angle = 0, onTop = "b1" }, lower)
	expect.near(q.x, 0, 1e-9)
	expect.near(math.abs(q.y - 6), 0.07, 1e-3)
end)

test("auto chooser: apart picks the end away from other kubbs, together the near one", function()
	local c = ctx("B", { { id = "b1", pose = standing(1.4, 6) } })
	local d = raising.options(lying(1, 6, 0), c)
	expect.eq(d.mode, "choice")
	expect.eq(d.choices[raising.choose(d, c, "apart")].which, 2)
	expect.eq(d.choices[raising.choose(d, c, "together")].which, 1)
	expect.eq(raising.choose(d, c, function() return 2 end), 2, "a policy can be a function")
end)

test("II.D.11 punishment placement validity", function()
	local c = ctx("B", { { id = "b1", pose = standing(1, 6) } })
	expect.truthy(raising.punishmentCheck(standing(1, 7), c))
	local ok, why = raising.punishmentCheck(standing(0, 3.5), c)
	expect.eq(ok, false); expect.eq(why, "not in the half")
	ok, why = raising.punishmentCheck(standing(0, 4.3), c)
	expect.eq(why, "closer than a baton length to the king")
	expect.truthy(raising.punishmentCheck(standing(0, 4.4), c), "30 cm edge to edge from the king")
	ok, why = raising.punishmentCheck(standing(2.3, 7.8), c)
	expect.eq(why, "closer than a baton length to a stake")
	ok, why = raising.punishmentCheck(standing(1.03, 6), c)
	expect.eq(why, "overlaps kubb b1")
end)

test("II.D.11 automatic punishment spot is valid and deep in the half", function()
	local c = ctx("A", { { id = "a3", pose = standing(0, 0) } })
	local p = raising.autoPunishment(c)
	expect.truthy(raising.punishmentCheck(p, c))
	expect.truthy(p.y < 1, "deep, near Team A's baseline: y " .. p.y)
	local cands = raising.punishmentCandidates(c)
	expect.truthy(#cands > 100)
	local picked = raising.autoPunishment(c, function(list) return list[1] end)
	expect.eq(picked.x, cands[1].x)
	expect.eq(picked.y, cands[1].y)
end)
