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
--
-- Drilling (core/drill, DESIGN "Kubbs (drilling)"): with s.drill on, a kubb
-- is aimed with a landing marker instead. The d-pad moves the marker over
-- the far half, the thrower stands on the baseline straight behind it, A or
-- B held at the release cuts the kubb, and the crank swing is judged against
-- the power band the marker's distance needs. The aim camera is then a
-- high view of the far half (camera.drillAim) that steps sideways with the
-- thrower. The match's kubb throws drill; the practice pitch
-- drills when "Pitch: drill" is chosen, and the drilled kubbs stay where they
-- end until "Pitch: reset".
import "CoreLibs/graphics"
import "core/tw"
import "core/camera"
import "core/swing"
import "core/flight"
import "core/pitch"
import "core/world"
import "core/playback"
import "core/quat"
import "render/world"
import "render/hud"
import "render/burst"
import "recorder"
import "framelog"
import "core/frametel"
import "core/drill"

local gfx <const> = playdate.graphics
local camera, swing, flight, pitch = tw.camera, tw.swing, tw.flight, tw.pitch
local phys, playback, frametel, drill = tw.world, tw.playback, tw.frametel, tw.drill
local render, hud, burst = tw.render.world, tw.render.hud, tw.render.burst
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
	-- The flight's pacing (AGENTS.md "Playback"). In flight the display runs
	-- unlocked (flightRate 0: the next frame starts when this one is done)
	-- and each frame gives the physics what is left of framePeriod after the
	-- frame's own work (update, draw and the display, each estimated from
	-- the frames before). So frames come at a steady framePeriod instead of
	-- whatever multiple of 20 ms the work happened to round up to.
	flightRate = 0,       -- refresh rate in flight (0: unlocked)
	framePeriod = 0.040,  -- s per flight frame (25 fps): the physics gets the rest of it
	tailPeriod = 0.100,   -- s per frame while the picture holds still for the calm tail
	minBudget = 0.003,    -- s the physics always gets in a flight frame
	-- the draw and display estimates follow a slower frame by this share of
	-- the step up and a faster one by a quarter of the step down. 1 (straight
	-- up to the worst frame) left the physics 1.7 ms a frame short of what
	-- the draw really took; a quarter gave 0.45 of real time against 0.38 on
	-- the device with the frame spread unchanged (2026-11-13).
	estRise = 0.25,
	physicsBudget = 0.012,-- s per frame when the frame clock is not the device's (scripted input)
	ahead = 50,           -- frames the physics may record ahead of the screen (1 s)
	focusSpeed = 4,       -- m/s the impact camera's aim point slews toward the first hit
	frameRadius = 1.5,    -- m from the impact point within which the camera keeps the baton in frame
	tossTumble = 0.5,     -- a lobbed kubb turns end over end at this fraction of the swing's
	                      -- tumble rate (guess: it is heavier and thrown softer than a baton)
	instantHold = 0.1,    -- s the rest hold lasts in instant mode (self-tests)
	drillKeep = 10,       -- drilled kubbs kept on the practice pitch; the oldest goes past this
	markerRadius = 0.2,   -- m: the drill marker's ring on the ground
	markerSegments = 12,  -- straight pieces the ring is drawn with
}

-- The match (scenes/match) uses the same scene with these per-scene fields,
-- all optional; the practice pitch sets none of them and behaves as before:
--   s.lineY, s.forwardY  the baseline and how far forward the thrower may
--                        walk (the advantage line); both default to tune.lineY
--   s.projectile         "baton" (default) or "kubb", with s.projectileId (the
--                        kubb's id, or the baton's body id: "baton" by default)
--   s.auto = false       after the rest hold, stop in mode "done" (the match
--                        resolves the throw and sets the next one up) instead of
--                        aiming again
--   s.targetIds          ids of the live targets the aim camera frames, in
--                        place of "standing kubbs in the far half"; with them the
--                        camera also looks nearer (camera.lookDistFor)
--   s.advY               the advantage line to draw (pitch and minimap)
--   s.instant            show a throw's last frame at once (self-tests)
--   s.scripted           launched by throw.autoLaunch, not the crank: no trace written
--   s.drill              aim kubbs with the drill marker (set by throw.prepare for a
--                        kubb throw; throw.setDrill on the practice pitch)

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

