-- Scenario "drive": the drive (Kubb Engine 0.16, docs/notes/throw.md "The drive") on
-- the practice pitch. A field kubb 1.5 m in front of an advantage line, one 4 m from
-- the stance and a base kubb 8 m away:
--   the default (no A or B): plan.arcFor by the distance, a firm low throw at 1.5 m
--     (a launch under 0, no end over end turn), loft 4.9 at 4 m, the line before at 8 m
--   ARC with B held: the chip (DRIVE under the knee, ARC above) and its words; B + down
--     steps to the throw's floor (plan.arcFloor) and no lower, and a tap up from the
--     floor moves the throw at once; up past the knee is ARC again; at 8 m the floor is
--     the knee; a drilled kubb stops at the knee
--   the side view: the planned arc leaves the hand going down and meets the kubb's
--     face, on screen in the plan view (from arcFitFrom, as shoulderFit keeps it)
--   a drive thrown on the plan's clean swing and played back: the baton never turns
--     end over end (its axis stays up) and the kubb falls
-- Frames: 1 ARC at 1.5 m (the plan view), 2 the side view of a drive at the floor, 3
-- ARC at 4 m, 4 ARC at 8 m, 5 a drive in flight, 6 at rest.
import "selftest/_throw"
import "render/hud"

local st = tw.selftest
local throw, plan, hud = tw.scenes.throw, tw.plan, tw.render.hud
local fmt, abs = string.format, math.abs

local B = { "b" }
local function tap(key) return { hold = B, press = { key } } end
local function near(a, b, e) return abs(a - b) < (e or 1e-6) end

