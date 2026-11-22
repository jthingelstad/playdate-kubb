-- device/namepick: the Names screen's state and the fallback for typed names kept
-- from older builds (kubb-engine docs/NAMES.md).
import "device/namepick"
local np, namegen = tw.namepick, tw.namegen

local function seq(...)
	local list, i = { ... }, 0
	return function(n) i = i % #list + 1; return math.min(n, list[i]) end
end

test("namepick: a name of the kind is kept, anything else is rolled", function()
	local p = np.new("player", "Mighty Maple", seq(1))
	expect.eq(np.text(p), "Mighty Maple")
	local s = np.slots(p)
	expect.eq(s[1], "Mighty"); expect.eq(s[2], "Maple")
	local q = np.new("player", "Kim", seq(3, 7, 11))
	expect.truthy(namegen.valid("player", np.text(q)), "rolled " .. tostring(np.text(q)))
	expect.eq(np.set(q, "Montgomery"), false)
	expect.eq(np.set(q, "Mighty Maple"), true)
	expect.eq(np.text(q), "Mighty Maple")
end)

test("namepick: a step moves one word and always makes a name", function()
	local p = np.new("player", "Mighty Maple", seq(1))
	for i = 1, 2 do
		for _, d in ipairs { 1, -1 } do
			for _ = 1, 60 do
				local before = np.slots(p)
				np.step(p, i, d)
				local after = np.slots(p)
				expect.truthy(namegen.valid("player", np.text(p)), np.text(p))
				expect.eq(after[3 - i], before[3 - i], "the other word")
			end
		end
	end
end)

test("namepick: a team's first word reaches The, the adjectives and the woods", function()
	local p = np.new("team", "The Lumberjacks", seq(1))
	expect.eq(np.slots(p)[1], "The")
	local shapes = {}
	for _ = 1, 400 do
		np.step(p, 1, 1)
		expect.truthy(namegen.valid("team", np.text(p)), np.text(p))
		expect.eq(np.slots(p)[2], "Lumberjacks", "the noun kept")
		shapes[p.parts.shape] = true
	end
	expect.truthy(shapes.the and shapes.adj and shapes.wood, "all three shapes")
	-- and back, then the noun row
	np.step(p, 1, -1)
	np.step(p, 2, 1)
	expect.truthy(np.slots(p)[2] ~= "Lumberjacks", "the noun moved")
	expect.truthy(namegen.valid("team", np.text(p)))
end)

test("namepick: shuffle rolls a new name of the kind", function()
	local p = np.new("team", "Wobbly Towers", seq(1))
	np.shuffle(p, seq(50, 9, 21, 4))
	expect.truthy(namegen.valid("team", np.text(p)))
end)

test("namepick: fallback keeps a generated name and replaces a typed one, the same each time", function()
	expect.eq(np.fallback("player", "Lucky Larch", 1), "Lucky Larch")
	local a = np.fallback("player", "Kim", np.seedOf("p1"))
	expect.truthy(namegen.valid("player", a), tostring(a))
	expect.eq(np.fallback("player", "Kim", np.seedOf("p1")), a)
	local t = np.fallback("team", "Snow Kubbs", np.seedOf("A"))
	expect.truthy(namegen.valid("team", t), tostring(t))
	-- a name the caller refuses is rolled past
	local b = np.fallback("player", "Kim", np.seedOf("p1"), function(n) return n == a end)
	expect.truthy(b ~= a and namegen.valid("player", b))
	-- a player name is not a team name (Mighty Maple is no team)
	expect.truthy(np.fallback("team", "Mighty Maple", 3) ~= "Mighty Maple")
end)
