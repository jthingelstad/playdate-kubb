-- Scenario "settle": raising and a punishment kubb by hand (scenes/settle).
-- The engine is driven to turn 3: A tosses a1 into B's half lying (in) and
-- a2 out over the sideline twice, so B raises a1, then places a2 as a
-- punishment kubb. Frames: 1 the raise view on the engine's choice, 2 after
-- right (the other end), 3 the placement view at the engine's suggestion,
-- 4 the cursor moved onto the king's keep-out (refused, with the reason).
-- Then the cursor goes back to the suggestion and A places it; the check:
-- a1 stands at the second end chosen, a2 is a field kubb in B's half, and
-- the engine is on to A's batons.
import "core/tw"
import "core/rules"
import "scenes/settle"
import "input"

local settle, rules = tw.scenes.settle, tw.rules
local s, g, steps, want

local MISS = {}
local function topple(id) return { toppled = { id } } end
local function land(x, y, a) return { rest = { x = x, y = y, standing = false, angle = a }, moved = {} } end

tw.selftest.scenarios.settle = {
	step = function(ctx)
		if not s then
			g = rules.new { teams = { A = { name = "Ash", players = { { name = "Ash" } } },
				B = { name = "Birch", players = { { name = "Birch" } } } } }
			g:throwBaton(MISS); g:throwBaton(MISS)
			g:throwBaton(topple("a1")); g:throwBaton(topple("a2")); g:throwBaton(MISS); g:throwBaton(MISS)
			g:toss(land(0.6, 6.0, 0.4))          -- a1: in, lying
			g:toss(land(2.7, 6.0, math.pi / 2))  -- a2: out over the sideline
			g:toss(land(2.8, 5.5, 0))            -- a2 rethrown: out again, a punishment kubb
			if g:need().kind ~= "raise" then error("expected a raise, got " .. g:need().kind) end
			steps = tw.input.scripted {
				{ n = 2 }, { press = { "right" } }, { n = 2 }, { press = { "a" } }, { n = 3 },
				{ n = 2 }, { press = { "a" } }, { n = 2 },
			}
			s = settle.new(g, function(side) return side == "A" and "ASH" or "BIRCH" end, steps)
			want = s.choice % #s.dec.choices + 1
		end
		local f = ctx.frame
		if f == 9 then
			-- the cursor onto the king's keep-out, then back
			ctx.back = { s.cx, s.cy }
			s.cx, s.cy, s.check = 0, 3.85, true
		elseif f == 11 then
			s.cx, s.cy, s.check = ctx.back[1], ctx.back[2], true
		end
		settle.update(s)
		settle.draw(s)
		if f == 1 or f == 3 or f == 8 or f == 10 then
			if f == 8 and s.mode ~= "punish" then error("expected the placement view, got " .. tostring(s.mode)) end
			if f == 10 and s.why ~= "TOO NEAR THE KING" then error("expected a refusal by the king, got " .. tostring(s.why)) end
			ctx:capture()
		end
		if s.done then
			local a1, a2 = g.kubbs.a1, g.kubbs.a2
			if not a1.pose.standing then error("a1 was not raised") end
			if a2.where ~= "pitch" or a2.kind ~= "field" or a2.half ~= "B" then error("a2 was not placed") end
			if g.phase ~= "batons" then error("engine phase " .. g.phase) end
			ctx.note = "end " .. want
			return true
		end
		if f > 40 then error("not done by frame 40 (" .. tostring(s.mode) .. ")") end
		return false
	end,
}
