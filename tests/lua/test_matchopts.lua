-- core/matchopts: the match options chosen before each match.
import "core/matchopts"
import "core/match"
import "core/save"
local matchopts, match, save = tw.matchopts, tw.match, tw.save

test("matchopts: defaults are grass, 2-4-6 and raising by hand", function()
	local c = matchopts.defaults()
	local o = matchopts.apply({}, c)
	expect.eq(o.surface, "Grass"); expect.eq(o.opening, "2-4-6"); expect.eq(o.autoSettle, nil)
end)

test("matchopts: left and right step through a row's values and wrap", function()
	local c = matchopts.defaults()
	expect.eq(matchopts.step(c, "surface", 1), 2); expect.eq(matchopts.value(c, "surface"), "Sand")
	matchopts.step(c, "surface", 1); expect.eq(matchopts.value(c, "surface"), "Snow")
	matchopts.step(c, "surface", 1); expect.eq(matchopts.value(c, "surface"), "Grass")
	matchopts.step(c, "surface", -1); expect.eq(matchopts.value(c, "surface"), "Snow")
	matchopts.step(c, "opening", 1); matchopts.step(c, "raising", -1)
	local o = matchopts.apply({ vs = "B" }, c)
	expect.eq(o.surface, "Snow"); expect.eq(o.opening, "six"); expect.eq(o.autoSettle, true); expect.eq(o.vs, "B")
	expect.eq(matchopts.shown(c, "opening"), "SIX FROM THE START")
end)

test("matchopts: a kept choice is read back, anything odd falls back to the defaults", function()
	expect.eq(matchopts.valid({ surface = 3, opening = 2, raising = 2 }).surface, 3)
	local bad = matchopts.valid({ surface = 9, opening = "x", raising = 1.5 })
	expect.eq(bad.surface, 1); expect.eq(bad.opening, 1); expect.eq(bad.raising, 1)
	expect.eq(matchopts.valid(nil).surface, 1)
end)

test("matchopts: the options reach the engine, and a save keeps the raising", function()
	local o = matchopts.apply({}, { surface = 2, opening = 2, raising = 2 })
	local m = match.new { start = { year = 2026, month = 11, day = 14, hour = 9, min = 0 }, surface = o.surface,
		opening = o.opening }
	expect.eq(m.game.surface, "Sand"); expect.eq(m.game.opening, "six")
	expect.eq(match.setup(m).surface, "sand")
	local d = save.pack(m, { autoSettle = o.autoSettle })
	local back, opts = save.unpack(d)
	expect.eq(opts.autoSettle, true)
	expect.eq(back.game.surface, "Sand"); expect.eq(back.game.opening, "six")
end)

test("matchopts: the kubb set row, and a save keeps the set", function()
	local c = matchopts.defaults()
	expect.eq(matchopts.value(c, "set"), "classic")
	matchopts.step(c, "set", 1); expect.eq(matchopts.value(c, "set"), "usa")
	matchopts.step(c, "set", -2); expect.eq(matchopts.value(c, "set"), "wisconsin")
	expect.eq(matchopts.shown(c, "set"), "WISCONSIN")
	local o = matchopts.apply({}, c)
	expect.eq(o.set, "wisconsin")
	expect.eq(matchopts.valid({ set = 9 }).set, 1)
	local m = match.new { start = { year = 2026, month = 11, day = 14, hour = 9, min = 0 } }
	local _, opts = save.unpack(save.pack(m, { set = "sweden" }))
	expect.eq(opts.set, "sweden")
end)

test("matchopts: the wind row, and a save keeps the wind", function()
	local c = matchopts.defaults()
	expect.eq(matchopts.value(c, "wind"), "off")
	matchopts.step(c, "wind", -1)
	expect.eq(matchopts.value(c, "wind"), "strong")
	expect.eq(matchopts.apply({}, c).wind, "strong")
	local m = match.new { start = { year = 2026, month = 11, day = 14, hour = 9, min = 0 } }
	local _, opts = save.unpack(save.pack(m, { wind = "light" }))
	expect.eq(opts.wind, "light")
end)
