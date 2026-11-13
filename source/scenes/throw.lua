-- The throw scene: stand at the baseline, aim, wind up and flick the crank,
-- watch the baton fly and knock kubbs over, then do it again. Controls: the
-- d-pad walks (left/right along the line, down back from it), B + crank
-- swivels, A + crank sets the loft, the crank alone throws. All input comes
-- from an input provider (input.lua), so self-tests drive this scene with
-- scripted crank samples.
--
-- Stage 2: the throw is simulated by the rigid-body world (core/world) and
-- shown through core/playback: the physics runs ahead of the screen within
-- tune.physicsBudget per frame and the scene plays the recorded frames back
-- in real time; when the physics falls behind, playback waits (slows down)
-- rather than skipping. Practice: toppled kubbs stay down between throws
-- (they keep their rest poses); throw.reset stands everything back up (the
-- System Menu "Pitch: reset"), and it happens by itself after the throw that
-- leaves every far base kubb down.
import "CoreLibs/graphics"
import "core/tw"
import "core/camera"
import "core/swing"
import "core/flight"
import "core/pitch"
import "core/world"
import "core/playback"
import "render/world"
import "render/hud"
import "recorder"

local gfx <const> = playdate.graphics
local camera, swing, flight, pitch = tw.camera, tw.swing, tw.flight, tw.pitch
local phys, playback = tw.world, tw.playback
local render, hud = tw.render.world, tw.render.hud
local max, min, rad, abs, sqrt, floor = math.max, math.min, math.rad, math.abs, math.sqrt, math.floor

tw.scenes = tw.scenes or {}
local throw = {}

throw.tune = {
	refreshRate = 50,     -- fps while aiming and throwing
	walkSpeed = 1.2,      -- m/s along the throwing line
	halfWidth = 2.5,      -- the line is 5 m wide (DESIGN 2)
	backMax = 3.0,        -- m the player may step back from the throwing line
	swivelGear = 0.25,    -- degrees of swivel per degree of crank with B held (geared down for fine aim)
	doubleTap = 0.35,     -- s between two presses of A or B that count as a double tap
	loftGear = 0.15,      -- degrees of loft per degree of crank with A held (forward = higher)
	swivelMaxDeg = 35,    -- swivel limit either way
	restHold = 1.0,       -- s the landed baton stays on screen before the next baton
	lineY = 0,            -- the throwing line: Team A's baseline
	surface = "grass",    -- the practice pitch (tw.world.surfaces)
	physicsBudget = 0.012,-- s of each frame the physics may use (guess: leaves ~8 ms of a
	                      -- 20 ms frame to draw; the device draws slower than that today)
	ahead = 25,           -- frames the physics may record ahead of the screen
	focusSpeed = 4,       -- m/s the impact camera's aim point slews toward the first hit
	frameRadius = 1.5,    -- m from the impact point within which the camera keeps the baton in frame
}

