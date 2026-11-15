-- Scenario "howto-play": HOW TO PLAY's six cards (scenes/howtoplay), paged
-- through with A, one B back and on again, then A on the last card, which
-- must ask for HOW TO THROW; the practice pitch is then opened with HOW TO
-- THROW over it, as main.lua does. render/howtoplay raises an error if a
-- card's words run past the bottom, so every card is checked by drawing it.
-- Frames: 01 to 06 the cards, 07 HOW TO THROW's first step after the last card.
import "core/tw"
import "core/howtoplay"
import "scenes/howtoplay"
import "scenes/throw"
import "input"

local scene, throw = tw.scenes.howtoplay, tw.scenes.throw
local s, ts, shots, backed = nil, nil, 0, false

tw.selftest.scenarios["howto-play"] = {
	step = function(ctx)
		if not s then
			-- nothing pressed at first: every third frame below feeds one press
			s = scene.new(tw.input.scripted { { n = 2 } })
			scene.enter()
		end
		if ts then
			throw.update(ts)
			throw.draw(ts)
			if ctx.frame >= ts.started + 3 then
				if not ts.howto or ts.howto.step ~= 1 then error("HOW TO THROW did not start at step 1") end
				ctx:capture()
				return true
			end
			return false
		end
		local p = s.input
		scene.update(s)
		if s.exit then
			if s.exit ~= "howto" then error("the last card's A asked for " .. tostring(s.exit)) end
			ts = throw.new(tw.input.scripted { { n = 20 } })
			throw.showHowTo(ts)
			throw.enter()
			ts.started = ctx.frame
			return false
		end
		scene.draw(s)
		local page = s.st.page
		if ctx.frame % 3 == 0 then
			if page > shots then
				ctx:capture()
				shots = page
			end
			-- one B back from card 3 and on again: B must turn back, not leave
			local press = "a"
			if page == 3 and not backed then press, backed = "b", true end
			-- (a provider that has run out starts again on the first new step)
			if p:finished() then p.k = 0 end
			p.steps[#p.steps + 1] = { press = { press } }
			p.steps[#p.steps + 1] = { n = 1 }
		end
		if ctx.frame > 200 then error("stuck on card " .. page) end
		return false
	end,
}
