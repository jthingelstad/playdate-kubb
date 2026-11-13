-- The throw scene (stage 1): stand at the baseline, aim, wind up and flick
-- the crank, watch the baton fly, then do it again. Controls: the d-pad
-- walks (left/right along the line, down back from it), A + crank swivels,
-- B + crank sets the loft, the crank alone throws. All input comes from an input provider (input.lua),
-- so self-tests drive this scene with scripted crank samples.
import "CoreLibs/graphics"
import "core/tw"
import "core/camera"
import "core/swing"
import "core/flight"
import "render/world"
import "render/hud"
import "recorder"

local gfx <const> = playdate.graphics
local camera, swing, flight = tw.camera, tw.swing, tw.flight
local world, hud = tw.render.world, tw.render.hud
local max, min, rad, abs = math.max, math.min, math.rad, math.abs

tw.scenes = tw.scenes or {}
local throw = {}

throw.tune = {
	refreshRate = 50,     -- fps while aiming and throwing
	walkSpeed = 1.2,      -- m/s along the throwing line
	halfWidth = 2.5,      -- the line is 5 m wide (DESIGN 2)
	backMax = 3.0,        -- m the player may step back from the throwing line
	swivelGear = 0.25,    -- degrees of swivel per degree of crank with A held (geared down for fine aim)
	doubleTap = 0.35,     -- s between two presses of A or B that count as a double tap
	loftGear = 0.15,      -- degrees of loft per degree of crank with B held (forward = higher)
	swivelMaxDeg = 35,    -- swivel limit either way
	restHold = 1.0,       -- s the landed baton stays on screen before the next baton
	lineY = 0,            -- the throwing line: Team A's baseline
}

function throw.new(provider)
	local s = {
		input = provider,
		mode = "aim",            -- "aim" | "flight" | "rest"
		playerX = 0,
		tapA = 10, tapB = 10,    -- s since A and B were last pressed
		playerY = throw.tune.lineY, -- at the throwing line, or up to backMax behind it
		swivel = 0,              -- radians, + = right
		loftDeg = flight.tune.loftDefaultDeg,
		arm = nil,               -- where the crank is: forward degrees from the bottom of the turn
		armed = false,           -- the crank crossed the bottom going back; the wind-up may start
		swing = swing.new(),
		flight = flight.new(),
		aimCam = camera.new(),
		impactCam = camera.new(),
		view = camera.new(),
		restTime = 0,
		last = nil,              -- the last throw: power, smoothness, tilt, legal, distance, ...
		readout = nil,           -- its readout text
		showReadout = true,
		throws = 0,
		baton = { x = 0, y = 0, z = 0, ax = 0, ay = 0, az = 1 },
		hudState = { playerX = 0, lineY = 0 },
	}
	camera.aim(s.aimCam, s.playerX, s.playerY, s.swivel, world.targets)
	return s
end

local function aimInput(s, dt)
	local t = throw.tune
	local p = s.input
	local left, right = p:held("left"), p:held("right")
	local up, down = p:held("up"), p:held("down")
	local delta = p:crank()
	local arm = swing.armAngle(p:crankPos())
	local prevArm = s.arm
	s.arm = arm

	-- d-pad: walk. Left/right along the line, down steps back from it, up
	-- comes forward again as far as the line.
	local dx = (right and 1 or 0) - (left and 1 or 0)
	local dy = (up and 1 or 0) - (down and 1 or 0)
	if dx ~= 0 then
		s.playerX = max(-t.halfWidth, min(t.halfWidth, s.playerX + dx * t.walkSpeed * dt))
	end
	if dy ~= 0 then
		s.playerY = max(t.lineY - t.backMax, min(t.lineY, s.playerY + dy * t.walkSpeed * dt))
	end

	-- double tap A: face straight down the pitch again. Double tap B: loft
	-- back to the default.
	s.tapA, s.tapB = s.tapA + dt, s.tapB + dt
	if p:pressed("a") then
		if s.tapA <= t.doubleTap then s.swivel = 0 end
		s.tapA = 0
	end
	if p:pressed("b") then
		if s.tapB <= t.doubleTap then s.loftDeg = flight.tune.loftDefaultDeg end
		s.tapB = 0
	end

	-- hold A: the crank swivels the player. Hold B: the crank changes the
	-- loft. Either way the crank does not throw.
	local sw = s.swing
	local holdA, holdB = p:held("a"), p:held("b")
	if holdA or holdB then
		local turn = delta * swing.tune.forwardSign
		if holdA then
			local lim = rad(t.swivelMaxDeg)
			s.swivel = max(-lim, min(lim, s.swivel + rad(turn * t.swivelGear)))
		else
			local ft = flight.tune
			s.loftDeg = max(ft.loftMinDeg, min(ft.loftMaxDeg, s.loftDeg + turn * t.loftGear))
		end
		if sw.phase ~= "idle" then swing.reset(sw) end
		s.armed = false
		return nil
	end
	-- the wind-up starts when the crank crosses the bottom of the turn going
	-- back; until then the crank does nothing
	if sw.phase == "idle" then
		if not s.armed then
			if swing.crossedBack(prevArm, arm) then
				s.armed = true
				delta = arm * swing.tune.forwardSign   -- only the part past the bottom
			else
				delta = 0
			end
		elseif arm >= 0 then
			s.armed = false
			sw.pending = 0
			delta = 0
		end
	end
	local rec = tw.recorder
	if sw.phase == "idle" and sw.pending == 0 then rec.clear() end
	if sw.phase ~= "idle" or delta ~= 0 then rec.add(dt, delta) end
	local ev = swing.update(sw, delta, dt)
	if ev then s.armed = false end
	if ev == "letdown" then
		rec.write("letdown", nil)
	end
	return ev
