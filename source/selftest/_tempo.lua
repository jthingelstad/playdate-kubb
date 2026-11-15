-- Helper for the scenarios "swing-tempo" and "swing-fast": the tempo rule (core/swing,
-- s.tempo; Jamie and Tyler, 2026-11-14). The wind-up picks the distance and
-- the flick only has to match the tempo (swing.tune.tempoDps, 850 deg/s: 17
-- degrees a 1/50 s frame). Wound 120 back (full power) at loft 29, released
-- as the arm passes the bottom. swing-tempo: a flick at the tempo leaves at
-- full power's launch speed, ON TEMPO. swing-fast: 26 degrees a frame (1300
-- deg/s) adds 0.4 m/s at the default gain and more beyond the knee, FAST:
-- LONG. Frames: 1 half wound (the aim arc lands short: it follows the
-- wind-up), 2 the baton in flight, 3 at rest (the verdict flag), 4 aiming
-- again (the flag until the next wind-up).
import "selftest/_throw"

local st = tw.selftest
local swing = tw.swing

function tw.selftest.tempoScenario(step, verdict, check)
	local steps = {}
	for i = 1, 12 do steps[i] = step end
	return st.throwScenario {
		setup = function(s)
			swing.setPreset("mid")
			s.swing.tempo = true
			s.loftDeg = 29
		end,
		script = {
			{ n = 5 },
			st.windup(120, 30),
			{ n = 5 },
			st.flick(steps),
			{ n = 300 },
		},
		shots = {
			function(s) return s.swing.phase == "winding" and s.swing.backswing >= 60 end,
			function(s) return s.mode == "flight" and tw.flight.progress(s.flight) >= 0.5 end,
			st.restShot(30),
			function(s) return s.mode == "aim" and s.throws == 1 end,
		},
		maxFrames = 500,
		check = function(s)
			swing.setPreset("stop")
			local l = s.last
			if not l or not l.launchSpeed then return "no launch" end
			if math.abs(l.power - 1) > 1e-6 then return "power " .. l.power .. ", wanted 1 (wound 120)" end
			if s.stopText ~= verdict then return "verdict " .. tostring(s.stopText) .. ", wanted " .. verdict end
			local err = check(s, l)
			if err then return err end
			return nil, string.format(" speed=%.2f tempo=%+d lands=%.2f", l.launchSpeed, math.floor(l.tempoDev + 0.5),
				s.flight.ly)
		end,
	}
end