-- The practice layout: five base kubbs on each baseline and the king.
-- `base` marks the far base kubbs (all down = stand everything back up).
function throw.defaultLayout()
	local l = {}
	for _, side in ipairs { { "a", 0 }, { "b", 8 } } do
		for i, x in ipairs(pitch.baseX) do
			l[#l + 1] = { id = side[1] .. i, kind = "kubb", x = x, y = side[2], base = side[2] == 8 }
		end
	end
	l[#l + 1] = { id = "king", kind = "king", x = pitch.king.x, y = pitch.king.y }
	return l
end

-- Stand every piece of the layout up at its spot (a reset).
function throw.standUp(s)
	local items = s.items
	for i, p in ipairs(s.layout) do
		local it = items[i]
		if not it or it.id ~= p.id or it.kind ~= p.kind then
			it = render.item(p.id, p.kind)
			items[i] = it
		end
		local yaw = (p.yaw or 0) / 2
		render.setPose(it, p.x, p.y, it.hz, math.cos(yaw), 0, 0, math.sin(yaw))
		it.toppled = false
		it.base = p.base
	end
	for i = #s.layout + 1, #items do items[i] = nil end
	s.nitems = #s.layout
end

-- Use another layout ({id, kind, x, y, yaw, base} list) and stand it up.
function throw.setLayout(s, layout)
	s.layout = layout
	throw.standUp(s)
end

-- Live targets for the aim camera's framing rule: the standing kubbs in the
-- far half (reused table).
local function updateTargets(s)
	local tg, n = s.targets, 0
	for i = 1, s.nitems do
		local it = s.items[i]
		if not it.toppled and not it.king and it.y > throw.tune.lineY + 4 then
			n = n + 1
			tg[n] = it
		end
	end
	for i = n + 1, #tg do tg[i] = nil end
end

function throw.new(provider)
	local s = {
		input = provider,
		mode = "aim",            -- "aim" | "flight" | "rest"
		playerX = 0,
		tapA = 10, tapB = 10,    -- s since the swivel button (B) and the loft button (A) were last pressed
		playerY = throw.tune.lineY, -- at the throwing line, or up to backMax behind it
		swivel = 0,              -- radians, + = right
		loftDeg = flight.tune.loftDefaultDeg,
		arm = nil,               -- where the crank is: forward degrees from the bottom of the turn
		armed = false,           -- the crank crossed the bottom going back; the wind-up may start
		swing = swing.new(),
		flight = flight.new(),   -- the stage 1 prediction (landing point, flight time) and
		                         -- the baton's displayed position (x, y, z, t)
		aimCam = camera.new(),
		impactCam = camera.new(),
		view = camera.new(),
		restTime = 0,
		last = nil,              -- the last throw: power, smoothness, tilt, legal, distance, ...
		readout = nil,           -- its readout text
		showReadout = true,
		throws = 0,
		surface = throw.tune.surface,
		layout = throw.defaultLayout(),
		items = {}, nitems = 0,  -- render/world items, one per layout piece
		targets = {},
		pb = nil,                -- the throw being played back (core/playback)
		bodyIndex = {},          -- item i -> body index in pb.w
		batonIndex = 0,
		showTime = 0,            -- s of the throw on screen
		focusX = 0, focusY = 0, side = 1, -- the impact camera's aim point and side
		result = nil,            -- core/world result of the last throw
		clock = playdate.getElapsedTime,
		baton = { x = 0, y = 0, z = 0, ax = 0, ay = 0, az = 1 },
		hudState = { playerX = 0, lineY = 0 },
	}
	throw.standUp(s)
	updateTargets(s)
	camera.aim(s.aimCam, s.playerX, s.playerY, s.swivel, s.targets, throw.tune.lineY - s.playerY)
	return s
end

-- Back to aiming with everything standing (System Menu "Pitch: reset").
function throw.reset(s)
	throw.standUp(s)
	updateTargets(s)
	s.mode = "aim"
	s.pb = nil
	s.readout = nil
	swing.reset(s.swing)
	s.swing.backswing = 0
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

	-- double tap B: face straight down the pitch again. Double tap A: loft
	-- back to the default.
	s.tapA, s.tapB = s.tapA + dt, s.tapB + dt
	if p:pressed("b") then
		if s.tapA <= t.doubleTap then s.swivel = 0 end
		s.tapA = 0
	end
	if p:pressed("a") then
		if s.tapB <= t.doubleTap then s.loftDeg = flight.tune.loftDefaultDeg end
		s.tapB = 0
	end

	-- hold B: the crank swivels the player. Hold A: the crank changes the
	-- loft. Either way the crank does not throw.
	local sw = s.swing
	local holdA, holdB = p:held("b"), p:held("a")   -- holdA = swivel (B button), holdB = loft (A button)
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
	-- the stage 1 prediction: landing point and flight time for the cameras
	flight.launch(fl, s.playerX, s.playerY, s.swivel, s.loftDeg, r.launchSpeed, r.tumbleRate, r.tilt)
	-- the physics world: every piece where it lies now, then the baton
	local pieces = {}
	for i = 1, s.nitems do
		local it = s.items[i]
		pieces[i] = { id = it.id, kind = it.kind, x = it.x, y = it.y, z = it.z,
			qw = it.qw, qx = it.qx, qy = it.qy, qz = it.qz, toppled = it.toppled }
	end
	local w = phys.new { surface = s.surface, pieces = pieces }
	for i = 1, s.nitems do s.bodyIndex[i] = w.byId[s.items[i].id].index end
	local b = phys.launchBaton(w, s.playerX, s.playerY, s.swivel, s.loftDeg, r.launchSpeed, r.tumbleRate, r.tilt)
	s.batonIndex = b.index
	s.pb = playback.new(w, 1 / t.refreshRate)
	s.showTime = 0
	s.result = nil
	s.focusX, s.focusY = fl.lx, fl.ly
	s.side = (fl.lx > 0) and 1 or -1
	camera.impact(s.impactCam, fl.lx, fl.ly, fl.dx, fl.dy, s.side)
	s.last = s.last or {}
	local l = s.last
	l.power, l.smoothness, l.tilt, l.legal = r.power, r.smoothness, r.tilt, r.legal
	l.launchSpeed, l.tumbleRate, l.loft = r.launchSpeed, r.tumbleRate, s.loftDeg
	l.distance, l.down, l.hit = nil, nil, nil
	s.readout = nil
	s.mode = "flight"
	s.throws = s.throws + 1
end

-- Show recorded frame f: move the items that ever moved and the baton.
local function showFrame(s, f)
	local pb = s.pb
	for i = 1, s.nitems do
		local bi = s.bodyIndex[i]
		local rec = pb.rec[bi]
		if rec.start >= 0 and f >= rec.start then
			render.setPose(s.items[i], playback.pose(pb, bi, f))
		end
	end
	local x, y, z, qw, qx, qy, qz = playback.pose(pb, s.batonIndex, f)
	local fl, bt = s.flight, s.baton
	fl.x, fl.y, fl.z = x, y, z
	fl.t = f * pb.frameDt
	bt.x, bt.y, bt.z = x, y, z
	-- the baton's long axis: column 3 of the rotation matrix
	bt.ax = 2 * (qx * qz + qw * qy)
	bt.ay = 2 * (qy * qz - qw * qx)
	bt.az = 1 - 2 * (qx * qx + qy * qy)
end

local function landed(s)
	local fl = s.flight
	local l = s.last
	local w = s.pb.w
	local res = phys.result(w)
	s.result = res
	-- the throw's length: from the release to where the baton first touched
	-- anything (the ground, a kubb or a stake), as in stage 1
	local fc = w.firstContact
	local ex, ey = fl.x, fl.y
	if fc then ex, ey = fc.x, fc.y end
	l.distance = sqrt((ex - fl.ox) ^ 2 + (ey - fl.oy) ^ 2)
	l.landX, l.landY = ex, ey
	l.down = #res.toppled
	l.hit = w.firstHit and w.firstHit.with or nil
	for i = 1, s.nitems do
		local it = s.items[i]
		local rb = res.bodies[it.id]
		render.setPose(it, rb.x, rb.y, rb.z, rb.qw, rb.qx, rb.qy, rb.qz)
		it.toppled = rb.toppled
	end
	s.readout = hud.readoutText(l)
	local r = s.swing.result
	r.loft, r.distance = s.loftDeg, l.distance
	tw.recorder.write("release", r)
	r.loft, r.distance = nil, nil
	s.mode = "rest"
	s.restTime = 0
end

-- Are all the far base kubbs down?
local function baseDown(s)
	local any = false
	for i = 1, s.nitems do
		local it = s.items[i]
		if it.base then
			if not it.toppled then return false end
			any = true
		end
	end
	return any
end

local function flightUpdate(s, dt)
	local t = throw.tune
	local pb = s.pb
	playback.advance(pb, t.physicsBudget, s.clock, t.ahead)
	-- real time on screen, but never past what is recorded (then it slows)
	s.showTime = min(s.showTime + dt, pb.frames * pb.frameDt)
	-- the nearest frame (floor would stop one short of the last on 32-bit floats)
	local f = min(pb.frames, floor(s.showTime / pb.frameDt + 0.5))
	if f ~= pb.frame or f == 0 then
		pb.frame = f
		showFrame(s, f)
	end
	-- the impact camera slews to the first body hit once the physics knows it
	local w, fl = pb.w, s.flight
	local tx, ty = fl.lx, fl.ly
	local hit = w.firstHit
	if hit then tx, ty = hit.x, hit.y end
	local dx, dy = tx - s.focusX, ty - s.focusY
	local d, step = sqrt(dx * dx + dy * dy), t.focusSpeed * dt
	if d > step then dx, dy = dx * step / d, dy * step / d end
	s.focusX, s.focusY = s.focusX + dx, s.focusY + dy
	camera.impact(s.impactCam, s.focusX, s.focusY, fl.dx, fl.dy, s.side)
	if pb.done and pb.frame >= pb.frames then landed(s) end
end

function throw.update(s)
	local p = s.input
	p:advance()
	local dt = p:dt()
	local t = throw.tune
	if s.mode == "aim" then
		local ev = aimInput(s, dt)
		camera.aim(s.aimCam, s.playerX, s.playerY, s.swivel, s.targets, throw.tune.lineY - s.playerY)
		if ev == "release" then
			launch(s)
			showFrame(s, 0)
		end
	elseif s.mode == "flight" then
		flightUpdate(s, dt)
	else
		s.restTime = s.restTime + dt
		if s.restTime >= t.restHold then
			s.mode = "aim"
			-- the crank may have moved during the flight: arming needs a fresh
			-- crossing of the bottom, seen from aim mode
			s.arm, s.armed = nil, false
			s.pb = nil
			swing.reset(s.swing)
			s.swing.backswing = 0
			if baseDown(s) then throw.standUp(s) end
			updateTargets(s)
		end
	end
	-- the camera for this frame
	if s.mode == "aim" then
		s.viewCam = s.aimCam
	else
		-- once the baton has touched something it is kept in frame only
		-- within frameRadius of the impact point: a baton kicking on down
		-- the lawn does not drag the camera away from the kubbs it knocked over
		local fl = s.flight
		local bx, by = fl.x, fl.y
		local fc = s.pb and s.pb.w.firstContact
		if fc and s.showTime >= fc.t then
			local dx, dy = bx - s.focusX, by - s.focusY
			local d, R = sqrt(dx * dx + dy * dy), t.frameRadius
			if d > R then bx, by = s.focusX + dx * R / d, s.focusY + dy * R / d end
		end
		camera.follow(s.view, s.aimCam, s.impactCam, flight.progress(fl), bx, by, fl.z)
		s.viewCam = s.view
	end
end

function throw.draw(s)
	local b = nil
	if s.mode ~= "aim" then b = s.baton end
	render.draw(s.viewCam or s.aimCam, s.items, s.nitems, b)

	local hs = s.hudState
	hs.playerX, hs.lineY = s.playerX, s.playerY
	hs.aimX, hs.aimY = flight.aimPreview(s.playerX, s.playerY, s.swivel, s.loftDeg, swing.tune.launchMax)
	hs.baton = b
	hs.pieces, hs.npieces = s.items, s.nitems
	local fl = s.flight
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