-- Use the match's pieces (core/outcome pieces: id, kind, x, y, qw..qz,
-- toppled, in the view frame), each resting on the ground. Reuses the items.
local function restZ(it, qw, qx, qy, qz)
	-- the half-extent of the box along z: how high its center sits on the ground
	local _, _, _, _, _, _, r31, r32, r33 = tw.quat.toMatrix(qw, qx, qy, qz)
	return abs(r31) * it.hx + abs(r32) * it.hy + abs(r33) * it.hz
end
-- `debris` (optional, core/debris pieces) follows the pieces: batons and
-- kubbs lying where earlier throws of the turn left them, each with its full
-- pose and height. A piece with z (an exact rest pose) keeps it.
local function setItem(s, i, p)
	local items = s.items
	local it = items[i]
	if not it or it.id ~= p.id or it.kind ~= p.kind then
		it = render.item(p.id, p.kind)
		items[i] = it
	end
	render.setPose(it, p.x, p.y, p.z or restZ(it, p.qw, p.qx, p.qy, p.qz), p.qw, p.qx, p.qy, p.qz)
	it.toppled = p.toppled
	it.base = nil
end
function throw.setPieces(s, pieces, debris)
	local items = s.items
	local n = #pieces
	for i, p in ipairs(pieces) do setItem(s, i, p) end
	if debris then
		for i, p in ipairs(debris) do setItem(s, n + i, p) end
		n = n + #debris
	end
	for i = n + 1, #items do items[i] = nil end
	s.nitems = n
	s.projItem = nil
end

-- Live targets for the aim camera's framing rule: the standing kubbs in the
-- far half, or the standing pieces named by s.targetIds (reused table).
local function updateTargets(s)
	local tg, n = s.targets, 0
	local ids = s.targetIds
	for i = 1, s.nitems do
		local it = s.items[i]
		if ids then
			if not it.toppled then
				for j = 1, #ids do
					if ids[j] == it.id then
						n = n + 1
						tg[n] = it
						break
					end
				end
			end
		elseif not it.toppled and not it.king and it.y > throw.tune.lineY + 4 then
			n = n + 1
			tg[n] = it
		end
	end
	for i = n + 1, #tg do tg[i] = nil end
end

-- The aim camera for this frame.
local function aimCamera(s)
	if s.drill then
		camera.drillAim(s.aimCam, s.lineY, s.playerX)
		return
	end
	local tg = s.targets
	local look = nil
	if s.targetIds then look = camera.lookDistFor(s.playerX, s.playerY, tg, #tg) end
	local back = s.lineY - s.playerY
	if back < 0 then back = 0 end
	camera.aim(s.aimCam, s.playerX, s.playerY, s.swivel, tg, back, look)
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
		showReadout = false,     -- System Menu "Readout"
		flagText = nil,          -- the result flag after a release (12 characters at most)
		-- the rail (hud.rail): practice until throw.setRail says otherwise
		railName = "PRACTICE", railKind = nil, railN = 0, railOf = 0, railR1 = nil, railR2 = nil,
		railDm = nil, railDist = nil,
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
		frameStart = 0,          -- clock() when this frame's update began
		drawEst = 0.018,         -- s the world and HUD take to draw (estimated per frame)
		postEst = 0.002,         -- s from the end of the draw to the next frame (the display)
		held = 0,                -- flight frames the picture held still for the calm tail
		baton = { x = 0, y = 0, z = 0, ax = 0, ay = 0, az = 1 },
		hudState = { playerX = 0, lineY = 0 },
		burst = tw.render.burst.new(), -- the hit burst (render/burst)
		lineY = throw.tune.lineY, forwardY = throw.tune.lineY,
		projectile = "baton", projectileId = nil, projItem = nil,
		auto = true,
		sceneName = "practice",  -- or "match": the frame-time log's scene
		ft = frametel.new(),     -- this throw's frame times (core/frametel), reset per throw
		ftInfo = {},             -- the rest of its log line, filled once at rest
		drill = false,           -- aim kubbs with the drill marker
		thisDrill = false,       -- the throw in the air (or at rest) was drilled
		markerX = 0, markerY = 0, markerHeld = 0, markerSide = nil,
		cut = 0,                 -- drill.CUT_NONE / CUT_A / CUT_B, from A or B held
		drillSol = {},           -- core/drill solution for the marker (reused)
		drillLaunch = {},        -- core/drill launch of the last drill (reused)
		drillSeq = 0,            -- practice: drilled kubbs thrown (their ids)
	}
	throw.standUp(s)
	updateTargets(s)
	aimCamera(s)
	return s
end

