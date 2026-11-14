-- Scenario "settle-crank": raising a kubb with the crank (scenes/settle).
-- The engine is driven to B's raise of a1 as in "settle"; the crank turns
-- forward 10 degrees a frame. Frame 1: half way (the kubb part way up on its
-- right-hand end); then on to all the way, which raises it. The check: a1
-- stands on the footprint of the end that showed on the right.
import "core/tw"
import "core/rules"
import "core/raising"
import "scenes/settle"
import "input"

local settle, rules, raising = tw.scenes.settle, tw.rules, tw.raising
local s, g, endRight, shot

local MISS = {}
local function topple(id) return { toppled = { id } } end
local function land(x, y, a) return { rest = { x = x, y = y, standing = false, angle = a }, moved = {} } end

tw.selftest.scenarios["settle-crank"] = {
	step = function(ctx)
		if not s then
			g = rules.new { teams = { A = { name = "Ash", players = { { name = "Ash" } } },
				B = { name = "Birch", players = { { name = "Birch" } } } } }
			g:throwBaton(MISS); g:throwBaton(MISS)
			g:throwBaton(topple("a1")); g:throwBaton(topple("a2")); g:throwBaton(MISS); g:throwBaton(MISS)
			g:toss(land(0.6, 6.0, 0.4)); g:toss(land(2.7, 6.0, math.pi / 2)); g:toss(land(2.8, 5.5, 0))
			local sign = tw.swing.tune.forwardSign
			s = settle.new(g, function(side) return side == "A" and "ASH" or "BIRCH" end,
				tw.input.scripted { { n = 2 }, { crank = 10 * sign, n = 40 } })
			endRight = s.rightEnd
			ctx.lying = raising.copyPose(g.kubbs.a1.pose)
		end
		settle.update(s)
		settle.draw(s)
		if not shot and s.mode == "raise" and s.tip >= 0.5 then
			ctx:capture()
			shot = true
		end
		if s.mode ~= "raise" then
			local p = g.kubbs.a1.pose
			if not p.standing then error("a1 not raised") end
			local fp = raising.footprints(ctx.lying)[endRight]
			if math.abs(p.x - fp.x) > 1e-6 or math.abs(p.y - fp.y) > 1e-6 then
				error(string.format("raised at %.3f,%.3f, the right-hand end's footprint is %.3f,%.3f", p.x, p.y, fp.x, fp.y))
			end
			ctx.note = "end " .. endRight
			return true
		end
		if ctx.frame > 60 then error("not raised by frame 60 (tip " .. tostring(s.tip) .. ")") end
		return false
	end,
}
