-- Scenario "match-vs": VS PLAYDATE to a winner. The player's throws come from
-- core/autothrow (seed 5), the Playdate's through its own path (the think
-- delay, then autothrow with cpuScatter); every throw is shown at rest at
-- once, and the Playdate raises and places punishment kubbs itself. The
-- hand-off card must never come before the Playdate's turn; before the
-- player's it is passed with A. The Playdate throws at its match option
-- level (COMPUTER: pro) while the System Menu's, the person's, is beginner,
-- and the game file's [Throw Levels] names it. Its game file is gated
-- (file=...).
-- Frames: 1 the Playdate's aim view, 2 the winner card.
import "selftest/_match"

local st = tw.selftest
local shot = false

st.scenarios["match-vs"] = st.matchScenario {
	opts = { vs = "B", seed = 5, cpuSeed = 7, instant = true, maxTurns = 14, cpuThink = 0.12, computer = "pro" },
	refreshRate = 0,
	maxFrames = 30000,
	step = function(ms, ctx, h)
		tw.scenes.throw.level = "beginner" -- the System Menu's: the person's level, not the computer's
		local s, ts = ms.setup, ms.ts
		if ms.phase == "handoff" then
			if s and s.side == "B" then error("a hand-off card before the Playdate's turn") end
			if h.idle() then h.pressA() end
		end
		if ms.cpuAim and ms.cpuAim.plan.level ~= tw.autothrow.cpuLevel("pro") then
			error("the computer ignored its match option level")
		end
		if not shot and ms.phase == "play" and s and s.side == "B" and ts.mode == "aim" and ms.cpuWait > 0.05 then
			ctx:capture()
			shot = true
		end
		if ms.phase == "over" then
			if not ms.file then error("no game file: " .. tostring(ms.fileError)) end
			if ms.cpuThrows < 3 then error("the Playdate threw " .. ms.cpuThrows .. " times") end
			local g = ms.m.game
			if g.teams.B.name ~= "Playdate" or g.teams.A.name ~= "You" then error("team names") end
			local f = playdate.file.open(ms.file)
			local text = f and f:read(4096) or ""
			if f then f:close() end
			if not text:find('%[Throw Levels "[^"]*pro"%]') then error("the game file does not name the computer pro") end
			if not shot then ctx:capture() end
			ctx:capture()
			ctx.note = ctx.note .. string.format(" turns=%d cpu=%d winner=%s file=%s", g.turn, ms.cpuThrows,
				g.winner, ms.file)
			return true
		end
		return false
	end,
}