-- the practice pitch with a field kubb at (FX, y), the stance (FX, stanceY)
local FX = 0.6
local function scene(script, ky, stanceY, adv)
	local s = throw.new(tw.input.scripted(script))
	local l = throw.defaultLayout()
	if ky then l[#l + 1] = { id = "f1", kind = "kubb", x = FX, y = ky, yaw = 0 } end
	throw.setLayout(s, l)
	if adv then
		s.forwardY, s.advY = stanceY, stanceY
		s.advText = hud.advantageText(stanceY)
	end
	if ky then
		throw.aimAt(s, FX, ky)
		throw.setStance(s, FX, stanceY)
	else
		throw.aimAt(s, 0, 8)            -- b3, 8 m straight ahead
		throw.setStance(s, 0, 0)
	end
	throw.enter()
	return s
end

local function frame(s)
	throw.update(s)
	throw.draw(s)
end

-- the default plan at distance d (nothing pressed)
local function checkDefault(s, d)
	local sol = s.sol
	local want = plan.arcFor("baton", d)
	if not near(sol.release, want, 1e-3) then return fmt("%.1f m: the default release %.2f, not %.2f", d, sol.release, want) end
	if s.arcSet then return fmt("%.1f m: the arc was set", d) end
	return nil
end

-- the planned arc from the hand to its end: z at each point (world), falling all the way?
local function arcFalls(s)
	local _, _, vz, T = throw.arcLaunch(s)
	local _, _, h = throw.arcOrigin(s)
	local g = tw.flight.tune.g
	local last = h
	for i = 1, 24 do
		local t = T * i / 24
		local z = h + vz * t - 0.5 * g * t * t
		if z > last + 1e-6 then return false, vz end
		last = z
	end
	return vz < 0, vz, h, last
end

-- the arc and the circle on screen in the camera as it is
local function arcOnScreen(s)
	local ring, _, on, all, off = throw.arcBox(s)
	if off then return false end
	-- the plan view keeps the arc on screen from arcFitFrom on: its first rise by the
	-- hand may come in from the lower edge (shoulderFit)
	local t = throw.tune
	return on >= all - (t.arcFitFrom - t.arcSkip) and ring[1] >= 0 and ring[3] <= 400 and ring[2] >= 0
		and ring[4] <= 240, on, all
end

-- Part 1: a kubb 1.5 m in front of the advantage line 4 m up
local S15 = {
	{ n = 5 },                                   -- 1-5 first person
	{ n = 25, hold = B },                        -- 6-30 the plan view: ARC at 1.5 m (frame 1)
	tap("down"), { n = 3, hold = B },            -- 31-34
	tap("down"), { n = 3, hold = B },            -- 35-38
	tap("down"), { n = 3, hold = B },            -- 39-42 (at the floor by now)
	tap("down"), { n = 25, hold = B },           -- 43-68 still the floor: the side view (frame 2)
	tap("up"), { n = 3, hold = B },              -- 69-72 a tap up: moves at once
	tap("up"), { n = 3, hold = B },              -- 73-76
	tap("up"), { n = 3, hold = B },              -- 77-80 past the knee: ARC
	{ n = 25 },                                  -- 81-105 back to first person
}
-- Part 2 and 3: the default at 4 m and 8 m, B held (frames 3 and 4); at 8 m held
-- down to the floor (the knee), then a tap up
local S4 = { { n = 5 }, { n = 25, hold = B }, { n = 5 } }
local S8 = { { n = 5 }, { n = 25, hold = B }, { n = 45, hold = { "b", "down" } }, { n = 3, hold = B }, tap("up"),
	{ n = 3, hold = B }, { n = 5 } }
-- Part 4: a drill, held down: a kubb stops at the knee
local SD = { { n = 5 }, { n = 45, hold = { "b", "down" } }, { n = 5, hold = B }, { n = 5 } }

local function fail(msg) error(msg, 0) end

st.scenarios["drive"] = {
	step = function(ctx)
		local s = ctx.scene
		local f = ctx.frame
		if not ctx.part then
			ctx.part, ctx.f0 = 1, f
			ctx.scene = scene(S15, 5.5, 4.0, true)
			s = ctx.scene
			local err = checkDefault(s, 1.5)
			if err then fail(err) end
			local sol = s.sol
			-- firm and low with no turn (CLIENTS.md "0.16 on top": a release of 6, launch
			-- loft -4.6 at 6.5 m/s at 1.5 m)
			if not (sol.loft < 0) then fail(fmt("1.5 m: the default launch loft %.1f is not under 0", sol.loft)) end
			if not (sol.speed > 6 and sol.speed < 7) then fail(fmt("1.5 m: the default speed %.2f m/s", sol.speed)) end
			if (sol.tumble or 0) > 1e-6 then fail(fmt("1.5 m: the default turns end over end (%.2f rad/s)", sol.tumble)) end
			if not throw.isDrive(s) then fail("1.5 m: the default is not a drive") end
			ctx.d15 = fmt("1.5m rel=%.1f loft=%.1f v=%.2f", sol.release, sol.loft, sol.speed)
		end
		local lf = f - ctx.f0 + 1     -- this part's frame
		if ctx.part == 1 then
			frame(s)
			local pt = plan.tune
			if lf == 30 then
				if s.arcWords ~= throw.ARC_WORDS.drive then fail("1.5 m: the ARC words " .. tostring(s.arcWords)) end
				local ok, on, all = arcOnScreen(s)
				if not ok then fail(fmt("1.5 m: the drive's arc off the plan view (%s of %s)", tostring(on), tostring(all))) end
				ctx.floor = throw.arcFloor(s)
				if not (ctx.floor >= 0 and ctx.floor < s.sol.release) then fail(fmt("1.5 m: the floor %.2f", ctx.floor)) end
				ctx:capture()                                                         -- 1
			elseif lf == 34 then
				if not near(s.release, plan.arcFor("baton", 1.5) - pt.arcTickDeg, 1e-3) and not near(s.release, ctx.floor) then
					fail(fmt("1.5 m: a tap down went to %.2f", s.release))
				end
			elseif lf == 68 then
				if not near(s.sol.release, ctx.floor, 1e-3) or s.release < ctx.floor - 1e-6 then
					fail(fmt("1.5 m: held down at %.2f (planned %.2f), not the floor %.2f", s.release, s.sol.release, ctx.floor))
				end
				if s.arcWords ~= throw.ARC_WORDS.floor then fail("1.5 m: at the floor the words " .. tostring(s.arcWords)) end
				local falls, vz, h, z1 = arcFalls(s)
				if not falls then fail(fmt("1.5 m: the floor's arc does not leave the hand going down (vz %.2f)", vz)) end
				-- the baton's centre at the plan's aim height on the face (plan.aimZFor: under
				-- the kubb's top, nearer its face close in)
				if not (z1 > 0.02 and z1 < 0.25) then
					fail(fmt("1.5 m: the arc ends %.2f m up, not on the kubb's face", z1))
				end
				local ok = arcOnScreen(s)
				if not ok then fail("1.5 m: the floor's arc off the plan view") end
				ctx.side = fmt("floor=%.1f loft=%.1f hand=%.2f face=%.2f", ctx.floor, s.sol.loft, h, z1)
				ctx:capture()                                                         -- 2 (the side view)
			elseif lf == 72 then
				-- a press at the floor and back is never a dead step
				if not near(s.release, ctx.floor + pt.arcTickDeg, 1e-3) then
					fail(fmt("1.5 m: a tap up from the floor %.2f went to %.2f", ctx.floor, s.release))
				end
			elseif lf == 80 then
				if throw.isDrive(s) or s.arcWords ~= throw.ARC_WORDS.lower then
					fail(fmt("1.5 m: up past the knee at %.1f is still %s", s.release, tostring(s.arcWords)))
				end
			elseif lf == 105 then
				ctx.part, ctx.f0 = 2, f + 1
				-- (the far half's targets start past the centre line: the kubb 4.5 m out, the
				-- stance half a metre ahead of the line)
				ctx.scene = scene(S4, 4.5, 0.5)
				local err = checkDefault(ctx.scene, 4.0)
				if err then fail(err) end
				local sol = ctx.scene.sol
				if not (sol.loft > 3 and sol.loft < 7) then fail(fmt("4 m: the default loft %.1f", sol.loft)) end
				if not (sol.speed > 10 and sol.speed < 10.6) then fail(fmt("4 m: the default speed %.2f m/s", sol.speed)) end
				ctx.d4 = fmt("4m rel=%.1f loft=%.1f v=%.2f", sol.release, sol.loft, sol.speed)
			end
		elseif ctx.part == 2 then
			frame(s)
			if lf == 30 then
				if s.arcWords ~= throw.ARC_WORDS.drive then fail("4 m: the ARC words " .. tostring(s.arcWords)) end
				if not arcOnScreen(s) then fail("4 m: the arc off the plan view") end
				ctx:capture()                                                         -- 3
			elseif lf == 35 then
				ctx.part, ctx.f0 = 3, f + 1
				ctx.scene = scene(S8, nil, 0)
				local err = checkDefault(ctx.scene, 8)
				if err then fail(err) end
				local sol = ctx.scene.sol
				if not near(sol.release, plan.sharedArcFor(8), 1e-3) then fail("8 m: not the line before") end
				ctx.d8 = fmt("8m rel=%.1f loft=%.1f v=%.2f", sol.release, sol.loft, sol.speed)
			end
		elseif ctx.part == 3 then
			frame(s)
			local pt = plan.tune
			if lf == 30 then
				if s.arcWords ~= throw.ARC_WORDS.lower then fail("8 m: the ARC words " .. tostring(s.arcWords)) end
				ctx:capture()                                                         -- 4
			elseif lf == 78 then
				local fl = throw.arcFloor(s)
				if not near(fl, pt.driveKneeDeg, 1e-3) then fail(fmt("8 m: the floor %.2f is not the knee", fl)) end
				if not near(s.release, fl, 1e-3) then fail(fmt("8 m: held down to %.2f, not the floor", s.release)) end
				if s.arcWords ~= throw.ARC_WORDS.floor then fail("8 m: at the floor the words " .. tostring(s.arcWords)) end
			elseif lf == 82 then
				if not near(s.release, pt.driveKneeDeg + pt.arcTickDeg, 1e-3) then
					fail(fmt("8 m: a tap up from the floor went to %.2f", s.release))
				end
			elseif lf == 86 then
				ctx.part, ctx.f0 = 4, f + 1
				ctx.scene = scene(SD, nil, 0)
				throw.setDrill(ctx.scene, true)
			end
		elseif ctx.part == 4 then
			frame(s)
			if lf == 55 then
				if not near(s.release, plan.tune.driveKneeDeg, 1e-3) then fail(fmt("drill: held down to %.2f", s.release)) end
				if s.arcWords ~= throw.ARC_WORDS.kubbFloor then fail("drill: the words " .. tostring(s.arcWords)) end
			elseif lf == 60 then
				-- Part 5: the default drive at 1.5 m thrown on the plan's clean swing
				ctx.part, ctx.f0 = 5, f + 1
				local t = scene({}, 5.5, 4.0, true)
				local steps = st.planned(t)
				local inp = tw.input.scripted(steps)
				t.input = inp
				ctx.scene = t
				ctx.minAz, ctx.flightFrames = 1, 0
			end
		elseif ctx.part == 5 then
			frame(s)
			if s.mode == "flight" then
				ctx.flightFrames = ctx.flightFrames + 1
				-- before it touches anything: the baton's axis (a unit vector) stays up
				-- (the physics runs ahead of the picture: a contact it has found may still
				-- be ahead on screen, sinceContact under 0)
				if (st.sinceContact(s) or -1) < 0 then
					local az = abs(s.baton.az or 1)
					if az < ctx.minAz then ctx.minAz = az end
					if not ctx.shotFlight and s.showTime > 0.08 and st.batonOnScreen(s) then
						ctx.shotFlight = true
						ctx:capture()                                                 -- 5
					end
				end
			end
			if s.mode == "rest" then
				ctx.restN = (ctx.restN or 0) + 1
				if ctx.restN == 30 then
					ctx:capture()                                                     -- 6
					local l = s.last
					if not ctx.shotFlight then fail("no flight frame before the baton touched") end
					if ctx.minAz < 0.5 then fail(fmt("the drive turned in the air: axis z down to %.2f", ctx.minAz)) end
					local down = false
					for _, id in ipairs(s.result.toppled) do if id == "f1" then down = true end end
					if not down then fail("the drive left f1 standing: " .. table.concat(s.result.toppled, ",")) end
					ctx.note = fmt("%s; %s; %s; %s; thrown: loft=%.1f v=%.2f tumble=%.2f minAz=%.2f flight=%d; floor solves %d",
						ctx.d15, ctx.d4, ctx.d8, ctx.side, l.launchLoft, l.launchSpeed, l.tumbleRate, ctx.minAz,
						ctx.flightFrames, throw.floorSolves or 0)
					return true
				end
			end
			if lf > 900 then fail("the drive never came to rest (" .. st.describe(s) .. ")") end
		end
		return false
	end,
}
