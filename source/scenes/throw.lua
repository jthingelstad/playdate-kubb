-- The throw scene (stage 1): stand at the baseline, aim, wind up and flick
-- the crank, watch the baton fly, then do it again. Controls are DESIGN.md
-- section 4 "Batons". All input comes from an input provider (input.lua),
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
	swivelGear = 0.25,    -- degrees of swivel per degree of crank (geared down for fine aim)
	swivelMaxDeg = 35,    -- swivel limit either way
	loftRepeatDelay = 0.35, -- s before a held d-pad up/down starts repeating
	loftRepeatEvery = 0.12, -- s between repeats
	restHold = 1.0,       -- s the landed baton stays on screen before the next baton
	lineY = 0,            -- the throwing line: Team A's baseline
}

function throw.new(provider)
	local s = {
		input = provider,
		mode = "aim",            -- "aim" | "flight" | "rest"
		playerX = 0,
		swivel = 0,              -- radians, + = right
		loftDeg = flight.tune.loftDefaultDeg,
		swivelLatched = false,   -- the crank turned while left/right was held
		loftHeld = 0,
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
	camera.aim(s.aimCam, s.playerX, throw.tune.lineY, s.swivel, world.targets)
	return s
end

local function aimInput(s, dt)
	local t = throw.tune
	local p = s.input
	local left, right = p:held("left"), p:held("right")
	local up, down = p:held("up"), p:held("down")
	local delta = p:crank()

	if left or right then
		-- d-pad left/right + crank swivels; walking stops once the crank turns
		if delta ~= 0 then s.swivelLatched = true end
		if s.swivelLatched then
			local d = s.swivel + rad(delta * swing.tune.forwardSign * t.swivelGear)
			local lim = rad(t.swivelMaxDeg)
			s.swivel = max(-lim, min(lim, d))
		else
			local dir = (right and 1 or 0) - (left and 1 or 0)
			s.playerX = max(-t.halfWidth, min(t.halfWidth, s.playerX + dir * t.walkSpeed * dt))
		end
	else
		s.swivelLatched = false
	end

	-- loft: one step per press, repeating while held
	local step = 0
	if p:pressed("up") then step = 1 elseif p:pressed("down") then step = -1 end
	if up or down then
		s.loftHeld = s.loftHeld + dt
		if step == 0 and s.loftHeld >= t.loftRepeatDelay then
			step = up and 1 or -1
			s.loftHeld = s.loftHeld - t.loftRepeatEvery
		end
	else
		s.loftHeld = 0
	end
	if step ~= 0 then
		local ft = flight.tune
		s.loftDeg = max(ft.loftMinDeg, min(ft.loftMaxDeg, s.loftDeg + step * ft.loftStepDeg))
	end

	-- the throw: only with the d-pad released
	if left or right or up or down then return nil end
	local sw = s.swing
	local rec = tw.recorder
	if sw.phase == "idle" and sw.pending == 0 then rec.clear() end
	if sw.phase ~= "idle" or delta ~= 0 then rec.add(dt, delta) end
	local ev = swing.update(sw, delta, dt)
	if ev == "letdown" then
		rec.write("letdown", nil)
	end
	return ev
end

local function launch(s)
	local r = s.swing.result
	local t = throw.tune
	local fl = s.flight
	flight.launch(fl, s.playerX, t.lineY, s.swivel, s.loftDeg, r.launchSpeed, r.tumbleRate, r.tilt)
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
		camera.aim(s.aimCam, s.playerX, t.lineY, s.swivel, world.targets)
		if ev == "release" then launch(s) end
	elseif s.mode == "flight" then
		if flight.step(s.flight, dt) then landed(s) end
	else
		s.restTime = s.restTime + dt
		if s.restTime >= t.restHold then
			s.mode = "aim"
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
	hs.playerX, hs.lineY = s.playerX, throw.tune.lineY
	hs.aimX, hs.aimY = flight.aimPreview(s.playerX, throw.tune.lineY, s.swivel, s.loftDeg, swing.tune.launchMax)
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

	if s.showReadout and s.readout and sw.phase == "idle" then hud.readout(s.readout) end
	if s.mode == "aim" and s.input:docked() then hud.crankPrompt() end
end

function throw.enter()
	playdate.display.setRefreshRate(throw.tune.refreshRate)
end

tw.scenes.throw = throw