end

local function launch(s)
	local r = s.swing.result
	local t = throw.tune
	local fl = s.flight
	flight.launch(fl, s.playerX, s.playerY, s.swivel, s.loftDeg, r.launchSpeed, r.tumbleRate, r.tilt)
	camera.impact(s.impactCam, fl.lx, fl.ly, fl.dx, fl.dy)
	s.last = s.last or {}
	local l = s.last
	l.power, l.smoothness, l.tilt, l.legal = r.power, r.smoothness, r.tilt, r.legal
	l.launchSpeed, l.tumbleRate, l.loft = r.launchSpeed, r.tumbleRate, s.loftDeg
	l.distance = nil
	s.readout = nil
	s.mode = "flight"
	s.throws = s.throws + 1
end

local function landed(s)
	local fl = s.flight
	local l = s.last
	l.distance = flight.distance(fl)
	l.landX, l.landY = fl.x, fl.y
	s.readout = hud.readoutText(l)
	local r = s.swing.result
	r.loft, r.distance = s.loftDeg, l.distance
	tw.recorder.write("release", r)
	r.loft, r.distance = nil, nil
	s.mode = "rest"
	s.restTime = 0
end

function throw.update(s)
	local p = s.input
	p:advance()
	local dt = p:dt()
	local t = throw.tune
	if s.mode == "aim" then
		local ev = aimInput(s, dt)
		camera.aim(s.aimCam, s.playerX, s.playerY, s.swivel, world.targets)
		if ev == "release" then launch(s) end
	elseif s.mode == "flight" then
		if flight.step(s.flight, dt) then landed(s) end
	else
		s.restTime = s.restTime + dt
		if s.restTime >= t.restHold then
			s.mode = "aim"
			-- the crank may have moved during the flight: arming needs a fresh
			-- crossing of the bottom, seen from aim mode
			s.arm, s.armed = nil, false
			swing.reset(s.swing)
			s.swing.backswing = 0
		end
	end
	-- the camera for this frame
	if s.mode == "aim" then
		s.viewCam = s.aimCam
	else
		local fl = s.flight
		camera.follow(s.view, s.aimCam, s.impactCam, flight.progress(fl), fl.x, fl.y, fl.z)
		s.viewCam = s.view
	end
end

function throw.draw(s)
	local fl = s.flight
	local b = nil
	if s.mode ~= "aim" then
		b = s.baton
		b.x, b.y = fl.x, fl.y
		b.ax, b.ay, b.az = flight.axis(fl)
		b.z = fl.landed and flight.tune.batonRadius or fl.z
	end
	world.draw(s.viewCam or s.aimCam, b)

	local hs = s.hudState
	hs.playerX, hs.lineY = s.playerX, s.playerY
	hs.aimX, hs.aimY = flight.aimPreview(s.playerX, s.playerY, s.swivel, s.loftDeg, swing.tune.launchMax)
	hs.baton = b
	if s.mode ~= "aim" then
		hs.landX, hs.landY = fl.lx, fl.ly
	elseif s.last and s.last.landX then
		hs.landX, hs.landY = s.last.landX, s.last.landY
	else
		hs.landX, hs.landY = nil, nil
	end
	hud.minimap(hs)

	local sw = s.swing
	local cap = (sw.phase ~= "idle") and swing.powerCap(sw) or nil
	local power = (s.mode ~= "aim" or sw.phase == "idle") and s.last and s.last.power or nil
	hud.panel(s.loftDeg, flight.tune.loftMinDeg, flight.tune.loftMaxDeg, cap, power)

	hud.swingGauge(sw.phase, sw.angle, (sw.phase ~= "idle") and sw.backswing or 0,
		swing.tune.fullBackswingDeg, s.mode ~= "aim", s.last and s.last.legal, s.last and s.last.power,
		s.arm or 0)

	if s.showReadout and s.readout and sw.phase == "idle" then hud.readout(s.readout) end
	if s.mode == "aim" and s.input:docked() then hud.crankPrompt() end
end

function throw.enter()
	playdate.display.setRefreshRate(throw.tune.refreshRate)
end

tw.scenes.throw = throw
