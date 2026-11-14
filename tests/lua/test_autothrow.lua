-- core/autothrow: the kitchen inkast and the baton's nearest stance.
import "core/tw"
import "core/autothrow"

local autothrow = tw.autothrow

local function toss(pieces)
	return { kind = "toss", side = "A", pieces = pieces or {}, lineY = 0, forwardY = 0 }
end

test("tosses go to the kitchen with more field kubbs near it", function()
	local t = autothrow.tune
	local s = toss {
		{ id = "f1", kind = "kubb", role = "field", half = "B", x = 1.8, y = 4.9 },
		{ id = "f2", kind = "kubb", role = "field", half = "B", x = 2.1, y = 5.3 },
		{ id = "f3", kind = "kubb", role = "field", half = "B", x = -1.9, y = 4.8 },
		-- the thrower's own half does not count
		{ id = "f4", kind = "kubb", role = "field", half = "A", x = -1.9, y = 4.6 },
		{ id = "f5", kind = "kubb", role = "field", half = "A", x = -1.7, y = 4.5 },
	}
	expect.eq(autothrow.kitchen(s, autothrow.rng(1)), 1)
	-- with no scatter the aim lands in that corner, past the centre line
	local a = autothrow.choose(s, autothrow.rng(1), 0)
	local lx = a.x + math.sin(a.swivel) * 1
	expect.truthy(a.swivel > 0, "aims right")
	expect.truthy(lx > a.x, "toward +x")
	expect.near(a.loftDeg, t.tossLoft, 1e-9)
end)

test("an empty far half: either kitchen, about half each", function()
	local r, right = autothrow.rng(7), 0
	for _ = 1, 200 do
		if autothrow.kitchen(toss(), r) == 1 then right = right + 1 end
	end
	expect.truthy(right > 70 and right < 130, "right " .. right)
end)

test("kitchen tosses stay in the far half near a sideline", function()
	local t = autothrow.tune
	local r = autothrow.rng(3)
	for _ = 1, 100 do
		local a = autothrow.choose(toss(), r, 0)
		-- the aim point (scatter off): kitchenX across, kitchenY - tossRoll along
		local d = (t.kitchenY - t.tossRoll)
		local ax = math.tan(a.swivel) * d
		expect.near(math.abs(ax), t.kitchenX, 1e-6)
	end
end)

test("a baton never stands nearer its target than minRange", function()
	local t = autothrow.tune
	local s = { kind = "baton", side = "A", lineY = 0, forwardY = 3.6, targets = { "f1" },
		pieces = { { id = "f1", kind = "kubb", role = "field", half = "B", x = 1.9, y = 4.6 } } }
	local a = autothrow.choose(s, autothrow.rng(2), 0)
	expect.near(a.y, 4.6 - t.minRange, 1e-9)
	s.forwardY, s.pieces[1].y = 1.0, 6.0
	a = autothrow.choose(s, autothrow.rng(2), 0)
	expect.near(a.y, 1.0, 1e-9)
end)
