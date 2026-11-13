-- Scenario "match-opening": the first turn of each side, thrown with the
-- crank, and the hand-off between them. Team A throws its two opening
-- batons (2-4-6), the card hands the Playdate to Team B, and Team B throws
-- its first baton from its own baseline (the pitch turned 180 degrees).
-- Frames: 1 Team A's hand-off card, 2 Team A aiming, 3 Team A's first baton
-- at rest with its result line, 4 Team B's hand-off card, 5 Team B aiming
-- (A's base kubbs now at the far end), 6 Team B's baton at rest.
import "selftest/_match"
import "selftest/_throw"

local st = tw.selftest

local function crankThrow()
	return {
		{ n = 5 },
		st.windup(120, 30),
		{ n = 5 },
		st.flick { 6, 12, 18, 22, 24, 24, 24 },
	}
end

local shots, stage = 0, 1
local restAt = nil

st.scenarios["match-opening"] = st.matchScenario {
	opts = {},
	maxFrames = 1500,
	step = function(ms, ctx, h)
		local ts = ms.ts
		local function shot() ctx:capture(); shots = shots + 1 end
		if stage == 1 then
			-- Team A's card
			if ms.phase ~= "handoff" or ms.side ~= "A" then error("expected Team A's hand-off, got " .. ms.phase) end
			local err = st.pitchMatchesEngine(ms)
			if err then error(err) end
			shot()
			h.pressA()
			stage = 2
		elseif stage == 2 and ms.phase == "play" and ts.mode == "aim" and h.idle() then
			shot()
			h.feed(crankThrow())
			stage = 3
		elseif stage == 3 then
			if ts.mode == "rest" and not restAt then restAt = ctx.frame end
			if restAt and ctx.frame == restAt + 20 then
				if not ms.result then error("no result line") end
				shot()
				stage = 4
			end
		elseif stage == 4 and ms.phase == "play" and ts.mode == "aim" and h.idle() then
			-- A's second baton
			if ms.setup.n ~= 2 then error("expected baton 2, got " .. tostring(ms.setup.n)) end
			h.feed(crankThrow())
			stage = 5
		elseif stage == 5 and ms.phase == "handoff" then
			if ms.side ~= "B" then error("hand-off to " .. tostring(ms.side)) end
			local b = ms.m.game.sheet.turns[1].batons
			if #b ~= 2 then error("turn 1 has " .. #b .. " batons") end
			local err = st.pitchMatchesEngine(ms)
			if err then error(err) end
			shot()
			h.pressA()
			stage = 6
		elseif stage == 6 and ms.phase == "play" and ts.mode == "aim" and h.idle() then
			-- Team B's view: A's base kubbs (world y = 0) are at the far end,
			-- mirrored across the middle
			local g = ms.m.game
			for i = 1, ts.nitems do
				local it = ts.items[i]
				local k = g.kubbs[it.id]
				if k and k.half == "A" and k.kind == "base" and k.where == "pitch" then
					if math.abs(it.y - (8 - k.pose.y)) > 1e-3 or math.abs(it.x + k.pose.x) > 1e-3 then
						error(string.format("%s shown at (%.2f, %.2f) for Team B", it.id, it.x, it.y))
					end
				end
			end
			-- a toss first when A's batons toppled any of B's kubbs
			local want = ms.setup.kind == "toss" and "^Team B  kubb 1 of %d$" or "^Team B  baton 1 of 4$"
			if not ms.setup.label:match(want) then error("label " .. ms.setup.label) end
			shot()
			h.feed(crankThrow())
			restAt = nil
			stage = 7
		elseif stage == 7 then
			if ts.mode == "rest" and not restAt then restAt = ctx.frame end
			if restAt and ctx.frame == restAt + 20 then
				shot()
				if ms.throws ~= 3 then error(ms.throws .. " throws resolved") end
				if ms.m.game.turn ~= 2 or ms.m.game.attacker ~= "B" then error("not Team B's turn 2") end
				return true
			end
		end
		return false
	end,
}
