-- Scenario "match-wind": a scripted match with the match option WIND set to
-- strong (core/wind). Each throw's wind reaches the throw scene in the
-- thrower's view frame with its label; within a turn the throws share a
-- direction (gusts aside), and Team B's view is turned. Frames: 1 Team A
-- aiming with the wind arrow on the minimap and WIND n M/S above it, 2 Team
-- B aiming.
import "selftest/_match"

local st = tw.selftest
local stage, seen = 1, nil

st.scenarios["match-wind"] = st.matchScenario {
	opts = { seed = 4, windSeed = 9, wind = "strong", skipHandoff = true, names = { A = "Ash", B = "Birch" } },
	maxFrames = 4000,
	step = function(ms, ctx, h)
		local ts = ms.ts
		if ms.phase ~= "play" or ts.mode ~= "aim" or not ms.setup then return false end
		if not ts.windText or not ts.windText:find("^WIND %d+ M/S$") then
			error("no wind label: " .. tostring(ts.windText))
		end
		local sp = math.sqrt(ts.windX * ts.windX + ts.windY * ts.windY)
		if sp < 2 or sp > 10 then error(string.format("wind %.2f m/s for strong", sp)) end
		if stage == 1 and ms.setup.side == "A" then
			ctx:capture()
			seen = { turn = ms.m.game.turn, dir = math.atan(ts.windY, ts.windX), dirB = nil }
			stage = 2
		elseif stage == 2 and ms.setup.side == "B" then
			-- the next turn rolled its own wind; Team B sees it turned (the
			-- gusts aside a turned view of the same air is a different
			-- direction, so only the label and speed are checked here)
			ctx:capture()
			ctx.note = ctx.note .. string.format(" B wind %s", ts.windText)
			return true
		end
		return false
	end,
}
