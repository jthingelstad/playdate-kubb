-- The scenarios "drill-tilt" and "drill-tilt-left" (one file each, so make
-- selftest runs both): the cut by tilting the console (Jamie, 2026-11-14:
-- "the accelerometer could be used to tilt and spin the Kubb on the drill").
-- The practice pitch drilling at the starting marker with the console rolled
-- right (30 degrees, the full cut) or left (40, past it: no more cut), no
-- button held; wound back into the band and stopped on the drill's notch. The
-- cut is drill.tiltCut of the roll, the flag says CUT RIGHT or CUT LEFT, the
-- kubb spins its way and curls that way after it lands, and the accelerometer
-- runs only while the drill is aimed (off in flight). Frames: 1 aiming tilted
-- (the level over the cut flag), 2 in the air, 3 at rest, 4 aiming again.
import "selftest/_throw"
import "core/drill"

local st = tw.selftest
local drill = tw.drill

local mx, my = 0, drill.tune.markerStartY
local sol = drill.solve(mx, my, 0)
local WIND = sol.band * tw.swing.tune.fullBackswingDeg

function tw.selftest.tiltScenario(roll, flag)
	local steps, left = {}, WIND + sol.loft
	while left > 0 do
		local d = math.min(20, left)
		steps[#steps + 1] = d
		left = left - d
	end
	local offInFlight, flagSeen = nil, nil
	return st.throwScenario {
		stopRelease = true,
		setup = function(s) tw.scenes.throw.setDrill(s, true) end,
		script = {
			{ n = 3, roll = roll },
			st.windup(WIND, 25),
			{ n = 3 },
			st.flick(steps),
			{ n = 300 },
		},
		shots = {
			function(s, f)
				if f == 3 then flagSeen = s.cut ~= 0 and s.tiltCuts end
				return f == 3
			end,
			function(s)
				if s.mode ~= "flight" or not s.pb or s.showTime < 0.2 then return false end
				offInFlight = not s.input.accelOn
				return true
			end,
			st.restShot(30),
			-- aiming again: the accelerometer is back on (from the next update)
			function(s) return s.mode == "aim" and s.throws == 1 and s.input.accelOn end,
		},
		maxFrames = 500,
		check = function(s)
			local l = s.last
			if not l or not l.drill then return "the throw was not a drill" end
			if not flagSeen then return "no tilt cut while aiming" end
			if not offInFlight then return "the accelerometer ran in flight" end
			if not l.roll or math.abs(l.roll - roll) > 0.5 then
				return string.format("roll %s, the console is at %d", tostring(l.roll), roll)
			end
			local want = drill.tiltCut(roll)
			if math.abs(l.cut - want) > 0.02 then return string.format("cut %.3f, expected %.3f", l.cut, want) end
			if (l.cut > 0 and "CUT RIGHT" or "CUT LEFT") ~= flag then return "cut the wrong way" end
			-- positive spin about the forward long axis curls left (core/drill)
			local spin = s.drillLaunch.spin
			if (spin < 0) ~= (roll > 0) then return string.format("spin %.1f for roll %d", spin, roll) end
			-- the curl: from where it first touched to where it rests, across the line
			local curl = l.restX - l.landX
			if (curl > 0) ~= (roll > 0) or math.abs(curl) < 0.02 then
				return string.format("curled %+.3f m for roll %d", curl, roll)
			end
			return nil, string.format(" cut=%.2f curl_m=%+.3f", l.cut, curl)
		end,
	}
end

