-- Scenario "drive-solves": a plan that needs the drive's floor is solved at most once
-- per settled change, never per frame (engine 0.16; docs/notes/throw.md "The drive",
-- aimInput's guard). On the practice pitch a field kubb 1.5 m in front of the stance
-- (the forward limit there); B + down lowers the throw to its floor, and the release is
-- kept. Then, counting the scene's solves (throw.solves) and the solves that raised a
-- kept release to the floor (the 24-step bisection) frame by frame:
--   walking back with A + down (the floor rises under the kept release): no solve while
--     walking, the arc greyed (s.planStale); one when the walk stops, raised once
--   the d-pad moving the circle away: the same
--   the crank wound part way and let down: no solve
--   a snap onto the kubb (throw.aimAt), RESET, a switch to drilling and back, the
--     drive set again and thrown on the plan's swing, the circle retargeting at rest
--     after the kubb falls: at most one solve each, in one frame
--   the next throw of a match (throw.prepare): the kept release goes (the arc starts
--     afresh each throw), so nothing is left under a floor
-- Never more than one solve in a frame of the scene's own. Frames: 1 walking (the arc
-- greyed), 2 the walk stopped (the plan solved at the new floor).
import "selftest/_throw"
import "core/match"
import "core/names"

local st = tw.selftest
local throw, plan, cmatch = tw.scenes.throw, tw.plan, tw.match
local fmt = string.format

local B = { "b" }
local FX, KY, STANCE = 0.6, 5.5, 4.0