-- The drill solution for the marker; the thrower stands where it says.
local function solveDrill(s)
	local sol = drill.solve(s.markerX, s.markerY, s.lineY, s.drillSol)
	s.playerX, s.playerY, s.swivel, s.loftDeg = sol.x, s.lineY, sol.swivel, sol.loft
end

local function markerHome(s)
	s.markerX, s.markerY = 0, s.lineY + drill.tune.markerStartY
end

-- The match: set the next throw up. `setup` is a core/match setup (view
-- frame): its pieces and debris, projectile, lines and targets. The thrower starts in
-- the middle of the baseline facing straight down the pitch.
function throw.prepare(s, setup)
	burst.reset(s.burst)
	throw.setPieces(s, setup.pieces, setup.debris)
	s.lineY, s.forwardY, s.advY = setup.lineY, setup.forwardY or setup.lineY, setup.advY
	s.projectile, s.projectileId = setup.projectile, setup.kubb or setup.batonId
	s.targetIds = setup.targets
	s.auto = false
	s.playerX, s.playerY, s.swivel = 0, setup.lineY, 0
	s.loftDeg = flight.tune.loftDefaultDeg
	-- a kubb is drilled; the marker stays where the team left it last throw
	local drilling = setup.projectile == "kubb"
	if drilling then
		if not (s.drill and s.markerSide == setup.side) then markerHome(s) end
		s.markerSide = setup.side
		s.drill = true
		solveDrill(s)
	else
		s.drill = false
	end
	s.thisDrill = false
	s.mode = "aim"
	s.pb, s.result, s.readout, s.last, s.flagText = nil, nil, nil, nil, nil
	s.slowMo = false
	burst.reset(s.burst)
	s.arm, s.armed = nil, false
	swing.reset(s.swing)
	s.swing.backswing = 0
	updateTargets(s)
	aimCamera(s)
	s.viewCam = s.aimCam
end

-- Practice: drill kubbs at the far half (on) or throw batons (off). Back to
-- aiming; drilled kubbs already on the pitch stay until a reset.
function throw.setDrill(s, on)
	if s.mode ~= "aim" then
		-- a throw is in the air: switch once it is back to aiming
		s.pendingDrill = on and true or false
		return false
	end
	s.pendingDrill = nil
	s.drill = on and true or false
	s.projectile = on and "kubb" or "baton"
	s.projectileId = nil
	if on then
		markerHome(s)
		solveDrill(s)
	else
		s.playerX, s.playerY, s.swivel, s.loftDeg = 0, s.lineY, 0, flight.tune.loftDefaultDeg
	end
	s.arm, s.armed = nil, false
	swing.reset(s.swing)
	s.swing.backswing = 0
	s.readout, s.last, s.flagText = nil, nil, nil
	aimCamera(s)
	return true
end

