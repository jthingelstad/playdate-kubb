-- device/enginetune: the engine plays the Playdate switches off (docs/notes/performance.md
-- "Engine 0.13 on the device"), and what they do to core/match's raising by side.
import "device/enginetune"
import "core/match"
local cpu, cmatch, et = tw.cpu, tw.match, tw.enginetune

test("enginetune: the Playdate at pro raises apart; club and beginner as the engine has them", function()
	expect.eq(cpu.raising.pro, "apart")
	expect.eq(cpu.raising.club, "apart")
	expect.eq(cpu.raising.beginner, "first")
	expect.eq(cpu.raisePolicy("pro"), "apart")
	-- kept: the advice for a person, and the pro's attacking plays
	expect.eq(cpu.advice, "par")
	expect.eq(cpu.tune.line.pro, 1)
	expect.eq(cpu.tune.depth.pro, 1)
end)

test("enginetune: a person's sides named in raising win over the advice", function()
	local m = cmatch.new { start = { year = 2026, month = 11, day = 21, hour = 12, min = 0 }, mode = "Vs Playdate",
		cpu = { "B" }, raising = { A = et.autoRaising } }
	expect.eq(cmatch.raisePolicy(m, "A"), "apart")
	expect.eq(type(cmatch.raisePolicy(m, "B")), "function")
	m.raising = nil
	expect.eq(cmatch.raisePolicy(m, "A"), "par")
end)

test("enginetune: names reach the generator's 16 letters", function()
	expect.eq(tw.names.max, 16)
	expect.eq(tw.names.finish("Mighty Maple"), "Mighty Maple")
	expect.eq(tw.names.finish("Wonderful Walnut"), "Wonderful Walnut")
end)