local function steps()
	local S = {
		{ n = 5 },                                     -- 1-5
		{ n = 25, hold = B },                          -- 6-30
	}
	for _ = 1, 4 do                                    -- 31-46: down to the floor
		S[#S + 1] = { hold = B, press = { "down" } }
		S[#S + 1] = { n = 3, hold = B }
	end
	S[#S + 1] = { n = 14 }                             -- 47-60
	S[#S + 1] = { n = 40, hold = { "a", "down" } }     -- 61-100 walking back
	S[#S + 1] = { n = 10 }                             -- 101-110 (101: the walk stopped)
	S[#S + 1] = { n = 20, hold = { "up" } }            -- 111-130 the circle away
	S[#S + 1] = { n = 10 }                             -- 131-140 (131: let go)
	S[#S + 1] = st.windup(60, 20)                      -- 141-160 wound part way
	S[#S + 1] = st.windup(-60, 20)                     -- 161-180 let down slowly
	S[#S + 1] = { n = 60 }                             -- 181-240 (the events below)
	return S
end

-- frames where the scenario itself changes the aim (its own call may solve once)
local EVENTS = { [200] = "snap", [205] = "reset", [210] = "drill", [215] = "batons", [220] = "drive" }
local QUIET = {}   -- frames that must make no solve: walking, moving the circle, the crank
for f = 62, 100 do QUIET[f] = "walking" end
for f = 112, 130 do QUIET[f] = "moving the circle" end
for f = 141, 180 do QUIET[f] = "the crank" end

st.scenarios["drive-solves"] = {
	step = function(ctx)
		if not ctx.scene then
			local S = steps()
			ctx.steps = S
			local s = throw.new(tw.input.scripted(S))
			local l = throw.defaultLayout()
			l[#l + 1] = { id = "f1", kind = "kubb", x = FX, y = KY, yaw = 0 }
			throw.setLayout(s, l)
			s.forwardY = STANCE
			throw.aimAt(s, FX, KY)
			throw.setStance(s, FX, STANCE)
			throw.enter()
			ctx.scene = s
			ctx.raised, ctx.worst = 0, 0
			-- a solve that raised its release to the floor bisected (plan.arcFloor's own
			-- are counted apart, throw.floorSolves)
			local solve = plan.solve
			ctx.solve = solve
			plan.solve = function(q, o)
				local r = solve(q, o)
				if q.projectile ~= "kubb" and q.release and r.release > q.release + 1e-6 then ctx.raised = ctx.raised + 1 end
				return r
			end
		end
		local s, f = ctx.scene, ctx.frame
		local ok, err = pcall(function()
			local ev = EVENTS[f]
			if ev == "snap" then throw.aimAt(s, FX, KY)
			elseif ev == "reset" then throw.reset(s)
			elseif ev == "drill" then throw.setDrill(s, true)
			elseif ev == "batons" then throw.setDrill(s, false)
			elseif ev == "drive" then
				throw.setArc(s, 0)
				if s.sol.release <= 0 then error("the drive was planned under its floor") end
				for _, x in ipairs(st.planned(s)) do ctx.steps[#ctx.steps + 1] = x end
				ctx.throwFrom = f
			end
			local n0, r0, fl0 = throw.solves or 0, ctx.raised, throw.floorSolves or 0
			throw.update(s)
			throw.draw(s)
			local n = (throw.solves or 0) - n0
			local raised = ctx.raised - r0 - ((throw.floorSolves or 0) - fl0)
			if n > ctx.worst then ctx.worst = n end
			if n > 1 then error(fmt("frame %d: %d solves in one frame", f, n)) end
			if raised > 1 then error(fmt("frame %d: %d raised solves", f, raised)) end
			if QUIET[f] and n > 0 then error(fmt("frame %d (%s): solved %d", f, QUIET[f], n)) end
			if f == 46 then
				if not throw.keptDrive(s) or s.sol.release > throw.arcFloor(s) + 1e-6 then
					error(fmt("not at the floor: %.2f", s.sol.release))
				end
				ctx.floor0 = s.sol.release
			elseif f == 80 then
				if not s.planStale then error("walking: the plan is not marked stale") end
				ctx:capture()                                                       -- 1
			elseif f == 101 then
				if n ~= 1 or raised ~= 1 then error(fmt("the walk stopped: %d solves, %d raised", n, raised)) end
				if s.planStale then error("the walk stopped and the plan is still stale") end
				if not (s.sol.release > ctx.floor0 + 0.5) then
					error(fmt("walked back but the floor %.2f did not rise from %.2f", s.sol.release, ctx.floor0))
				end
				ctx.walkFloor = s.sol.release
				ctx:capture()                                                       -- 2
			elseif f == 131 then
				if n ~= 1 then error(fmt("the circle let go: %d solves", n)) end
				ctx.circleRaised = raised
			elseif f == 241 then
				if not s.arcSet then error("the drive was not kept for the throw") end
			end
			-- the drive thrown: back to aiming after the rest, the circle retargeted
			if ctx.throwFrom and s.mode == "rest" then ctx.rested = true end
			if ctx.rested and s.mode == "aim" and not ctx.backAt then
				ctx.backAt = f
				if not s.arcSet then error("practice dropped the kept drive") end
			end
			if ctx.backAt and f == ctx.backAt + 5 then
				-- the next throw of a match: the kept release goes
				local m = cmatch.new { start = { year = 2026, month = 11, day = 22, hour = 12, min = 0 },
					teams = tw.names.teams { A = "Ash", B = "Birch" } }
				local n1 = throw.solves or 0
				throw.prepare(s, cmatch.setup(m))
				if s.arcSet then error("a new match throw kept the drive") end
				if (throw.solves or 0) - n1 > 1 then error("prepare solved more than once") end
				ctx.done = true
			end
		end)
		if not ok then
			plan.solve = ctx.solve
			error(err, 0)
		end
		if ctx.done then
			plan.solve = ctx.solve
			ctx.note = fmt("floor at 1.5 m %.2f, walked back %.2f; at most %d solve a frame; none while walking, moving the circle or cranking",
				ctx.floor0, ctx.walkFloor, ctx.worst)
			return true
		end
		if f > 1500 then
			plan.solve = ctx.solve
			error("the thrown drive never came back to aiming (" .. st.describe(s) .. ")", 0)
		end
		return false
	end,
}