-- Back to aiming with everything standing (System Menu "Pitch: reset").
function throw.reset(s)
	throw.standUp(s)
	s.projItem, s.thisDrill = nil, false
	updateTargets(s)
	s.mode = "aim"
	s.pb = nil
	s.readout = nil
	burst.reset(s.burst)     -- a burst (or the king's inverted flash) must not outlive the throw
	swing.reset(s.swing)
	s.swing.backswing = 0
end

local swingInput, drawMarker, drawRail

local function aimInput(s, dt)
	local t = throw.tune
	local p = s.input
	local left, right = p:held("left"), p:held("right")
	local up, down = p:held("up"), p:held("down")
	local delta = p:crank()
	local arm = swing.armAngle(p:crankPos())
	local prevArm = s.arm
	s.arm = arm

	local dx = (right and 1 or 0) - (left and 1 or 0)
	local dy = (up and 1 or 0) - (down and 1 or 0)
	local sw = s.swing
	if s.drill then
		-- d-pad: the marker, across and along, faster the longer it is held
		if dx ~= 0 or dy ~= 0 then
			local dtn = drill.tune
			s.markerHeld = s.markerHeld + dt
			local v = min(dtn.markerSpeedMax, dtn.markerSpeed + dtn.markerAccel * s.markerHeld)
			local mx, my = drill.clampMarker(s.markerX + dx * v * dt, s.markerY - s.lineY + dy * v * dt)
			s.markerX, s.markerY = mx, s.lineY + my
			solveDrill(s)
		else
			s.markerHeld = 0
		end
		-- A or B held: the cut, read again every frame up to the release
		s.cut = p:held("a") and drill.CUT_A or (p:held("b") and drill.CUT_B or drill.CUT_NONE)
		return swingInput(s, sw, delta, arm, prevArm, dt)
	end
	-- d-pad: walk. Left/right along the line, down steps back from it, up
	-- comes forward again as far as the line (in a match, as far as the
	-- advantage line when the engine allows it: s.forwardY).
	if dx ~= 0 then
		s.playerX = max(-t.halfWidth, min(t.halfWidth, s.playerX + dx * t.walkSpeed * dt))
	end
	if dy ~= 0 then
		s.playerY = max(s.lineY - t.backMax, min(s.forwardY, s.playerY + dy * t.walkSpeed * dt))
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
	return swingInput(s, sw, delta, arm, prevArm, dt)
end

-- The crank throws: arming at the bottom of the turn, the wind-up and the
-- flick (core/swing), with the trace recorder fed alongside.
swingInput = function(s, sw, delta, arm, prevArm, dt)
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

-- Launch the throw `r` (the swing's result: launchSpeed, tumbleRate, tilt,
-- power, smoothness, legal) from where the player stands and aims.
local function launch(s, r)
	local t = throw.tune
	local fl = s.flight
	local kubb = s.projectile == "kubb"
	local tumble, tilt, speed = r.tumbleRate, r.tilt, r.launchSpeed
	-- a lobbed kubb: slower end over end, never sideways (no helicopter)
	if kubb then tumble, tilt = tumble * t.tossTumble, 0 end
	-- a drilled kubb (not the computer's: it lobs): the launch the drill
	-- solution and the swing make (core/drill)
	local drilling = kubb and s.drill and (not s.scripted or s.autoDrill)
	local L
	if drilling then
		local sol = s.drillSol
		L = drill.launch(sol, r, s.cut, s.drillLaunch)
		s.playerX, s.playerY, s.swivel, s.loftDeg = sol.x, s.lineY, L.swivel, L.loft
		speed, tumble = L.speed, 0
		if not s.projectileId then
			-- practice: each drilled kubb is a piece of its own
			s.drillSeq = s.drillSeq + 1
			s.drillId = "d" .. s.drillSeq
		end
	end
	s.thisDrill = drilling
	local id = s.projectileId or (drilling and s.drillId) or nil
	-- the stage 1 prediction: landing point and flight time for the cameras
	flight.launch(fl, s.playerX, s.playerY, s.swivel, s.loftDeg, speed, tumble, tilt)
	-- the physics world: every piece where it lies now, then the baton
	local pieces = {}
	for i = 1, s.nitems do
		local it = s.items[i]
		pieces[i] = { id = it.id, kind = it.kind, x = it.x, y = it.y, z = it.z,
			qw = it.qw, qx = it.qx, qy = it.qy, qz = it.qz, toppled = it.toppled }
	end
	local w = phys.new { surface = s.surface, pieces = pieces }
	for i = 1, s.nitems do s.bodyIndex[i] = w.byId[s.items[i].id].index end
	local b
	if kubb then
		if drilling then
			b = phys.launchDrill(w, id, s.playerX, s.playerY, L.swivel, L.loft, L.speed, L.noseDown, L.rollLand,
				L.spin, L.wobble, L.digGain)
		else
			b = phys.launchKubb(w, id, s.playerX, s.playerY, s.swivel, s.loftDeg, speed, tumble)
		end
		-- the thrown kubb is drawn as one more item after the pitch's
		local it = s.projItem
		if not it or it.id ~= id then
			it = render.item(id, "kubb")
			s.projItem = it
		end
		s.items[s.nitems + 1] = it
	else
		b = phys.launchBaton(w, s.playerX, s.playerY, s.swivel, s.loftDeg, r.launchSpeed, tumble, tilt,
			s.projectileId)
	end
	s.batonIndex = b.index
	s.pb = playback.new(w, 1 / t.refreshRate)
	s.pb.v = 1
	frametel.reset(s.ft)
	s.showTime = 0
	s.held = 0
	if playdate and not s.instant then playdate.display.setRefreshRate(t.flightRate) end
	s.result = nil
	s.focusX, s.focusY = fl.lx, fl.ly
	s.side = (fl.lx > 0) and 1 or -1
	camera.impact(s.impactCam, fl.lx, fl.ly, fl.dx, fl.dy, s.side)
	s.last = s.last or {}
	local l = s.last
	l.power, l.smoothness, l.tilt, l.legal = r.power, r.smoothness, tilt, kubb or r.legal
	l.launchSpeed, l.tumbleRate, l.loft = speed, tumble, s.loftDeg
	l.distance, l.down, l.hit = nil, nil, nil
	l.drill = drilling
	if drilling then
		local sol = s.drillSol
		l.markerX, l.markerY, l.band = s.markerX, s.markerY, sol.band
		l.verdict = drill.judge(r.power or 0, sol.band)
		l.cut, l.jerk = s.cut, L.jerk
		l.restX, l.restY = nil, nil
	end
	s.readout = nil
	-- the result flag: a helicopter shows from the release, the rest at rest
	s.flagText = (not l.legal) and "HELICOPTER" or nil
	s.mode = "flight"
	s.throws = s.throws + 1
end

-- Show the throw at time t (s from the release, between recorded frames):
-- move the items that ever moved and the baton.
local function showAt(s, t)
	local pb = s.pb
	local f = t / pb.frameDt
	for i = 1, s.nitems do
		local bi = s.bodyIndex[i]
		local rec = pb.rec[bi]
		if rec.start >= 0 and f > rec.start - 1 then
			render.setPose(s.items[i], playback.poseAt(pb, bi, t))
		end
	end
	local x, y, z, qw, qx, qy, qz = playback.poseAt(pb, s.batonIndex, t)
	if s.projectile == "kubb" then render.setPose(s.projItem, x, y, z, qw, qx, qy, qz) end
	local fl, bt = s.flight, s.baton
	fl.x, fl.y, fl.z = x, y, z
	fl.t = t
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
	if s.projectile == "kubb" then
		local rb = res.bodies[s.projItem.id]
		render.setPose(s.projItem, rb.x, rb.y, rb.z, rb.qw, rb.qx, rb.qy, rb.qz)
		s.projItem.toppled = rb.toppled
		if l.drill then l.restX, l.restY = rb.x, rb.y end
	end
	s.readout = l.drill and hud.drillReadoutText(l) or hud.readoutText(l)
	if l.drill and l.restX then
		l.restCm = floor(100 * sqrt((l.restX - l.markerX) ^ 2 + (l.restY - l.markerY) ^ 2) + 0.5)
	end
	-- the result flag (a match puts its own ruling there: throw.setFlag)
	if not l.legal then s.flagText = "HELICOPTER"
	elseif l.drill then s.flagText = nil
	elseif l.down > 0 then s.flagText = l.down .. " DOWN"
	else s.flagText = "MISS" end
	if not s.instant then
		-- the frame-time log: one line per throw, now that it is at rest
		local info, pb = s.ftInfo, s.pb
		info.scene, info.proj = s.sceneName, l.drill and "drill" or s.projectile
		info.awake, info.contacts, info.bodies = pb.awakeMax, pb.contactsMax, w.n
		info.steps, info.phys = pb.steps, pb.busy
		tw.framelog.write(s.ft, info)
	end
	if not s.scripted then
		local r = s.swing.result
		r.loft, r.distance = s.loftDeg, l.distance
		if l.drill then
			-- drill fields (core/trace): lengths from the thrower's baseline
			local y0 = s.lineY
			r.mode, r.band, r.verdict, r.cut = "drill", l.band, l.verdict, l.cut
			r.markerX, r.markerY = l.markerX, l.markerY - y0
			r.landX, r.landY = l.landX, l.landY - y0
			r.restX, r.restY = l.restX, l.restY - y0
			r.throwerX, r.launchSpeed = s.playerX, l.launchSpeed
		end
		tw.recorder.write("release", r)
		r.loft, r.distance = nil, nil
		r.mode, r.band, r.verdict, r.cut, r.markerX, r.markerY = nil, nil, nil, nil, nil, nil
		r.landX, r.landY, r.restX, r.restY, r.throwerX = nil, nil, nil, nil, nil
	end
	s.mode = "rest"
	s.restTime = 0
	if playdate and not s.instant then playdate.display.setRefreshRate(throw.tune.refreshRate) end
end

-- Practice: the drilled kubb at rest becomes a piece of the pitch, and the
-- oldest drilled kubb goes once there are more than tune.drillKeep.
local function keepDrilled(s)
	local it = s.projItem
	s.projItem = nil
	if not it then return end
	it.drilled = true
	s.nitems = s.nitems + 1
	s.items[s.nitems] = it
	local n = 0
	for i = 1, s.nitems do
		if s.items[i].drilled then n = n + 1 end
	end
	if n > throw.tune.drillKeep then
		for i = 1, s.nitems do
			if s.items[i].drilled then
				table.remove(s.items, i)
				s.nitems = s.nitems - 1
				break
			end
		end
	end
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
	if s.instant then
		-- self-tests: run the throw to rest now and show its last frame
		playback.finish(pb)
		pb.frame = pb.frames
		s.showTime = pb.frames * pb.frameDt
		showAt(s, s.showTime)
		landed(s)
		return
	end
	-- the calm tail (core/playback.calm): nothing visibly moves any more, so
	-- the picture holds and the physics gets nearly the whole frame
	local tail = pb.calmFrom and s.showTime >= pb.calmFrom * pb.frameDt
	-- the physics gets what is left of the frame: the period, less the time
	-- this update has taken so far and the draw and the display to come
	local budget = t.physicsBudget
	if s.input.raw then
		budget = (tail and t.tailPeriod or t.framePeriod) - (s.clock() - s.frameStart) - s.drawEst - s.postEst
		if budget < t.minBudget then budget = t.minBudget end
	end
	-- (no look-ahead cap in the tail: the picture is held, so the cap would
	-- never move and a calm body that cannot sleep would stop the physics
	-- short of rest for good)
	playback.advance(pb, budget, s.clock, (not tail) and t.ahead or nil)
	-- real time on screen, slow motion around the first hit (the physics is
	-- ahead, so the hit is known before it is shown), and slower still when
	-- the physics cannot keep up (playback.pace: a steady ease, so the
	-- picture never has to stop and wait), never past what is recorded
	local hitAt = pb.w.firstHit and pb.w.firstHit.t or nil
	local slow = playback.speed(s.showTime, hitAt)
	s.slowMo = slow < 1     -- the HUD's slow motion flag
	local pace = playback.pace(pb, s.showTime, dt)
	local speed = min(slow, pace)
	local have = pb.frames * pb.frameDt
	local want = s.showTime + dt * speed
	-- starved: the picture had to wait for the physics this frame
	local starved = want > have and not pb.done and not tail
	frametel.frame(s.ft, s.input.raw or dt, slow, starved)
	local shown = s.showTime
	if tail then
		-- hold until the throw is at rest, then show its last frame (what
		-- moves in the calm moves by a few millimetres)
		if pb.done then s.showTime = have else s.held = s.held + 1 end
	else
		s.showTime = min(want, have)
	end
	pb.frame = min(pb.frames, floor(s.showTime / pb.frameDt + 0.5))
	if s.showTime ~= shown or pb.frames == 0 then showAt(s, s.showTime) end
	-- the impact camera slews to the first body hit once the physics knows it
	local w, fl = pb.w, s.flight
	local tx, ty = fl.lx, fl.ly
	local hit = w.firstHit
	if hit then tx, ty = hit.x, hit.y end
	local dx, dy = tx - s.focusX, ty - s.focusY
	local d, step = sqrt(dx * dx + dy * dy), t.focusSpeed * dt
	if d > step then dx, dy = dx * step / d, dy * step / d end
	-- (held still in the calm tail, so the held picture is one cached image)
	if not tail then s.focusX, s.focusY = s.focusX + dx, s.focusY + dy end
	camera.impact(s.impactCam, s.focusX, s.focusY, fl.dx, fl.dy, s.side)
	if pb.done and s.showTime >= have then landed(s) end
end

function throw.update(s)
	local p = s.input
	p:advance()
	local dt = p:dt()
	-- the frame clock: when this frame started, and how long the last one's
	-- draw and display took (fast up, slow down: the budget errs short)
	s.frameStart = s.clock()
	if p.raw and s.drawEnd then
		local post = p.raw - s.drawEnd
		if post < 0 then post = 0 end
		local up = throw.tune.estRise
		s.postEst = s.postEst + (post - s.postEst) * ((post > s.postEst) and up or 0.25)
		local d = s.drawEnd - s.drawStart
		s.drawEst = s.drawEst + (d - s.drawEst) * ((d > s.drawEst) and up or 0.25)
	end
	s.drawEnd = nil
	local t = throw.tune
	if s.mode == "aim" then
		local ev = aimInput(s, dt)
		aimCamera(s)
		if ev == "release" then
			s.scripted = false
			launch(s, s.swing.result)
			showAt(s, 0)
		end
	elseif s.mode == "flight" then
		flightUpdate(s, dt)
		burst.update(s.burst, s, dt)
	elseif s.mode == "rest" then
		burst.update(s.burst, s, dt)
		s.restTime = s.restTime + dt
		if not s.auto and s.restTime >= (s.instant and t.instantHold or t.restHold) then
			-- the match takes it from here (throw.prepare sets the next throw up)
			s.mode = "done"
		elseif s.restTime >= t.restHold then
			s.mode = "aim"
			-- the crank may have moved during the flight: arming needs a fresh
			-- crossing of the bottom, seen from aim mode
			s.arm, s.armed = nil, false
			s.pb = nil
			burst.reset(s.burst)
			swing.reset(s.swing)
			s.swing.backswing = 0
			if s.thisDrill then
				keepDrilled(s)
			elseif baseDown(s) then
				throw.standUp(s)
			end
			s.thisDrill = false
			if s.pendingDrill ~= nil then throw.setDrill(s, s.pendingDrill) end
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

-- A scripted throw (self-tests, and stage 5's computer can grow from it):
-- `a` is a core/autothrow throw {x, y, swivel, loftDeg, speed, tumbleRate,
-- tilt, legal}. The player is put where it says and the throw launched as if
-- the crank had made it. Only in aim mode. With a.drill = {markerX, markerY}
-- and s.drill on (the autobench's match case), the kubb is drilled at that
-- marker instead: a clean swing at the band's center, no cut.
function throw.autoLaunch(s, a)
	assert(s.mode == "aim", "autoLaunch while " .. s.mode)
	s.playerX, s.playerY, s.swivel, s.loftDeg = a.x, a.y, a.swivel, a.loftDeg
	s.scripted = true
	local r = s.autoResult or {}
	s.autoResult = r
	r.launchSpeed, r.tumbleRate, r.tilt, r.legal = a.speed, a.tumbleRate, a.tilt or 0, a.legal ~= false
	r.power = (a.speed - swing.tune.launchMin) / (swing.tune.launchMax - swing.tune.launchMin)
	r.smoothness = 1
	s.autoDrill = (a.drill ~= nil) and s.drill
	if s.autoDrill then
		s.markerX, s.markerY = a.drill.markerX, s.lineY + a.drill.markerY
		solveDrill(s)
		s.cut = drill.CUT_NONE
		r.power, r.how = s.drillSol.band, nil
	end
	-- a.tumbleRate is the projectile's own (a kubb's too): undo the toss factor
	if s.projectile == "kubb" then r.tumbleRate = a.tumbleRate / throw.tune.tossTumble end
	launch(s, r)
	showAt(s, 0)
end

-- The drill marker on the ground: a ring with a cross in it, and a dotted
-- line to it from the thrower's spot on the baseline. Drawn over the world
-- image each frame (a few lines), so moving it leaves the cached scenery be.
local ringX, ringY = {}, {}
drawMarker = function(s, c)
	local t = throw.tune
	local mx, my = s.markerX, s.markerY
	local x0, y0, x1, y1 = camera.projectSegment(c, s.drillSol.x, s.lineY, 0, mx, my, 0)
	if x0 then
		gfx.setLineWidth(2)
		gfx.setColor(gfx.kColorBlack)
		gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer2x2)
		gfx.drawLine(x0, y0, x1, y1)
	end
	local n, R = t.markerSegments, t.markerRadius
	local ok = true
	for i = 1, n do
		local a = 2 * math.pi * i / n
		local sx, sy = camera.project(c, mx + R * math.cos(a), my + R * math.sin(a), 0)
		if not sx then ok = false break end
		ringX[i], ringY[i] = sx, sy
	end
	if not ok then return end
	-- white under black, so it reads on the grass pattern and on a kubb
	for pass = 1, 2 do
		gfx.setColor(pass == 1 and gfx.kColorWhite or gfx.kColorBlack)
		gfx.setLineWidth(pass == 1 and 4 or 2)
		local px, py = ringX[n], ringY[n]
		for i = 1, n do
			gfx.drawLine(px, py, ringX[i], ringY[i])
			px, py = ringX[i], ringY[i]
		end
		local cx, cy = camera.project(c, mx, my, 0)
		local w = (ringX[n] - ringX[n // 2]) * 0.3
		gfx.drawLine(cx - w, cy, cx + w, cy)
		gfx.drawLine(cx, cy - w * 0.6, cx, cy + w * 0.6)
	end
	gfx.setLineWidth(1)
	gfx.setColor(gfx.kColorBlack)
end

function throw.draw(s)
	s.drawStart = s.clock() - (s.frameStart or 0)
	local ok = throw.drawFrame(s)
	s.drawEnd = s.clock() - (s.frameStart or 0)
	return ok
end

function throw.drawFrame(s)
	local b = nil
	local n = s.nitems
	if s.mode ~= "aim" then
		if s.projectile == "kubb" then n = n + 1 else b = s.baton end
	end
	render.advantageY = s.advY
	local cam = s.viewCam or s.aimCam
	render.draw(cam, s.items, n, b)
	burst.draw(s.burst, cam)
	local marker = s.drill and (s.mode == "aim" or s.thisDrill)
	if marker then drawMarker(s, cam) end

	local hs = s.hudState
	hs.playerX, hs.lineY = s.playerX, s.playerY
	if marker then
		hs.aimX, hs.aimY = s.markerX, s.markerY
	else
		hs.aimX, hs.aimY = flight.aimPreview(s.playerX, s.playerY, s.swivel, s.loftDeg, swing.tune.launchMax)
	end
	hs.baton = (s.mode ~= "aim") and s.baton or nil
	hs.pieces, hs.npieces = s.items, s.nitems
	hs.advY = s.advY
	local fl = s.flight
	if s.mode ~= "aim" then
		hs.landX, hs.landY = fl.lx, fl.ly
	elseif s.last and s.last.landX then
		hs.landX, hs.landY = s.last.landX, s.last.landY
	else
		hs.landX, hs.landY = nil, nil
	end
	hud.minimap(hs)
	drawRail(s)

	-- s.covered: a card is over the pitch (the match's hand-off and winner
	-- cards), so the plaques stay out of the way
	if s.covered then return end
	local half = drill.tune.bandHalf
	local sw = s.swing
	local l = s.last
	if s.mode == "aim" then
		local cap = (sw.phase ~= "idle") and swing.powerCap(sw) or nil
		local band = marker and s.drillSol.band or nil
		hud.plaque(s.loftDeg, cap, band, half)
		local prompt, inverted = hud.gauge(sw.phase, sw.angle, (sw.phase ~= "idle") and sw.backswing or 0,
			swing.tune.fullBackswingDeg, s.arm or 0, band, half)
		hud.prompt(prompt, inverted)
		s.promptText = prompt    -- (self-tests read it)
		if marker and s.cut ~= drill.CUT_NONE then
			hud.cutFlag(s.cut == drill.CUT_A and "CUT RIGHT" or "CUT LEFT")
		end
		if s.showReadout and s.readout and sw.phase == "idle" then hud.readout(s.readout) end
		if s.input:docked() then hud.crankPrompt() end
	elseif l then
		-- after the release: the power chip and the result flag, and once a
		-- drilled kubb stops, how near the band it was
		hud.chip(l.power, l.drill and l.band or nil, half)
		hud.flag(s.flagText)
		if s.mode == "flight" and s.slowMo then hud.slow() end
		if l.drill and l.restCm and s.mode ~= "flight" then
			hud.callout(l.verdict, (l.power or 0) - l.band, half, l.restCm)
		end
		if s.showReadout and s.readout then hud.readout(s.readout) end
	end
end

-- The rail's targets on the right. Practice: the far base kubbs standing,
-- or how far the drill marker is from the baseline. Strings are made only
-- when the number changes.
local BASE, FIELD = {}, {}
for i = 0, 12 do BASE[i], FIELD[i] = "BASE " .. i, "FIELD " .. i end
throw.railBase, throw.railField = BASE, FIELD
drawRail = function(s)
	local r1, r2 = s.railR1, s.railR2
	if s.drill then
		local d = floor((s.markerY - s.lineY) * 10 + 0.5)
		if d ~= s.railDm then
			s.railDm = d
			s.railDist = string.format("%d.%d M", d // 10, d % 10)
		end
		r1, r2 = s.railDist, nil
	elseif s.railName == "PRACTICE" then
		local n = 0
		for i = 1, s.nitems do
			local it = s.items[i]
			if it.base and not it.toppled then n = n + 1 end
		end
		r1, r2 = BASE[n] or BASE[12], nil
	end
	hud.rail(s.railName, s.railKind, s.railN, s.railOf, r1, r2)
end

-- The match's rail: the team's name (capitals), "baton" | "kubb" pips, n of
-- `of`, and the targets (strings, or nil). Once per throw.
function throw.setRail(s, name, kind, n, of, r1, r2)
	s.railName, s.railKind, s.railN, s.railOf, s.railR1, s.railR2 = name, kind, n, of, r1, r2
end

-- The match's ruling on the throw, for the result flag (hud.short).
function throw.setFlag(s, text)
	s.flagText = text
end

function throw.enter()
	playdate.display.setRefreshRate(throw.tune.refreshRate)
end

tw.scenes.throw = throw
