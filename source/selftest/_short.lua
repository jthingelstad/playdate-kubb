-- Shared by the scenarios "short-throw" and "short-over": the crank throw
-- at a field kubb a step away (engine 0.8, the hand at a short throw: flight.handAt; Jamie,
-- 2026-11-20: a kubb a step away is hit low and hard, and overpowering it
-- misses). A field kubb 1 m straight ahead of the stance, the circle on it.
-- "short-throw" is the plan's clean crank throw: the baton leaves the plan's
-- low hand and must topple the kubb. "short-over" winds three power bands
-- past the target and stops on the release: the overpowered bowl heaves up
-- and must leave the kubb standing. Frames: 1 aiming (the short arc from the
-- hand), 2 at rest.
import "selftest/_throw"

local st = tw.selftest
local throw = tw.scenes.throw

local FX, FY, STANCE = 0.6, 5.0, 4.0

function st.shortSetup(s)
	local l = throw.defaultLayout()
	l[#l + 1] = { id = "f1", kind = "kubb", x = FX, y = FY, yaw = 0 }
	throw.setLayout(s, l)
	s.forwardY = STANCE
	throw.aimAt(s, FX, FY)
	throw.setStance(s, FX, STANCE)
end

local function fell(s)
	for _, id in ipairs(s.result.toppled) do
		if id == "f1" then return true end
	end
	return false
end

function st.shortCheck(want)
	return function(s)
		local r, sol = s.result, s.sol
		if not r or not sol then return "no result" end
		if not (sol.handZ < tw.flight.tune.handHeight) then
			return string.format("the plan's hand at %.2f m: not a short throw", sol.handZ)
		end
		if fell(s) ~= want then
			return (want and "f1 left standing" or "f1 toppled by an overpowered throw")
				.. ": " .. table.concat(r.toppled, ",")
		end
		return nil, string.format(" hand=%.2f fwd=%.2f power=%d toppled=%s",
			sol.handZ, sol.handFwd, s.vPower or 0, fell(s) and "f1" or "-")
	end
end

