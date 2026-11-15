-- Scenario "burst-reset": the hit throw of "burst", reset (System Menu Pitch
-- -> reset) while its burst is up. The check: the burst is gone, the screen
-- is not inverted, and the next frame aims with nothing over the pitch.
-- Frame 1: the burst up; 2: the frame after the reset.
import "selftest/_throw"

local st = tw.selftest
local throw = tw.scenes.throw
local s

st.scenarios["burst-reset"] = {
	step = function(ctx)
		if not s then
			local steps = {}
			s = throw.new(tw.input.scripted(steps))
			for _, x in ipairs(st.planned(s)) do steps[#steps + 1] = x end
			throw.enter()
		end
		throw.update(s)
		throw.draw(s)
		local B = s.burst
		if not ctx.didReset and B.kind and B.age > 0.15 then
			ctx:capture()
			throw.reset(s)
			ctx.didReset = true
			if B.kind ~= nil or B.inverted then error("reset left the burst up") end
			return false
		end
		if ctx.didReset then
			if s.mode ~= "aim" or B.kind ~= nil or B.inverted then error("burst back after the reset") end
			ctx:capture()
			return true
		end
		if ctx.frame > 400 then error("no burst by frame 400") end
		return false
	end,
}
