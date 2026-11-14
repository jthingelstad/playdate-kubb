-- Scenarios "release-stop" and "release-early": the release where the crank
-- stops (Jamie and Tyler, 2026-11-14). The crank is the throwing arm: the
-- launch angle is the arm's angle past the bottom of the turn where the
-- crank stops, and the loft set (30 here) is the target marked on the dial.
-- release-stop: wound 120 back, a strong flick of 150 forward, stopped 30
-- past the bottom, on the target: the baton leaves at 30 degrees and flies
-- long. release-early: the same flick cut to 100 forward, stopped 20 short of
-- the bottom, 50 short of the notch: with the forgiving notch it leaves at
-- about 17 degrees, low and short (it was -20, into the ground). Frames: 1
-- aiming (the target on the dial), 2 the baton in flight (release-stop) or
-- just down (release-early), 3 at rest (the verdict flag: ON THE NOTCH or
-- EARLY: LOW), 4 aiming again (the stop's dot on the dial beside the notch).
import "selftest/_throw"

local st = tw.selftest

local function scenario(flick, want, verdict, check)
	return st.throwScenario {
		stopRelease = true,
		setup = function(s) s.loftDeg = 30 end,
		script = {
			{ n = 5 },
			st.windup(120, 30),
			{ n = 5 },
			st.flick(flick),
			{ n = 300 },
		},
		shots = {
			function(s, f) return f == 3 end,
			function(s) return s.mode == "flight" and tw.flight.progress(s.flight) >= 0.5 end,
			st.restShot(30),
			-- aiming again: the stop's dot on the dial beside the notch, and
			-- the verdict
			function(s) return s.mode == "aim" and s.throws == 1 end,
		},
		maxFrames = 500,
		check = function(s)
			local l = s.last
			if not l or not l.launchLoft then return "no launch" end
			if math.abs(l.launchLoft - want) > 3 then
				return string.format("launch loft %.1f, wanted about %d", l.launchLoft, want)
			end
			if s.loftDeg ~= 30 then return "the loft set moved: " .. s.loftDeg end
			if s.stopText ~= verdict then return "verdict " .. tostring(s.stopText) .. ", wanted " .. verdict end
			local err = check(s)
			if err then return err end
			return nil, string.format(" loft=%.1f lands=%.2f", l.launchLoft, s.flight.ly)
		end,
	}
end

st.scenarios["release-stop"] = scenario({ 6, 12, 18, 22, 24, 24, 24, 20 }, 30, "ON THE NOTCH", function(s)
	if s.flight.ly < 5 then return string.format("landed %.2f m out: too short", s.flight.ly) end
end)

-- 50 short of the notch: 10 of it forgiven, a third of the other 40 off
-- the loft (30 - 13.3): a lower, shorter throw, not one into the ground
st.scenarios["release-early"] = scenario({ 6, 12, 18, 22, 24, 18 }, 30 - 40 / 3, "EARLY: LOW", function(s)
	if s.flight.ly > 7.5 then return string.format("landed %.2f m out: should be short", s.flight.ly) end
end)
