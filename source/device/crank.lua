-- The crank's direction, a device setting (Jamie, 2026-11-19: "That feels like
-- a left - right hand pref for playdate crank"), and the nudge that tells a
-- player turning it the wrong way that it can be flipped. Pure: no playdate.*.
--
-- The direction is one sign, core/swing's tune.forwardSign; everything that
-- reads the crank as the arm reads it at use (swing.armAngle, the swing, the
-- settle scene's tip, the recorder's trace line, input.swingSteps). The core
-- is vendored and never edited: the game sets the tune value at launch and
-- when the player flips it. "Flipped" is kept relative to the core's own
-- sign, so a later change to the core's default keeps a flipped device
-- flipped against it.
--
--   crank.defaultSign      the core's forwardSign as loaded (before any flip)
--   crank.flipped          is the crank flipped now
--   crank.valid(d)         what the datastore gave back -> true (flipped) or
--                          false; anything else (nil, damaged) is false
--   crank.signFor(f)       the forwardSign for flipped f
--   crank.apply(f)         set crank.flipped and swing.tune.forwardSign
--   crank.save(f)          the table to write to the datastore
--
-- The nudge (scenes/throw, its tune's nudge* values): while the swing is idle
-- the scene feeds the arm angle (forward degrees from the bottom, as
-- swing.armAngle gives it). A forward turn is the arm going from within
-- nudgeBottomDeg of the bottom to nudgeTurnDeg or more forward without first
-- going back past the bottom zone. After nudgeTurns of them with no throw the
-- hint shows. A wind-up starting hides it (one more forward turn shows it
-- again: the count drops to one short); a throw clears the count.
--   crank.nudgeNew()            a fresh count
--   crank.nudgeArm(N, arm, t)   one idle frame's arm angle (nil: nothing)
--   crank.nudgeWound(N, t)      a wind-up started
--   crank.nudgeClear(N)         a throw was made (or the crank was flipped)
--   crank.nudgeShown(N, t)      does the hint show
import "core/tw"
import "core/swing"

local swing = tw.swing

local crank = {}

crank.defaultSign = swing.tune.forwardSign
crank.flipped = false

function crank.valid(d)
	return type(d) == "table" and d.flipped == true
end

function crank.signFor(f)
	if f then return -crank.defaultSign end
	return crank.defaultSign
end

function crank.apply(f)
	crank.flipped = f and true or false
	swing.tune.forwardSign = crank.signFor(crank.flipped)
end

function crank.save(f)
	return { flipped = f and true or false }
end

function crank.nudgeNew()
	return { n = 0, from = false }
end

function crank.nudgeArm(N, arm, t)
	if arm == nil then return end
	local b = t.nudgeBottomDeg
	if arm >= -b and arm <= b then
		N.from = true
	elseif arm < -b then
		N.from = false           -- went back from the bottom: not a forward turn
	elseif N.from and arm >= t.nudgeTurnDeg then
		N.n = N.n + 1
		N.from = false           -- separate turns: back to the bottom before the next counts
	end
end

function crank.nudgeWound(N, t)
	if N.n >= t.nudgeTurns then N.n = t.nudgeTurns - 1 end
	N.from = false
end

function crank.nudgeClear(N)
	N.n, N.from = 0, false
end

function crank.nudgeShown(N, t)
	return N.n >= t.nudgeTurns
end

tw.crank = crank
