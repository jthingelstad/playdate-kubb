-- Scenario "settle": raising and a punishment kubb by hand (scenes/settle).
-- The engine is driven to turn 3: A tosses a1 into B's half lying (in) and
-- a2 out over the sideline twice, so B raises a1, then places a2 as a
-- punishment kubb. Frames: 1 the raise view on the engine's choice, 2 after
-- the d-pad has looked about (right turns the view round the kubb, down
-- zooms out), 3 the placement view at the engine's suggestion, 4 the cursor
-- moved onto the king's keep-out (refused, with the reason). Then the cursor
-- goes back to the suggestion and A places it; the check: the look turned
-- and zoomed out, a1 stands, a2 is a field kubb in B's half, and the engine
-- is on to A's batons.
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
				{ n = 2 }, { hold = { "right" }, n = 25 }, { hold = { "down" }, n = 25 }, { press = { "a" } },
				{ n = 6 }, { press = { "a" } }, { n = 2 },
			}
			s = settle.new(g, function(side) return side == "A" and "ASH" or "BIRCH" end, steps)
			want = s.choice   -- the engine's own end: the d-pad only looks
		end
		local f = ctx.frame
		if f == 55 then
			-- the cursor onto the king's keep-out, then back
			ctx.back = { s.cx, s.cy }
			s.cx, s.cy, s.check = 0, 3.85, true
		elseif f == 57 then
			s.cx, s.cy, s.check = ctx.back[1], ctx.back[2], true
		end
		settle.update(s)
		settle.draw(s)
		if f == 52 then
			if not (s.yaw > 0.5 and s.zoom > 1.3) then
				error(string.format("the d-pad did not look about: yaw %.2f zoom %.2f", s.yaw, s.zoom))
			end
			if s.choice ~= want then error("the d-pad changed the end") end
		end
		if f == 1 or f == 52 or f == 54 or f == 56 then
			if f == 54 and s.mode ~= "punish" then error("expected the placement view, got " .. tostring(s.mode)) end
			if f == 56 and s.why ~= "TOO NEAR THE KING" then error("expected a refusal by the king, got " .. tostring(s.why)) end
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
		if f > 90 then error("not done by frame 90 (" .. tostring(s.mode) .. ")") end
		return false
	end,
}
