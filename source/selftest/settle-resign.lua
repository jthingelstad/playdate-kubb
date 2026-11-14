-- Scenario "settle-resign": System Menu resign chosen while the defender
-- raises (it holds the Playdate). The engine is driven to turn 3 as in
-- "settle" (B raises a1 and places a2); resign is asked during the raise.
-- It must not resign the attacker: B settles, A's batons are thrown (as
-- misses, through the engine), and when B's own turn comes B resigns, so A
-- wins. First the pass card (PASS + PLAY: the Playdate goes to B, who raises
-- 1 kubb and places 1 punishment kubb, then hands it back to Team A).
-- Frame 1: the pass card, at the resign.
import "selftest/_match"

local st = tw.selftest
local scene = tw.scenes.match

local MISS = {}
local function topple(id) return { toppled = { id } } end
local function land(x, y, a) return { rest = { x = x, y = y, standing = false, angle = a }, moved = {} } end

local stage = 0

st.scenarios["settle-resign"] = st.matchScenario {
	opts = {},
	maxFrames = 400,
	step = function(ms, ctx, h)
		local g = ms.m.game
		if stage == 0 then
			-- to turn 3's raise, through the engine; then let the scene set up
			g:throwBaton(MISS); g:throwBaton(MISS)
			g:throwBaton(topple("a1")); g:throwBaton(topple("a2")); g:throwBaton(MISS); g:throwBaton(MISS)
			g:toss(land(0.6, 6.0, 0.4)); g:toss(land(2.7, 6.0, math.pi / 2)); g:toss(land(2.8, 5.5, 0))
			ms.phase, ms.ts.mode, ms.resolved = "play", "done", true
			stage = 1
		elseif stage == 1 then
			if ms.phase ~= "settle" then error("expected the settle phase, got " .. ms.phase) end
			local c = ms.settleCard
			if not c or c.side ~= "B" or c.raise ~= 1 or c.punish ~= 1 then
				error("expected the pass card to B: 1 to raise, 1 punishment kubb")
			end
			ctx:capture()
			scene.resign(ms)
			stage = 2
		elseif stage == 2 then
			if ms.phase == "over" then error("the resign ended the game during B's raise (" .. tostring(g.winner) .. " won)") end
			-- B settles: raise, then place the punishment kubb at its suggested spot
			if ms.phase == "settle" and h.idle() then h.pressA() end
			if ms.phase == "play" then
				if g.attacker ~= "A" or g.phase ~= "batons" then error("expected A's batons, got " .. g.phase) end
				while g.attacker == "A" and g.phase == "batons" do g:throwBaton(MISS) end
				ms.ts.mode, ms.resolved = "done", true
				stage = 3
			end
		elseif stage == 3 then
			if ms.phase == "over" then
				if g.winner ~= "A" or g.how ~= "resigned" then error("winner " .. tostring(g.winner) .. " by " .. tostring(g.how)) end
				ctx.note = "B resigned on its turn"
				return true
			end
			if ms.phase == "handoff" and h.idle() then h.pressA() end
		end
		return false
	end,
}
