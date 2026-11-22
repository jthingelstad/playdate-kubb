-- The throw scene: aim, wind up and flick the crank, watch the baton fly
-- and knock kubbs over, then do it again. The throw is DESIGN 4 "the crank
-- as a clock" (docs/notes/throw.md "The throw"): the d-pad moves the target circle
-- over the far half (it snaps onto a standing kubb or the king), A + d-pad
-- walks, B + d-pad plans (up/down the arc, left/right tilt or spin), the
-- crank alone throws. The swivel is always the plan's (core/throwplan): the
-- thrower faces the target. All input comes from an input provider
-- (input.lua), so self-tests drive this scene with scripted crank samples.
--
-- The throw is simulated by the rigid-body world (core/world) and shown
-- through core/playback: the physics runs ahead of the screen within its
-- budget per frame and the scene plays the recorded frames back; when the
-- physics falls behind, playback waits (slows down) rather than skipping.
-- Practice: toppled kubbs stay down between throws (they keep their rest
-- poses); throw.reset stands everything back up (the System Menu "Pitch:
-- reset"), and it happens by itself after the throw that leaves every far
-- base kubb down.
--
-- Drilling (DESIGN "Kubbs (drilling)"): a kubb throw (s.drill) is the same
-- throw: the circle is where the kubb should rest, the plan solves the clean
-- drill that rests there (from the baseline), B + left/right plans its spin.
-- The aim camera is the baton's: first person, the plan view while B is held.
-- The match's kubb throws drill; the
-- practice pitch drills when "Pitch: drill" is chosen, and the drilled kubbs
-- stay where they end until "Pitch: reset".
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
import "core/burstpick"
import "recorder"
import "framelog"
import "device/frametel"
import "device/crank"
import "core/drill"
import "core/throwplan"
import "core/howto"
import "render/howto"
import "sound"

local gfx <const> = playdate.graphics
local camera, swing, flight, pitch = tw.camera, tw.swing, tw.flight, tw.pitch
local phys, playback, frametel, drill, plan = tw.world, tw.playback, tw.frametel, tw.drill, tw.plan
local render, hud, burst = tw.render.world, tw.render.hud, tw.render.burst
local burstpick = tw.burstpick
local crank = tw.crank
local sound = tw.sound
local max, min, rad, abs, sqrt, floor = math.max, math.min, math.rad, math.abs, math.sqrt, math.floor

tw.scenes = tw.scenes or {}
local throw = {}

throw.tune = {
	refreshRate = 50,     -- fps while aiming and throwing
	tickHold = 0.3,       -- s: B + the d-pad held this long slides the plan a tick a frame (a tap: one tick)
	walkSpeed = 1.2,      -- m/s along the throwing line
	halfWidth = 2.5,      -- the line is 5 m wide (DESIGN 2)
	backMax = 3.0,        -- m the player may step back from the throwing line
	snapRadius = 0.25,    -- m: throw.aimAt puts the circle onto a standing kubb or the king this near;
	                      -- a baton's circle this near a standing target is on it (replan: aimed
	                      -- through it at plan.aimZFor's height)
	howtoTap = 0.3,       -- s: B let go within this, with no d-pad while it was down, is
	                      -- HOW TO THROW's tap (skip a step)
	halfRateM = 2.0,      -- m: a circle the d-pad moves nearer the stance than this is planned every
	                      -- other frame (aimInput; flight.tune.nearM, where the plan grows costly)
	keepNear = 1.0,       -- m: a circle moved by hand stays put for the next throw while a live
	                      -- target stands this near it (else it goes onto the nearest target)
	                      -- snaps onto it (the circle's radius, DESIGN 4)
	overDeg = 150,        -- backswing degrees past which the clock shows overpowered (11 o'clock)
	cpuSwingTime = 0.6,   -- s the Playdate's arm takes on the clock before its throw leaves
	cpuBackShare = 0.6,   -- the share of that spent going back
	-- The crank flipped (throw.flipCrank, the scene's System Menu item "flip
	-- crank"; device/crank): CRANK FLIPPED in the prompt flag for this long
	-- once the player is aiming again, so the choice is seen to have taken.
	flipNoteS = 1.5,
	-- The nudge (device/crank, Jamie 2026-11-19: a player found the crank
	-- backward): a forward turn is the idle crank going from within
	-- nudgeBottomDeg of 6 o'clock to nudgeTurnDeg or more forward; after
	-- nudgeTurns of them with no throw, a hint over the prompt says the crank
	-- can be flipped and where. A wind-up hides it; a throw clears the count.
	-- Guesses, not measured on players.
	nudgeTurns = 3,
	nudgeTurnDeg = 60,    -- 8 o'clock's mirror: 4 o'clock, well past the bottom's jitter
	nudgeBottomDeg = 20,  -- within this of 6 o'clock the crank is "at the bottom" (howto's own)
	restHold = 1.0,       -- s the landed baton stays on screen before the next baton
	lineY = 0,            -- the throwing line: Team A's baseline
	surface = "grass",    -- the practice pitch (tw.world.surfaces)
	-- The flight's pacing (docs/notes/throw.md "Playback"). In flight the display runs
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
	-- the camera's half circle round the hit (Jamie, 2026-11-13): once a burst
	-- fires, the impact camera orbits the struck piece by swingDeg over
	-- swingTime seconds of shown time from its impact, eased, so the slow
	-- motion shows the piece fall and the pitch round it; it stays there for
	-- the rest. 0 turns it off.
	swingDeg = 180,
	swingTime = 0.8,      -- s of shown time for the half circle (it runs on past the slow motion)
	-- s per flight frame while the camera turns: every one is a full draw (the
	-- layer needs a still camera), so fewer frames leave the physics its time.
	-- On the device a hit took 6.7 s release to rest at 40 ms, 4.7 at 60, 4.2
	-- with no half circle (2026-11-14); in slow motion 60 ms still reads smooth.
	swingPeriod = 0.060,
	tossTumble = 0.5,     -- a lobbed kubb turns end over end at this fraction of the swing's
	                      -- tumble rate (guess: it is heavier and thrown softer than a baton)
	instantHold = 0.1,    -- s the rest hold lasts in instant mode (self-tests)
	knockLate = 0.15,     -- s: a knock this far behind the picture is not played (sound.lua)
	drillKeep = 10,       -- drilled kubbs kept on the practice pitch; the oldest goes past this
	markerRadius = 0.25,  -- m: the target circle on the ground (0.5 m across, DESIGN 4)
	markerSegments = 12,  -- straight pieces the ring is drawn with
	-- the planned throw's arc while aiming a baton or a drill (Jamie and
	-- Tyler, 2026-11-14: "like billiards on a computer, lines that show you
	-- where it's going to go"): the plan's clean throw from the stance onto the
	-- target (a drill's down to where it lands, short of the circle)
	arc = true,           -- false: no arc
	arcPoints = 24,       -- points along the arc, release to landing (every other gap drawn: dashes)
	arcSkip = 2,          -- the first points (at the hand, under the camera) are left out
	arcWidth = 2,         -- px
	arcFitFrom = 6,       -- the plan view (camera.shoulder) keeps the arc on screen from this point
	                      -- on; before it (the first quarter, near the hand) only inside the
	                      -- sides: it may rise in from the lower edge
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
--   s.kid, s.kidY        a Kid match (engine 0.15; core/match setup.kid, setup.kidY):
--                        the Kid line to draw (pitch and minimap), which every kubb and
--                        baton at a kubb is thrown from (s.forwardY, the setup's), and a
--                        person's throw planned on the Kid meter (throw.planBy)
--   s.instant            show a throw's last frame at once (self-tests)
--   s.scripted           launched by throw.autoLaunch, not the crank: no trace written
--   s.drill              the throw is a drilled kubb (set by throw.prepare for a
--                        kubb throw; throw.setDrill on the practice pitch)
--   s.level              the thrower's throw level (plan.levels), or nil for
--                        throw.level (throw.levelFor): since engine 0.13 only the
--                        Playdate's throws go by it; a person throws on the meter
--                        (throw.planBy)
--   s.drillRun           the practice drill's id during a drill run (scenes/drills),
--                        written to the trace line
--
-- The aim (docs/notes/throw.md "The throw"): the target circle s.markerX, s.markerY
-- (view frame), the stance s.playerX, s.playerY (s.stanceSet once A has
-- walked it; until then plan.stance behind the target), the plan s.release
-- (s.arcSet once B has moved it; until then plan.arcFor by the distance from
-- the stance to the circle, engine 0.10),
-- s.tilt (baton, degrees) and s.spin (kubb, taps). s.sol is plan.solve's
-- solution for them, solved again only when one changes (s.planDirty). While
-- the d-pad moves the circle within halfRateM of the stance it is solved at most
-- every other frame (s.planSkipped; docs/notes/throw.md "The aim at a short
-- throw"): the arc may lag the circle by a frame, and a throw, a let-go circle
-- and every other change solve it at once.

-- The throw level: the scene's own (the thrower's: a named player's, or the
-- Playdate's match option COMPUTER) or throw.level (main.lua reads the old
-- System Menu "Level" kept in the datastore; the match before engine 0.9 with no
-- level on the Playdate's player falls back to it).
throw.level = plan.tune.defaultLevel
function throw.levelFor(s)
	return s.level or throw.level
end

-- What the scene's plan is solved on (engine 0.13, kubb-engine docs/notes/throw.md
-- "The person's meter"): a person's throw on the one meter (plan.meter(), the same
-- table every call), whatever level they have, and in a Kid match (s.kid, engine
-- 0.15) on the Kid meter (plan.meter("kid"): much wider bars, a soft flick forgiven;
-- "The Kid meter"); the Playdate's (s.watching) on its level. Returns the meter, or
-- nil and the level. plan.launch is then given no level for a person's throw: it
-- reads the meter's table for the distance from the solution (sol.level).
function throw.planBy(s)
	if s.watching then return nil, throw.levelFor(s) end
	if s.kid then return plan.meter("kid"), nil end
	return plan.meter(), nil
end
local function planKey(s)
	local m, lv = throw.planBy(s)
	return m or lv
end

-- The nerves (plan.tune "Nerves"): the player's throws go off the planned
-- line and length by seeded draws, as the computer's do. s.nerves (true or
-- false) overrides throw.nerves; the self-test runner turns throw.nerves off
-- so a scripted clean swing is the plan's clean throw, unless the scenario
-- asks for them (nerves = true).
throw.nerves = true
local function nervesFor(s)
	if s.nerves ~= nil then return s.nerves end
	return throw.nerves
end

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

-- How high a box's center sits on the ground at this orientation: its
-- half-extent along z (body.lowestZ for a box, what world.addPiece rests it at).
local function restZ(it, qw, qx, qy, qz)
	local _, _, _, _, _, _, r31, r32, r33 = tw.quat.toMatrix(qw, qx, qy, qz)
	return abs(r31) * it.hx + abs(r32) * it.hy + abs(r33) * it.hz
end

-- A kubb standing plumb is drawn in its seat (core 1.0: world.seat, up to the
-- surface's `seat` degrees), the pose world.addPiece will give it when the
-- throw's world is built from these items, so nothing steps at a throw's first
-- frame. Same inputs as addPiece (the view frame, this pitch's surface); a piece
-- that is not a plumb kubb comes back as given, seated false.
local function seatOf(s, kind, x, y, qw, qx, qy, qz)
	return phys.seat(s.surface or throw.tune.surface, kind, x, y, qw, qx, qy, qz)
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
		local qw, qx, qy, qz, seated = seatOf(s, p.kind, p.x, p.y, math.cos(yaw), 0, 0, math.sin(yaw))
		render.setPose(it, p.x, p.y, seated and restZ(it, qw, qx, qy, qz) or it.hz, qw, qx, qy, qz)
		it.toppled = false
		it.base = p.base
	end
	for i = #s.layout + 1, #items do items[i] = nil end
	s.nitems = #s.layout
	s.practiceBaton = 0
end

-- Use the match's pieces (core/outcome pieces: id, kind, x, y, qw..qz,
-- toppled, in the view frame), each resting on the ground. Reuses the items.
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
	-- a plumb kubb in its seat (world.addPiece then ignores a given z: it rests
	-- the seated kubb on its lowest corner)
	local qw, qx, qy, qz, seated = seatOf(s, p.kind, p.x, p.y, p.qw, p.qx, p.qy, p.qz)
	render.setPose(it, p.x, p.y, (not seated and p.z) or restZ(it, qw, qx, qy, qz), qw, qx, qy, qz)
	it.toppled = p.toppled
	it.base = nil
	it.role = p.role
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
-- far half, or the standing pieces named by s.targetIds (reused table). The
-- target circle snaps onto these, and on the practice pitch onto the king too
-- (s.snaps, reused).
local function updateTargets(s)
	local tg, n = s.targets, 0
	local sn, k = s.snaps, 0
	local ids = s.targetIds
	for i = 1, s.nitems do
		local it = s.items[i]
		if ids then
			if not it.toppled then
				for j = 1, #ids do
					if ids[j] == it.id then
						n = n + 1
						tg[n] = it
						k = k + 1
						sn[k] = it
						break
					end
				end
			end
		elseif not it.toppled and not it.drilled and not it.baton then
			-- the king stands on the centerline (y = 4), so it is a snap target
			-- although the far-half test leaves it out (Codex on #91)
			local king = it.king or it.kind == "king"
			local far = it.y > throw.tune.lineY + 4
			if far and not king then
				n = n + 1
				tg[n] = it
			end
			if far or king then
				k = k + 1
				sn[k] = it
			end
		end
	end
	for i = n + 1, #tg do tg[i] = nil end
	for i = k + 1, #sn do sn[i] = nil end
end

-- Use another layout ({id, kind, x, y, yaw, base} list) and stand it up.
function throw.setLayout(s, layout)
	s.layout = layout
	throw.standUp(s)
	updateTargets(s)
	s.planDirty = true
end

-- What kind of target a piece is: "king", "field" or "base" (until engine 0.10 the
-- arc the plan starts on; now plan.arcFor goes by the distance, throw.defaultArc).
local function kindOf(it)
	if it.king or it.kind == "king" then return "king" end
	if it.role == "field" then return "field" end
	return "base"
end

-- The aim camera for this frame (docs/notes/throw.md "The aim camera"): first person
-- (camera.aim, straight behind the thrower, looking circleBeyond past the
-- target circle), and while B is held the plan view over the shoulder
-- (camera.shoulder, fitted to the target half, the planned arc and the
-- circle), the two blended by s.camMix (0 first person, 1 the plan view;
-- throw.update moves it over camera.tune.shoulder.time, eased). `k` (0 to 1,
-- default 1) is how far the plan view's lens and principal point go toward
-- this frame's fit: throw.update eases them (a tap of the arc re-fits the view
-- without a jump); every other caller snaps. No tables.
local shoulderFit   -- (below, with drawArc)

local function aimCamera(s, k)
	local mix = s.camMix
	local fp = (mix > 0) and s.fpCam or s.aimCam
	local look
	if not s.watching or s.cpuTarget then
		look = camera.lookDistAt(s.playerX, s.playerY, s.markerX, s.markerY)
	elseif s.targetIds then
		look = camera.lookDistFor(s.playerX, s.playerY, s.targets, #s.targets)
	end
	local back = s.lineY - s.playerY
	if back < 0 then back = 0 end
	camera.aim(fp, s.playerX, s.playerY, s.swivel, s.targets, back, look)
	-- a close target (an advantage line near the middle) stays on screen:
	-- the circle's near edge, along the line from the thrower (Codex on #96)
	do
		local dx, dy = s.markerX - s.playerX, s.markerY - s.playerY
		local d = sqrt(dx * dx + dy * dy)
		local r = throw.tune.markerRadius or 0.25
		if d > r then
			camera.fitNear(fp, s.markerX - dx * r / d, s.markerY - dy * r / d)
		else
			camera.fitNear(fp, s.playerX, s.playerY)
		end
	end
	if mix <= 0 then
		s.shF = nil
		return
	end
	local sh = s.shCam
	shoulderFit(s, sh)
	k = k or 1
	if s.shF and k < 1 then
		-- ease toward this frame's fit (the lens in log space), and take it
		-- once within half a pixel: an easing that never arrives would move
		-- the camera, and redraw the world, every frame B is held
		local f, cx, cy = sh.f, sh.cx, sh.cy
		if abs(f - s.shF) > 0.5 or abs(cx - s.shCx) > 0.5 or abs(cy - s.shCy) > 0.5 then
			sh.f = s.shF * (f / s.shF) ^ k
			sh.cx = s.shCx + (cx - s.shCx) * k
			sh.cy = s.shCy + (cy - s.shCy) * k
		end
	end
	s.shF, s.shCx, s.shCy = sh.f, sh.cx, sh.cy
	camera.blend(s.aimCam, fp, sh, camera.smooth(mix))
end

-- How far forward this throw may stand: the advantage line for a baton (a
-- king shot's forwardY is the baseline already), the baseline for a kubb
-- (II.C.1); in a Kid match the Kid line for both (the setup's forwardY: kubbs
-- and batons at kubbs from 2 m in front of the baseline, the king from it).
local function forwardLimit(s)
	if s.projectile == "kubb" and not s.kid then return s.lineY end
	return s.forwardY
end

-- The default release (engine 0.10): a drill's, or a baton's for the distance from
-- the stance to the circle (plan.arcFor; the session's throw.defaultArc), read again
-- on every solve until B sets the arc, so it follows the circle and the stance.
function throw.defaultArc(s)
	if s.projectile == "kubb" then return plan.arcFor("drill") end
	local dx, dy = s.markerX - s.playerX, s.markerY - s.playerY
	return plan.arcFor("baton", sqrt(dx * dx + dy * dy))
end

-- Solve the plan for the aim as it stands: the stance straight behind the
-- target until A has walked it (plan.stance), the arc for the distance until
-- B has moved it (throw.defaultArc), on the meter or the level (throw.planBy);
-- the swivel and loft follow the solution (the swivel is never set by hand).
-- The bars (sol.powerLo..Hi, releaseLo..Hi) go by the distance on the meter, so
-- every solve may move them; the clock reads them from the plan each frame. No
-- tables.
local function replan(s)
	local kubb = s.projectile == "kubb"
	if not s.stanceSet then
		local o = plan.stance(s.markerX, s.markerY, s.lineY, forwardLimit(s), throw.tune.halfWidth, s.stanceOut)
		s.playerX, s.playerY = o.x, o.y
	end
	if not s.arcSet then s.release = throw.defaultArc(s) end
	local q = s.planQ
	q.projectile = kubb and "kubb" or "baton"
	q.px, q.py, q.tx, q.ty = s.playerX, s.playerY, s.markerX, s.markerY
	q.meter, q.level = throw.planBy(s)
	q.release, q.surface, q.spin = s.release, s.surface, kubb and s.spin or 0
	-- a baton's circle on a piece (a standing target within snapRadius of its
	-- centre: the piece is in the circle) aims the baton's centre through it at
	-- the piece's aim height (plan.aimZFor; Tyler's report, 2026-11-16), and
	-- the arc ends on that piece's near face (s.aimFace, m along the throw from
	-- the stance); an empty spot is aimed at the ground
	local on = nil
	if not kubb then on = plan.snap(s.markerX, s.markerY, s.snaps, #s.snaps, throw.tune.snapRadius) end
	if on then
		local king = on.king or on.kind == "king"
		q.aimZ = plan.aimZFor(king and "king" or "kubb")
		local dx, dy = s.markerX - s.playerX, s.markerY - s.playerY
		local d = sqrt(dx * dx + dy * dy)
		local along = d > 0 and ((on.x - s.playerX) * dx + (on.y - s.playerY) * dy) / d or 0
		s.aimFace = along - (king and tw.body.kinds.king.hx or tw.body.kinds.kubb.hx)
	else
		q.aimZ, s.aimFace = 0, nil
	end
	local sol = plan.solve(q, s.sol)
	s.swivel, s.loftDeg = sol.swivel, sol.loft
	s.planLevel, s.planDirty, s.planSkipped, s.planStale = q.meter or q.level, false, false, false
	throw.solves = (throw.solves or 0) + 1   -- (self-tests count the scene's solves)
end
throw.replan = replan

-- A release B has set under the knee (a drive), which the floor can raise
-- (aimInput's guard: such a plan is never solved per frame while the circle or the
-- stance moves).
function throw.keptDrive(s)
	return s.arcSet and s.projectile ~= "kubb" and s.release < plan.tune.driveKneeDeg
end

-- The lowest release this throw can be planned at (engine 0.16, plan.arcFloor: the
-- drive's floor for the stance, the circle and the aim height; a kubb's the knee).
-- For a stance and circle the engine has not seen it still costs about 0.5 ms in
-- desktop Lua from 1.5 m out on engine 0.18 as on 0.16, roughly 150 ms on the device
-- (0.18 keeps the last floor, so a repeat is a default plan's cost, but its search
-- carries a line at the hand's geometric limit first: docs/notes/throw.md "The floor
-- on 0.18"). It is worked out only when B +
-- down steps ARC, and kept with what it was worked out for (the stance, the circle,
-- the aim height, the projectile, the meter) until one of them changes: never per
-- frame, and with B held the circle and the stance cannot move, so a held slide down
-- works it out once. docs/notes/throw.md "The drive".
local function floorKnown(s)
	local q, k = s.planQ, s.floorKey
	return k.ok and k.px == q.px and k.py == q.py and k.tx == q.tx and k.ty == q.ty and k.aimZ == q.aimZ
		and k.projectile == q.projectile and k.meter == (q.meter or q.level)
end
function throw.arcFloor(s)
	if s.planDirty then replan(s) end
	local q, k = s.planQ, s.floorKey
	if not floorKnown(s) then
		k.px, k.py, k.tx, k.ty, k.aimZ, k.projectile, k.meter = q.px, q.py, q.tx, q.ty, q.aimZ, q.projectile,
			q.meter or q.level
		k.floor, k.ok = plan.arcFloor(q), true
		throw.floorSolves = (throw.floorSolves or 0) + 1   -- (self-tests and the perf check count them)
	end
	return k.floor
end
-- The floor if it is already known for the plan as it stands, else nil (no solve).
function throw.knownFloor(s)
	if s.projectile == "kubb" then return plan.tune.driveKneeDeg end
	if not s.planDirty and floorKnown(s) then return s.floorKey.floor end
	return nil
end

-- B + up/down (engine 0.16, kubb-engine docs/CLIENTS.md "0.16 on top"): the release a
-- tick at a time from the release as it is planned (s.sol.release: the default, or the
-- kept release raised to the floor), never under the throw's floor, so a press at the
-- floor and back moves the throw at once (the session's stepArc). Up never needs the
-- floor (the planned release is on or over it already); down works it out.
function throw.stepArc(s, ticks)
	if s.planDirty then replan(s) end
	local from = s.sol.release or s.release
	local f = (ticks < 0) and throw.arcFloor(s) or nil
	if f and from < f then from = f end
	local r = plan.clampRelease(from + ticks * plan.tune.arcTickDeg, s.projectile)
	if f and r < f then r = f end
	s.release = r
	s.arcSet, s.planDirty = true, true
end

-- What ARC does, on the control while B is held (engine 0.16; the game's woodcut
-- voice, one line in the hint over the prompt): from the knee up a lower arc is a
-- flatter, harder throw; under it the drive; at the throw's floor, that it goes no
-- lower from here. A drilled kubb has no drive (its floor is the knee). Constant
-- strings: nothing is made per frame.
throw.ARC_WORDS = {
	lower = "DOWN: LOWER AND HARDER",
	drive = "DRIVE: LOW, HARD, NO FLIP",
	floor = "NO LOWER FROM HERE",
	kubb = "DOWN: LOWER, IT RUNS ON",
	kubbFloor = "A KUBB GOES NO LOWER",
}
function throw.arcWords(s, drive)
	local W = throw.ARC_WORDS
	local rel = s.sol.release or s.release
	-- on the floor: a known floor reached, or a kept release the plan raised to it
	local f = throw.knownFloor(s)
	local atFloor = (f and rel <= f + 0.01) or (s.arcSet and rel > s.release + 0.01)
	if s.projectile == "kubb" then return atFloor and W.kubbFloor or W.kubb end
	if atFloor then return W.floor end
	return drive and W.drive or W.lower
end

-- The plan as it stands is a drive: a baton planned under the knee (half past 5,
-- plan.tune.driveKneeDeg), thrown flat or down and hard, with no end over end turn.
function throw.isDrive(s)
	return s.projectile ~= "kubb" and (s.sol.release or s.release) < plan.tune.driveKneeDeg
end

-- The circle has been let go at (markerX, markerY): the arc's kind is the
-- nearest target's, and (snap) it snaps onto a standing target within
-- snapRadius (plan.snap over s.snaps). Nothing in play snaps any more (Tyler's
-- play test, 2026-11-15: a circle that locks onto the kubb made 8 m too easy
-- and left no way to aim off it for the wind); a new throw's circle still
-- starts on a target (retarget).
local function settleMarker(s, snap)
	local sn, n = s.snaps, #s.snaps
	local best, bd = nil, math.huge
	for i = 1, n do
		local dx, dy = sn[i].x - s.markerX, sn[i].y - s.markerY
		local d = dx * dx + dy * dy
		if d < bd then best, bd = sn[i], d end
	end
	if best then s.markerKind = kindOf(best) end
	s.markerOn = nil
	if snap then
		local it = plan.snap(s.markerX, s.markerY, sn, n, throw.tune.snapRadius)
		if it then s.markerX, s.markerY, s.markerOn = it.x, it.y, it end
	end
	s.planDirty = true
end

-- A new throw's circle: (keep) one the player put with the d-pad stays where
-- it is while a live target stands within keepNear of it (s.markerSet: aimed
-- off a kubb for the wind, it stays aimed; its arc's kind is read again, so
-- the default arc follows the targets: Codex on #98), else it stays on the
-- target it is on while that still stands; otherwise it goes onto the live
-- target nearest the thrower (s.targets; with none it stays where it is).
local function retarget(s, keep)
	if keep and s.markerSet then
		local sn, r = s.snaps, throw.tune.keepNear
		for i = 1, #sn do
			local dx, dy = sn[i].x - s.markerX, sn[i].y - s.markerY
			if dx * dx + dy * dy <= r * r then
				settleMarker(s, false)
				return
			end
		end
	end
	s.markerSet = false
	local on = s.markerOn
	if keep and on and not on.toppled then
		for i = 1, #s.snaps do
			if s.snaps[i] == on then
				s.markerX, s.markerY, s.markerKind = on.x, on.y, kindOf(on)
				s.planDirty = true
				return
			end
		end
	end
	local tg = s.targets
	local best, bd = nil, math.huge
	for i = 1, #tg do
		local dx, dy = tg[i].x - s.playerX, tg[i].y - s.playerY
		local d = dx * dx + dy * dy
		if d < bd then best, bd = tg[i], d end
	end
	if best then s.markerX, s.markerY, s.markerOn, s.markerKind = best.x, best.y, best, kindOf(best) end
	s.planDirty = true
end

-- The plan starts afresh: the arc follows the target, no tilt or spin.
local function freshPlan(s)
	s.arcSet, s.tilt, s.spin = false, 0, 0
	s.planDirty = true
end

-- The last throw's dots on the clock and its verdicts go (a new wind-up, a
-- new team's turn).
local function clearLast(s)
	s.lastBack, s.lastStop, s.showVerdicts, s.restText = nil, nil, false, nil
end

function throw.new(provider)
	local s = {
		input = provider,
		mode = "aim",            -- "aim" | "cpuswing" (the Playdate's arm on the clock) | "flight" | "rest" | "done"
		playerX = 0,
		playerY = throw.tune.lineY, -- at the throwing line, or up to backMax behind it
		swivel = 0,              -- radians, + = right: the plan's (s.sol.swivel)
		loftDeg = flight.tune.loftDefaultDeg, -- the plan's loft (s.sol.loft)
		arm = nil,               -- where the crank is: forward degrees from the bottom of the turn
		armed = false,           -- the crank crossed the bottom going back; the wind-up may start
		swing = swing.new(),
		flight = flight.new(),   -- the stage 1 prediction (landing point, flight time) and
		                         -- the baton's displayed position (x, y, z, t)
		aimCam = camera.new(),   -- the aim camera shown: first person, the plan view or between
		fpCam = camera.new(),    -- first person, while the plan view is mixed in
		shCam = camera.new(),    -- the plan view over the shoulder (camera.shoulder)
		camMix = 0,              -- 0 first person .. 1 the plan view (B held), eased
		shF = nil, shCx = nil, shCy = nil, -- the plan view's lens and principal point last frame
		planHeld = false,        -- B was held this frame (aimInput)
		impactCam = camera.new(),
		view = camera.new(),
		restTime = 0,
		last = nil,              -- the last throw: what the swing measured, the launch, distance, ...
		readout = nil,           -- its readout text
		showReadout = false,     -- System Menu "Pitch: readout"
		flagText = nil,          -- the result flag after a release (12 characters at most)
		-- the rail (hud.rail): practice until throw.setRail says otherwise
		railName = "PRACTICE", railKind = nil, railN = 0, railOf = 0, railR1 = nil, railR2 = nil,
		railDm = nil, railDist = nil,
		throws = 0,
		surface = throw.tune.surface,
		layout = throw.defaultLayout(),
		items = {}, nitems = 0,  -- render/world items, one per layout piece
		targets = {},            -- live targets (camera framing, the circle's start)
		snaps = {},              -- what the circle snaps onto
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
		ft = frametel.new(),     -- this throw's frame times (device/frametel), reset per throw
		ftInfo = {},             -- the rest of its log line, filled once at rest
		drill = false,           -- the throw is a drilled kubb
		thisDrill = false,       -- the throw in the air (or at rest) was drilled
		-- the aim: the target circle (view frame), what it is on, and the plan
		markerX = 0, markerY = 0, markerHeld = 0, markerSide = nil, markerFixed = false,
		markerOn = nil,          -- the target item the circle is on, or nil
		markerSet = false,       -- the player moved the circle with the d-pad (kept across throws)
		markerKind = "base",     -- the kind of target nearest the circle (the arc's default)
		markerMoving = false,    -- the d-pad moved the circle last frame
		stanceSet = false,       -- A has walked the stance this aim
		release = plan.arcFor("baton"), arcSet = false, -- the planned release (clock degrees)
		tilt = 0, spin = 0,      -- B + left/right: a baton's tilt (degrees), a kubb's spin (taps)
		sol = {}, planQ = {}, stanceOut = {}, planDirty = true,
		floorKey = {},           -- throw.arcFloor's kept floor and what it was worked out for
		planLevel = nil,         -- what s.sol was solved on: the meter or the level (throw.planBy)
		planSkipped = false,     -- the moving circle's last frame went without a solve (aimInput)
		launchOut = {}, launchOpts = {}, -- plan.launch's (reused)
		dial = {},               -- hud.clock's state (reused)
		traceOut = {},           -- the trace line's result (reused)
		lastBack = nil, lastStop = nil, -- the last throw's peak and stop: dots on the clock
		showVerdicts = false,    -- the last throw's verdicts show (until the next wind-up)
		vPower = 0, vRelease = 0, vSteady = true, vSide = 0,
		restText = nil,          -- a drilled kubb's rest distance from the circle ("18 CM AWAY")
		drillSeq = 0,            -- practice: drilled kubbs thrown (their ids)
		howto = nil,             -- HOW TO THROW running over the pitch (core/howto), or nil
		howtoObs = {},           -- what it sees each frame (reused)
		howtoThrows = 0,         -- s.throws it has seen come back to aiming
		howtoB = nil, howtoPad = false, -- B's time down, and whether the d-pad moved meanwhile
		nudge = crank.nudgeNew(), -- forward turns with no throw (device/crank)
		-- the nudge's words, naming the scene's System Menu item (throw.setMenuName)
		nudgeText = "CRANK BACKWARD? MENU: CRANK FLIPS IT",
		flipNote = 0,            -- s CRANK FLIPPED still shows (throw.flipCrank)
	}
	throw.standUp(s)
	updateTargets(s)
	retarget(s, false)
	replan(s)
	aimCamera(s)
	return s
end

local function markerHome(s)
	s.markerX, s.markerY, s.markerOn = 0, s.lineY + drill.tune.markerStartY, nil
	s.planDirty = true
end

-- The match: set the next throw up. `setup` is a core/match setup (view
-- frame): its pieces and debris, projectile, lines and targets. The circle
-- starts on the live target nearest the thrower and the thrower stands
-- behind it (a drill's circle: where the team left it).
function throw.prepare(s, setup)
	burst.reset(s.burst)
	-- the match's surface (core/match setup.surface: grass, sand, snow)
	if setup.surface then s.surface = setup.surface end
	render.setSurface(s.surface)
	throw.setPieces(s, setup.pieces, setup.debris)
	s.lineY, s.forwardY, s.advY = setup.lineY, setup.forwardY or setup.lineY, setup.advY
	s.kid, s.kidY = setup.kid, setup.kidY
	s.projectile, s.projectileId = setup.projectile, setup.kubb or setup.batonId
	s.targetIds = setup.targets
	s.auto = false
	updateTargets(s)
	-- another team's turn: the last throw's dots and verdicts are not this team's
	if s.stanceSide ~= setup.side then
		clearLast(s)
		crank.nudgeClear(s.nudge)   -- the nudge counts one team's turns at a time
	end
	-- Stay put (Jamie, 2026-11-14: "in a real Kubb game you stand in one spot
	-- and throw until you want to move"): a team's batons after its first of
	-- a turn keep the stance the player walked to with A, held to where this
	-- one may stand (a king shot is from the baseline), and the circle stays
	-- on its target while that stands. Otherwise (a turn's first baton, every
	-- kubb) the stance follows the target.
	local keep = setup.projectile == "baton" and (setup.n or 1) > 1
		and s.stanceSide == setup.side and s.stanceKind == "baton"
	local t = throw.tune
	if keep and s.stanceSet then
		s.playerX = max(-t.halfWidth, min(t.halfWidth, s.playerX))
		s.playerY = max(s.lineY - t.backMax, min(s.forwardY, s.playerY))
	else
		s.stanceSet = false
		s.playerX, s.playerY = 0, (setup.projectile == "baton" or s.kid) and s.forwardY or setup.lineY
	end
	-- a drill's own stance (AROUND THE PITCH: in front of the next base kubb)
	if setup.playerX then s.playerX, s.playerY, s.stanceSet = setup.playerX, setup.lineY, true end
	s.stanceSide, s.stanceKind = setup.side, setup.projectile
	-- A kubb's spin is kept for the side's next kubb in the same inkast turn
	-- (setup.turn, the match's; as the engine's session does since 0.9); it
	-- goes when the turn ends, the side changes or a match starts. Arc and
	-- tilt start afresh at every throw.
	local spin = s.spin
	local keepSpin = setup.projectile == "kubb" and setup.turn ~= nil
		and s.spinTurn == setup.turn and s.spinSide == setup.side
	freshPlan(s)
	if keepSpin then s.spin = spin end
	s.spinTurn, s.spinSide = setup.turn, setup.side
	-- metres the advantage line is up from the baseline, for the HUD's flag
	-- (batons only; nil from the baseline and for a king shot). In a Kid match the
	-- line thrown from is the Kid line unless the advantage line is nearer the middle,
	-- and kubbs are thrown from it too: KID LINE 2.0 M (the session's aim.advText)
	local adv = s.forwardY - s.lineY
	s.advMeters = ((setup.projectile == "baton" or s.kid) and adv > 0.05) and adv or nil
	local onKid = s.kid and s.kidY and math.abs(s.forwardY - s.kidY) < 0.01
	s.advText = s.advMeters and (onKid and hud.kidLineText(s.advMeters) or hud.advantageText(s.advMeters)) or nil
	-- a kubb is drilled; its circle stays where the team left it last throw
	-- (setup.markerY, a drill's own from the thrower's line: fixed there)
	s.markerFixed = false
	if setup.projectile == "kubb" then
		if setup.markerY then
			s.markerX, s.markerY, s.markerFixed = setup.markerX or 0, setup.lineY + setup.markerY, true
			s.markerOn = nil
		elseif not (s.drill and s.markerSide == setup.side) then
			markerHome(s)
		end
		s.markerSide = setup.side
		s.drill = true
	else
		s.drill = false
		retarget(s, keep)
	end
	s.thisDrill = false
	s.mode = "aim"
	s.pb, s.result, s.readout, s.last, s.flagText = nil, nil, nil, nil, nil
	s.cpuThrow, s.cpuPlan, s.cpuTarget, s.cpuSpeed = nil, nil, false, nil
	s.slowMo = false
	burst.reset(s.burst)
	s.arm, s.armed = nil, false
	swing.reset(s.swing)
	s.camMix, s.planHeld, s.shF = 0, false, nil
	replan(s)
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
	s.markerFixed = false
	s.drill = on and true or false
	s.projectile = on and "kubb" or "baton"
	s.projectileId = nil
	s.stanceSet = false
	freshPlan(s)
	clearLast(s)
	if on then
		markerHome(s)
	else
		s.playerX, s.playerY = 0, s.lineY
		retarget(s, false)
	end
	s.arm, s.armed = nil, false
	swing.reset(s.swing)
	s.readout, s.last, s.flagText = nil, nil, nil
	replan(s)
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
	s.cpuThrow = nil
	burst.reset(s.burst)     -- a burst (or the king's inverted flash) must not outlive the throw
	swing.reset(s.swing)
	s.planDirty = true
end

-- The aim, for self-tests and callers that set it up directly (each solves
-- the plan again at once): the circle onto (x, y) (a baton's snaps onto a
-- standing target within snapRadius: callers aim at a piece; the d-pad's
-- let-go no longer snaps), the stance (as if A had walked it there), the
-- planned release (as if B had set it), the tilt or spin.
function throw.aimAt(s, x, y)
	local mx, my = drill.clampMarker(x, y - s.lineY)
	s.markerX, s.markerY = mx, s.lineY + my
	settleMarker(s, s.projectile ~= "kubb")
	replan(s)
	aimCamera(s)
end
function throw.setStance(s, x, y)
	s.playerX, s.playerY, s.stanceSet = x, y, true
	replan(s)
	aimCamera(s)
end
function throw.setArc(s, releaseDeg)
	-- under the floor the plan is solved at the floor (plan.solve, engine 0.16)
	s.release, s.arcSet = plan.clampRelease(releaseDeg, s.projectile), true
	replan(s)
	aimCamera(s)
end
function throw.setTilt(s, deg) s.tilt = plan.clampTilt(deg) end
function throw.setSpin(s, taps) s.spin, s.planDirty = plan.clampSpin(taps), true end

local swingInput, drawMarker, drawRail, drawArc

-- How many ticks a plan control moves this frame (-1, 0 or 1): one the frame
-- its direction goes down, none until it has been held throw.tune.tickHold s,
-- then one a frame while it is held. s[key] is the time held (nil: let go).
local function planTicks(s, key, dir, dt)
	if dir == 0 then
		s[key] = nil
		return 0
	end
	local h = s[key]
	if h == nil or h.dir ~= dir then
		s[key] = { dir = dir, t = 0 }
		return dir
	end
	h.t = h.t + dt
	return h.t >= throw.tune.tickHold and dir or 0
end

local function aimInput(s, dt)
	local t = throw.tune
	local p = s.input
	local delta = p:crank()
	local arm = swing.armAngle(p:crankPos())
	local prevArm = s.arm
	s.arm = arm
	local dx = (p:held("right") and 1 or 0) - (p:held("left") and 1 or 0)
	local dy = (p:held("up") and 1 or 0) - (p:held("down") and 1 or 0)
	local holdA, holdB = p:held("a"), p:held("b")
	s.planHeld = holdB
	if not holdB then s.arcHeld, s.sideHeld = nil, nil end
	local sw = s.swing
	local moving, walking = false, false
	if holdB then
		-- the plan: up/down move the release, left/right tilt a baton's spin
		-- plane or spin a kubb, any value in range (core 0.9): a tap moves one
		-- tick (plan.tune arcTickDeg, tiltTickDeg, spinTick), held past
		-- throw.tune.tickHold it slides a tick a frame
		local pt = plan.tune
		local v = planTicks(s, "arcHeld", (p:held("up") and 1 or 0) - (p:held("down") and 1 or 0), dt)
		-- from engine 0.16 down to the throw's floor (the drive): stepped from the
		-- release as planned (throw.stepArc)
		if v ~= 0 then throw.stepArc(s, v) end
		local side = planTicks(s, "sideHeld", dx, dt)
		if side ~= 0 then
			if s.projectile == "kubb" then
				s.spin = plan.clampSpin(s.spin + side * pt.spinTick)
				s.planDirty = true   -- the plan chip and trace carry the spin
			else
				s.tilt = plan.clampTilt(s.tilt + side * pt.tiltTickDeg)
			end
		end
	elseif holdA then
		-- walk: left/right along the line, down steps back from it, up comes
		-- forward again as far as this throw may stand (in a match, as far as
		-- the advantage line when the engine allows it: s.forwardY)
		if dx ~= 0 then
			s.playerX = max(-t.halfWidth, min(t.halfWidth, s.playerX + dx * t.walkSpeed * dt))
		end
		if dy ~= 0 then
			s.playerY = max(s.lineY - t.backMax, min(forwardLimit(s), s.playerY + dy * t.walkSpeed * dt))
		end
		if dx ~= 0 or dy ~= 0 then s.stanceSet, s.planDirty, walking = true, true, true end
	elseif (dx ~= 0 or dy ~= 0) and not s.markerFixed then
		-- the d-pad alone: the target circle, across and along, faster the
		-- longer it is held (not a drill's fixed marker)
		local dtn = drill.tune
		s.markerHeld = s.markerHeld + dt
		local v = min(dtn.markerSpeedMax, dtn.markerSpeed + dtn.markerAccel * s.markerHeld)
		local mx, my = drill.clampMarker(s.markerX + dx * v * dt, s.markerY - s.lineY + dy * v * dt)
		s.markerX, s.markerY, s.markerOn, s.markerSet = mx, s.lineY + my, nil, true
		s.planDirty = true
		moving = true
	end
	if not moving then
		s.markerHeld = 0
		-- let go: the arc follows the nearest target's kind (no snap)
		if s.markerMoving then settleMarker(s, false) end
	end
	s.markerMoving = moving
	local by = planKey(s)
	if s.planDirty or s.planLevel ~= by then
		-- a short throw's plan costs most of a frame on the device (plan.solve at
		-- 1 m, about 23 ms): while only the moving circle changed it, solve every
		-- other frame; the circle let go, or anything else, solves it now
		local skip = false
		if moving and not s.planSkipped and s.planLevel == by then
			local ddx, ddy, r = s.markerX - s.playerX, s.markerY - s.playerY, t.halfRateM
			skip = ddx * ddx + ddy * ddy < r * r
		end
		-- A drive kept by B (throw.keptDrive) may sit under the floor of the throw as it
		-- now is, and plan.solve then works out the new floor: about 0.5 ms in desktop Lua
		-- on engine 0.18 (0.08 to 0.12 on 0.16 from 2 to 4 m), roughly 150 ms on the
		-- device. So while the circle or the stance moves (the d-pad,
		-- A + d-pad: the only inputs that change the plan frame after frame) it is not
		-- solved at all; the frame the movement stops solves it once. Meanwhile the
		-- clock keeps the last good plan's targets and the arc is drawn greyed
		-- (s.planStale). Every other change (a snap, a retarget, a new throw, a switch
		-- of projectile, a reset, a launch) solves once when it happens. Engine 0.18's
		-- floor is cheap only for a geometry it has just seen, never for a moving one,
		-- so this guard and s.planStale stay until a solve raised to a new floor costs
		-- what a default plan does. docs/notes/throw.md "The drive".
		if (moving or walking) and s.planLevel == by and throw.keptDrive(s) then
			skip = true
			s.planStale = true
		end
		if skip then s.planSkipped = true else replan(s) end
	end
	-- while A or B is held the crank does not throw
	if holdA or holdB then
		if sw.phase ~= "idle" then swing.reset(sw) end
		s.armed = false
		return nil
	end
	return swingInput(s, sw, delta, arm, prevArm, dt)
end

-- The crank throws: arming at the bottom of the turn, the wind-up and the
-- flick (core/swing), with the trace recorder fed alongside (not in the
-- cooldown after a release: the crank swinging back is not part of the swing).
swingInput = function(s, sw, delta, arm, prevArm, dt)
	-- the nudge counts the idle crank's forward turns (device/crank)
	if sw.phase == "idle" and not s.watching then crank.nudgeArm(s.nudge, arm, throw.tune) end
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
	local ph = sw.phase
	if ph == "idle" and sw.pending == 0 then rec.clear() end
	if ph == "winding" or ph == "swinging" or (ph == "idle" and delta ~= 0) then rec.add(dt, delta) end
	local ev = swing.update(sw, delta, dt)
	if ev then s.armed = false end
	-- a new wind-up: the last throw's dots and verdicts go, and the nudge hides
	if sw.phase == "winding" then
		if s.lastBack or s.showVerdicts then clearLast(s) end
		crank.nudgeWound(s.nudge, throw.tune)
	end
	if ev == "release" then crank.nudgeClear(s.nudge) end
	if ev == "letdown" then
		rec.write("letdown", nil)
	end
	return ev
end

-- A knock for every piece struck (wood on wood: kubbs, the king, lying
-- batons, stakes), as the picture reaches the moment (sound.lua; Jamie,
-- 2026-11-14): those first touched since the last frame's
-- shown time, nothing until the thrown piece's first hit is on screen
-- (before it nothing else is awake to touch), and none more than knockLate
-- behind the picture (a jump to the end of the calm tail plays no pile of
-- old knocks). No tables.
local knockBuf = {}
local function knocks(s)
	local pb = s.pb
	if not pb then return end
	local t1, fh = s.showTime, pb.w.firstHit
	local t0 = s.knockT or -1
	if not fh or t1 < fh.t or t1 <= t0 then return end
	local n = burstpick.touches(pb.w, t0, t1, knockBuf)
	local late = throw.tune.knockLate
	for i = 1, n do
		if t1 - knockBuf[i].touchT <= late then sound.knock() end
	end
	s.knockT = t1
end

-- Launch a throw: L is a launch (plan.launch's fields: speed, loft, swivel,
-- tilt, tumble, legal; a drill's noseDown, rollLand, spin, wobble, scatter)
-- from where the player stands; how is "baton", "drill" or "lob" (the
-- Playdate's kubb tosses, end over end). sol (optional) is the plan the
-- throw was made on: a baton leaves its hand (plan.solve's handZ, handFwd,
-- handTip; flight.handAt of the planned distance): under flight.tune.nearM
-- lower, ahead of the feet and tipped toward the target, the short throw's
-- firm bowl (engine 0.8, docs/notes/throw.md "The short throw"); without a
-- plan, or from nearM out, from the feet at handHeight as always.
local function fire(s, L, how, sol)
	s.knockT = -1
	-- the follow camera starts from the aim camera as it is (normally first
	-- person); the next aim starts in first person
	s.camMix, s.planHeld, s.shF = 0, false, nil
	local t = throw.tune
	local fl = s.flight
	local kubb = how ~= "baton"
	local drilling = how == "drill"
	if drilling and not s.projectileId then
		-- practice: each drilled kubb is a piece of its own
		s.drillSeq = s.drillSeq + 1
		s.drillId = "d" .. s.drillSeq
	end
	s.thisDrill = drilling
	local id = s.projectileId or (drilling and s.drillId) or nil
	local tumble = drilling and 0 or (L.tumble or 0)
	local tilt = kubb and 0 or (L.tilt or 0)
	local handZ, handFwd, handTip = nil, nil, nil
	if not kubb and sol and sol.handZ then handZ, handFwd, handTip = sol.handZ, sol.handFwd, sol.handTip end
	-- the stage 1 prediction: landing point and flight time for the cameras
	flight.launch(fl, s.playerX, s.playerY, L.swivel, L.loft, L.speed, tumble, tilt, handZ, handFwd, handTip)
	-- Pick up the next of the six practice batons before building the world.
	-- A match supplies its own projectile ID and turn debris.
	if not kubb and s.auto then
		s.practiceBaton = s.practiceBaton % 6 + 1
		id = s.practiceBaton == 1 and "baton" or ("baton" .. s.practiceBaton)
		for i = 1, s.nitems do
			if s.items[i].id == id then
				table.remove(s.items, i)
				s.nitems = s.nitems - 1
				break
			end
		end
	end
	-- the physics world: every piece where it lies now, then the thrown one
	local pieces = {}
	for i = 1, s.nitems do
		local it = s.items[i]
		pieces[i] = { id = it.id, kind = it.kind, x = it.x, y = it.y, z = it.z,
			qw = it.qw, qx = it.qx, qy = it.qy, qz = it.qz, toppled = it.toppled }
	end
	render.setSurface(s.surface)
	local w = phys.new { surface = s.surface, pieces = pieces, windX = s.windX, windY = s.windY }
	for i = 1, s.nitems do s.bodyIndex[i] = w.byId[s.items[i].id].index end
	local b
	if kubb then
		if drilling then
			-- the hand's steadiness last (engine 0.11: plan.launch's scatter, the
			-- meter's for a person, the level's drillScatter for the Playdate)
			b = phys.launchDrill(w, id, s.playerX, s.playerY, L.swivel, L.loft, L.speed, L.noseDown, L.rollLand,
				L.spin, L.wobble, L.scatter)
		else
			b = phys.launchKubb(w, id, s.playerX, s.playerY, L.swivel, L.loft, L.speed, tumble)
		end
		-- the thrown kubb is drawn as one more item after the pitch's
		local it = s.projItem
		if not it or it.id ~= id then
			it = render.item(id, "kubb")
			s.projItem = it
		end
		s.items[s.nitems + 1] = it
	else
		b = phys.launchBaton(w, s.playerX, s.playerY, L.swivel, L.loft, L.speed, tumble, tilt, id, handZ, handFwd, handTip)
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
	s.swingFrom, s.swinging, s.swingStop = nil, false, nil
	camera.impact(s.impactCam, fl.lx, fl.ly, fl.dx, fl.dy, s.side)
	s.last = s.last or {}
	local l = s.last
	l.legal = L.legal ~= false
	l.tilt, l.launchSpeed, l.tumbleRate, l.launchLoft, l.launchSwivel = tilt, L.speed, tumble, L.loft, L.swivel
	l.back, l.planBack, l.stop, l.plan, l.flick, l.shake = nil, nil, nil, nil, nil, nil
	l.powerV, l.releaseV, l.steady, l.loft, l.swivelOff = nil, nil, nil, nil, nil
	l.sideDeg, l.lenShare, l.sideV, l.lenV = nil, nil, nil, nil
	l.distance, l.down, l.hit, l.restCm = nil, nil, nil, nil
	l.drill = drilling
	if drilling then
		l.markerX, l.markerY = s.markerX, s.markerY
		l.restX, l.restY = nil, nil
	end
	s.readout, s.restText = nil, nil
	-- the result flag: a helicopter shows from the release, the rest at rest (in a
	-- Kid match a helicopter counts: it says so, nobody is told off)
	s.flagText = (not l.legal) and (s.kid and "HELICOPTER: IT COUNTS" or "HELICOPTER") or nil
	s.mode = "flight"
	s.throws = s.throws + 1
end

-- The player's throw: the swing's result `r` (core/swing) against the plan
-- (plan.launch), and its verdicts and dots for the HUD.
local function launch(s, r)
	local kubb = s.projectile == "kubb"
	local o = s.launchOpts
	-- a person's throw: no level, so plan.launch reads the meter's from the plan
	local _, lv = throw.planBy(s)
	o.projectile, o.tilt, o.spin, o.level = kubb and "kubb" or "baton", s.tilt, s.spin, lv
	o.nerves = nervesFor(s) or nil
	if s.planDirty or s.planLevel ~= planKey(s) then replan(s) end
	local sol = s.sol
	local L = plan.launch(sol, r, o, s.launchOut)
	fire(s, L, kubb and "drill" or "baton", sol)
	s.lastBack, s.lastStop = r.back, r.releaseAngle
	s.vPower, s.vRelease, s.vSteady, s.vSide = L.powerV, L.releaseV, L.steady, L.sideV
	local l = s.last
	l.back, l.planBack, l.stop, l.plan = r.back, sol.back, r.releaseAngle, sol.release
	l.flick, l.shake = r.flickDps, r.shake
	l.powerV, l.releaseV, l.steady = L.powerV, L.releaseV, L.steady
	l.loft, l.swivelOff = sol.loft, math.deg(L.swivel - sol.swivel)
	l.sideDeg, l.lenShare, l.sideV, l.lenV = L.sideDeg, L.lenShare, L.sideV, L.lenV
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

-- The trace line's plan and launch (core/trace's header): written once, at
-- rest, for the player's own throws.
local function writeTrace(s, l)
	local T = s.traceOut
	for k in pairs(T) do T[k] = nil end
	for k, v in pairs(s.swing.result) do T[k] = v end   -- what the swing measured
	local y0, sol = s.lineY, s.sol
	local lv = throw.levelFor(s)
	T.level = type(lv) == "string" and lv or nil
	T.projectile = l.drill and "kubb" or "baton"
	T.drillId = s.drillRun
	T.tx, T.ty, T.px, T.py = s.markerX, s.markerY - y0, s.playerX, s.playerY - y0
	T.plan, T.loft = sol.release, sol.loft
	T.powerLo, T.powerHi, T.releaseLo, T.releaseHi = sol.powerLo, sol.powerHi, sol.releaseLo, sol.releaseHi
	if l.drill then T.spin = s.spin else T.planTilt = s.tilt end
	T.launchSpeed, T.launchLoft, T.swivelOff = l.launchSpeed, l.launchLoft, l.swivelOff
	T.tumbleRate, T.tilt, T.legal = l.tumbleRate, l.tilt, l.legal
	T.powerV, T.releaseV, T.steady = l.powerV, l.releaseV, l.steady
	T.sideDeg, T.lenShare, T.sideV, T.lenV = l.sideDeg, l.lenShare, l.sideV, l.lenV
	T.distance = l.distance
	if l.drill then
		-- lengths from the thrower's baseline, as the target's
		T.mode = "drill"
		T.markerX, T.markerY = l.markerX, l.markerY - y0
		T.landX, T.landY = l.landX, l.landY - y0
		T.restX, T.restY = l.restX, l.restY - y0
		T.throwerX = s.playerX
	end
	tw.recorder.write("release", T)
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
	if l.drill and l.restX then
		local cm = floor(100 * sqrt((l.restX - l.markerX) ^ 2 + (l.restY - l.markerY) ^ 2) + 0.5)
		l.restCm = cm
		-- the drill's rest distance, in the plan chip's place (hud.cutFlag)
		s.restText = (cm < 100) and string.format("%d CM AWAY", cm) or string.format("%.1f M AWAY", cm / 100)
	end
	s.readout = hud.readoutText(l)
	-- the result flag (a match puts its own ruling there: throw.setFlag)
	if not l.legal then s.flagText = s.kid and "HELICOPTER: IT COUNTS" or "HELICOPTER"
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
	-- the player's throws: the verdicts show until the next wind-up, and
	-- the trace line is written
	s.showVerdicts = not s.scripted
	if not s.scripted then writeTrace(s, l) end
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
		local period = t.framePeriod
		if s.swinging then period = t.swingPeriod end
		budget = (tail and t.tailPeriod or period) - (s.clock() - s.frameStart) - s.drawEst - s.postEst
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
	-- the half circle goes round the piece its burst is for (the first hit may
	-- have been a stake, or a kubb that stayed up)
	if s.swingFrom and s.burst.x1 then tx, ty = s.burst.x1, s.burst.y1 end
	local dx, dy = tx - s.focusX, ty - s.focusY
	local d, step = sqrt(dx * dx + dy * dy), t.focusSpeed * dt
	if d > step then dx, dy = dx * step / d, dy * step / d end
	-- (held still in the calm tail, so the held picture is one cached image)
	if not tail then s.focusX, s.focusY = s.focusX + dx, s.focusY + dy end
	-- the half circle: from the impact of the piece the burst is for, by
	-- shown time (so it holds when the picture holds)
	local B = s.burst
	if not s.swingFrom and t.swingDeg ~= 0 and B.kind and not B.takenBack then
		s.swingFrom = B.first and burstpick.hitTime(B.first) or s.showTime
	end
	local orbit, open = 0, 0
	s.swinging = false
	if s.swingFrom then
		-- a burst taken back (the piece stood after all) stops the turn where it is
		if B.takenBack and not s.swingStop then s.swingStop = s.showTime end
		open = camera.smooth(((s.swingStop or s.showTime) - s.swingFrom) / t.swingTime)
		orbit = rad(t.swingDeg) * open
		s.swinging = open < 1 and not s.swingStop
	end
	camera.impact(s.impactCam, s.focusX, s.focusY, fl.dx, fl.dy, s.side, orbit, open)
	if pb.done and s.showTime >= have then landed(s) end
end

-- The Playdate's arm on the clock before its throw leaves (core/autothrow's
-- a.swing): back to a.swing.back over cpuBackShare of cpuSwingTime, eased
-- out, then forward to a.swing.releaseAngle, speeding up; then the throw.
local autoFire
local function cpuSwing(s, dt)
	local t = throw.tune
	local a = s.cpuThrow
	local back, rel = a.swing.back or 0, a.swing.releaseAngle or 0
	s.cpuT = s.cpuT + dt
	local tb = t.cpuSwingTime * t.cpuBackShare
	local u = s.cpuT
	if u < tb then
		local f = u / tb
		s.cpuArm, s.cpuPhase = -back * f * (2 - f), "winding"
		s.cpuBack = -s.cpuArm
	elseif u < t.cpuSwingTime then
		local f = (u - tb) / (t.cpuSwingTime - tb)
		s.cpuArm, s.cpuPhase, s.cpuBack = -back + (back + rel) * f * f, "swinging", back
	else
		s.cpuThrow = nil
		autoFire(s, a)
		s.lastBack, s.lastStop = back, rel
		showAt(s, 0)
	end
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
		if s.flipNote > 0 then s.flipNote = s.flipNote - dt end
		local ev = aimInput(s, dt)
		-- the plan view while B is held, first person when it is let go: a
		-- smooth move both ways (camera.tune.shoulder.time, eased in aimCamera)
		local st = camera.tune.shoulder
		local want = (s.planHeld and not s.watching) and 1 or 0
		local step = (st.time > 0) and dt / st.time or 1
		if s.camMix < want then s.camMix = min(want, s.camMix + step)
		elseif s.camMix > want then s.camMix = max(want, s.camMix - step) end
		aimCamera(s, (st.refit > 0) and min(1, dt / st.refit) or 1)
		if ev == "release" then
			s.scripted = false
			launch(s, s.swing.result)
			showAt(s, 0)
		end
	elseif s.mode == "cpuswing" then
		cpuSwing(s, dt)
	elseif s.mode == "flight" then
		flightUpdate(s, dt)
		burst.update(s.burst, s, dt)
		knocks(s)
	elseif s.mode == "rest" then
		burst.update(s.burst, s, dt)
		knocks(s)
		s.restTime = s.restTime + dt
		if not s.auto and s.restTime >= (s.instant and t.instantHold or t.restHold) then
			-- the match takes it from here (throw.prepare sets the next throw up)
			s.mode = "done"
		elseif s.restTime >= t.restHold then
			s.mode = "aim"
			-- the crank may have moved during the flight: arming needs a fresh
			-- crossing of the bottom, seen from aim mode
			s.arm, s.armed = nil, false
			burst.reset(s.burst)
			swing.reset(s.swing)
			if s.thisDrill then
				keepDrilled(s)
			elseif baseDown(s) then
				throw.standUp(s)
			elseif s.projectile == "baton" then
				local id = s.pb.w.projectile.id
				local pose = s.result.bodies[id]
				s.nitems = s.nitems + 1
				setItem(s, s.nitems, { id = id, kind = "baton", x = pose.x, y = pose.y, z = pose.z,
					qw = pose.qw, qx = pose.qx, qy = pose.qy, qz = pose.qz, toppled = pose.toppled })
			end
			s.pb = nil
			s.thisDrill = false
			if s.pendingDrill ~= nil then throw.setDrill(s, s.pendingDrill) end
			updateTargets(s)
			-- the circle stays on its target while that stands, else the
			-- nearest one (a drill's stays where it was)
			if not s.drill then retarget(s, true) end
			s.planDirty = true
		end
	end
	if s.howto then throw.howtoFrame(s, p, dt) end
	-- the camera for this frame
	if s.mode == "aim" or s.mode == "cpuswing" then
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

-- HOW TO THROW (core/howto, render/howto) over the practice pitch: every step
-- is done with the real crank, circle, walk and plan, and real throws. It
-- starts on batons (a drilling pitch turns back, as "Pitch: batons" does) with
-- the plan fresh; throw.howtoDone(s) runs when it ends (main.lua: remember it
-- was seen).
function throw.showHowTo(s)
	if s.drill then throw.setDrill(s, false) end
	freshPlan(s)
	s.howto = tw.howto.new()
	s.howtoThrows = s.throws
	s.howtoB, s.howtoPad = nil, false
end

function throw.stopHowTo(s)
	if not s.howto then return end
	s.howto = nil
	if throw.howtoDone then throw.howtoDone(s) end
end

-- One frame of HOW TO THROW: what it sees (s.howtoObs) and its step, only
-- while aiming (a throw in the air is the throw's).
function throw.howtoFrame(s, p, dt)
	-- B's tap: let go quickly with no d-pad while it was down
	local tapB = false
	if p:pressed("b") then s.howtoB, s.howtoPad = 0, false end
	if s.howtoB then
		if p:held("b") then
			s.howtoB = s.howtoB + dt
			if p:held("left") or p:held("right") or p:held("up") or p:held("down") then s.howtoPad = true end
		else
			tapB = s.howtoB <= throw.tune.howtoTap and not s.howtoPad
			s.howtoB = nil
		end
	end
	if s.mode ~= "aim" then return end
	local o = s.howtoObs
	o.arm, o.docked = s.arm, p:docked()
	o.thrown = s.throws > s.howtoThrows
	if o.thrown then
		s.howtoThrows = s.throws
		o.powerV, o.releaseV, o.steady = s.vPower, s.vRelease, s.vSteady
	end
	o.markerX, o.markerY, o.playerX, o.playerY = s.markerX, s.markerY, s.playerX, s.playerY
	o.release, o.tilt, o.spin = s.release, s.tilt, s.spin
	o.pressA, o.tapB = p:pressed("a"), tapB
	if tw.howto.update(s.howto, o) == "close" then throw.stopHowTo(s) end
end

-- The crank flipped (the scene's System Menu item "crank", main.lua):
-- the device's crank direction turns over (device/crank sets
-- swing.tune.forwardSign), throw.crankSaved(flipped) keeps it (main.lua: the
-- datastore "crank", never during a self-test run), and CRANK FLIPPED shows
-- in the prompt flag. A wind-up in progress is dropped, never thrown: the
-- swing goes back to idle unarmed and the arm is read afresh, so the crank
-- must cross the bottom going back (the new back) before anything starts.
-- A throw in the air plays on; it was thrown the old way, and its trace is
-- kept and written when it lands with the sign it was thrown with (the
-- recorder's own): only an unfinished wind-up's samples are dropped.
function throw.flipCrank(s)
	crank.apply(not crank.flipped)
	if throw.crankSaved then throw.crankSaved(crank.flipped) end
	if not s then return end
	swing.reset(s.swing)
	s.arm, s.armed = nil, false
	if s.mode == "aim" then tw.recorder.clear() end
	crank.nudgeClear(s.nudge)
	s.flipNote = throw.tune.flipNoteS
end

-- The scene's System Menu item ("PITCH", "DRILL", "MATCH"), for the nudge's
-- words. Made once, not per frame.
function throw.setMenuName(s, name)
	s.nudgeText = name and ("CRANK BACKWARD? MENU, " .. name .. ": CRANK FLIPS IT") or "CRANK BACKWARD? MENU: CRANK FLIPS IT"
end

-- The practice pitch's surface (System Menu "Pitch"): the next throw is on
-- it, and the ground looks it at once.
function throw.setSurface(s, name)
	s.surface, s.planDirty = name, true   -- a drill runs on by the ground (drill.slideFor)
	render.setSurface(name)
end

-- The Playdate's throws (core/autothrow; self-tests; the autobench): `a` is
-- {x, y, swivel, loftDeg, speed, tumbleRate, tilt, legal}, optionally a.plan
-- (its plan: tx, ty and the clock's targets) and a.swing (its swing: back,
-- releaseAngle). throw.showAim shows its stance and aim before it throws
-- (s.watching hides the player's controls and prompts WATCH); a lobbed kubb
-- (the Playdate's tosses: no a.drill) is aimed like a baton, so no drill
-- circle is shown that the toss will not go to.
function throw.showAim(s, a)
	if s.projectile == "kubb" and not a.drill then s.drill = false end
	s.playerX, s.playerY, s.swivel, s.loftDeg = a.x, a.y, a.swivel, a.loftDeg
	local P = a.plan
	s.cpuPlan, s.cpuSpeed = P, a.speed
	s.cpuTarget = P ~= nil and P.tx ~= nil
	-- the circle on the plan's target; the piece the last circle was on is not
	-- this one (autothrow.choose names it, a.on, for a label the Playdate does not show)
	if s.cpuTarget then s.markerX, s.markerY, s.markerOn = P.tx, P.ty, nil end
	aimCamera(s)
end

-- The clean swing of the autobench's drill (a circle and no launch): exactly
-- on the plan's targets.
local CLEAN = { back = 0, releaseAngle = 0, flickFrac = 1, smoothness = 1, shake = 0, pull = 1, how = "stopped" }

-- Launch the Playdate's throw `a` as it is (its own speed, loft and swivel,
-- mistakes included). A kubb with a.drill's launch fields (core/autothrow:
-- noseDown, rollLand, spin, wobble, scatter) is drilled with them; a.drill
-- with only a circle (the autobench's match case: markerX, markerY) is
-- drilled as the plan's clean drill onto it at the drill arc; a kubb with no
-- a.drill is lobbed end over end.
autoFire = function(s, a)
	local L = s.launchOut
	local d = a.drill
	if s.projectile == "kubb" and d then
		s.markerX, s.markerY, s.markerOn = d.markerX, s.lineY + d.markerY, nil
		if d.noseDown then
			L.speed, L.loft, L.swivel, L.tilt, L.tumble, L.legal = a.speed, a.loftDeg, a.swivel, 0, 0, true
			L.noseDown, L.rollLand, L.spin, L.wobble, L.scatter = d.noseDown, d.rollLand, d.spin, d.wobble, d.scatter
		else
			s.stanceSet, s.arcSet, s.tilt, s.spin = false, false, 0, 0
			s.projectile, s.drill = "kubb", true
			replan(s)
			CLEAN.back, CLEAN.releaseAngle = s.sol.back, s.sol.release
			local o = s.launchOpts
			local _, lv = throw.planBy(s)
			o.projectile, o.tilt, o.spin, o.level = "kubb", 0, 0, lv
			plan.launch(s.sol, CLEAN, o, L)
		end
		s.drill = true
		fire(s, L, "drill")
		return
	end
	L.speed, L.loft, L.swivel, L.tilt, L.tumble, L.legal = a.speed, a.loftDeg, a.swivel, a.tilt or 0, a.tumbleRate,
		a.legal ~= false
	-- the computer's batons leave the hand of their own plan (a.plan): it
	-- never stands nearer than nearM, so that is the feet at handHeight
	fire(s, L, s.projectile == "kubb" and "lob" or "baton", a.plan)
end

-- Throw `a` now (only in aim mode). With a.swing, and not in instant mode,
-- the Playdate's arm plays on the clock first (mode "cpuswing", about
-- cpuSwingTime), then the throw leaves.
function throw.autoLaunch(s, a)
	assert(s.mode == "aim", "autoLaunch while " .. s.mode)
	s.playerX, s.playerY, s.swivel, s.loftDeg = a.x, a.y, a.swivel, a.loftDeg
	s.scripted = true
	clearLast(s)
	if a.swing and not s.instant then
		s.cpuThrow, s.cpuT, s.cpuArm, s.cpuBack, s.cpuPhase = a, 0, 0, 0, "winding"
		s.cpuPlan = s.cpuPlan or a.plan
		s.mode = "cpuswing"
		return
	end
	autoFire(s, a)
	showAt(s, 0)
end

-- The target circle on the ground: a ring with a cross in it (white under
-- black, so it reads on the grass pattern and on a kubb), and for a drill a
-- dotted line to it from the thrower's spot on the baseline. Drawn over the
-- world image each frame (a few calls: the ring is one polygon a pass), so
-- moving it leaves the cached scenery be. No tables.
local ringPts = {}
local unpack = table.unpack

-- The arc's launch: start velocity and time to the ground for the plan's
-- clean throw from the stance onto the target (its loft and speed).
-- A drilled kubb's is drill.solveAt's: the same launch from the hand, down
-- to where it lands (its centre at drill.tune.landZ, its edge short of the
-- circle by what it slides on: sol.land out), in the plan's sol.T. The flight
-- has the air's drag (flight.carry); the arc is drawn as the plain parabola
-- from the hand to the same landing in the same time, within 2 to 4 cm of it.
-- A baton's plan already sends its center through the target (plan.solve: sol.dist
-- out, at sol.aimZ, in sol.flightT), so the arc reads them and carries nothing: it is
-- drawn twice a frame (drawArc, shoulderFit), and a carry costs about half a
-- millisecond on the device. On a piece (replan's s.aimFace) the arc stops
-- where it reaches the piece's near face, a hair above the aim height: the
-- fourth value is the time drawn to, not the flight's.
local function arcLaunch(s)
	local sol = s.sol
	local speed, loft, sw = sol.speed or 0, sol.loft or 32, sol.swivel or 0
	local T, R, z1 = sol.T, sol.land, drill.tune.landZ
	local Tdraw = nil
	if s.projectile ~= "kubb" and sol.flightT and sol.dist then
		T, R, z1 = sol.flightT, sol.dist > 0.1 and sol.dist or 0.1, sol.aimZ or 0
		local face = s.aimFace
		if face and face > 0 and face < R then Tdraw = T * face / R end
	elseif not (s.drill and T and R) then
		local lx, ly
		lx, ly, T = flight.predict(s.playerX, s.playerY, sw, loft, speed)
		lx, ly = lx - s.playerX, ly - s.playerY
		R, z1 = sqrt(lx * lx + ly * ly), 0
	end
	if T <= 0 then return 0, 0, 0, 0 end
	-- a baton's hand (plan.solve's handZ, handFwd): on a short throw lower and
	-- ahead of the feet, so the arc starts there and carries the rest
	local h, g = flight.tune.handHeight, flight.tune.g
	if s.projectile ~= "kubb" and sol.handZ then
		h = sol.handZ
		if sol.flightT and sol.dist then
			local fwd = sol.handFwd or 0
			R = R - fwd
			if Tdraw then
				local f = s.aimFace - fwd
				Tdraw = f > 0 and T * f / R or nil
			end
		end
	end
	local vh = R / T
	return vh * math.sin(sw), vh * math.cos(sw), (z1 - h + 0.5 * g * T * T) / T, Tdraw or T
end

-- Where the planned arc starts: the hand (x, y, z), ahead of the stance and
-- lower on a short baton (plan.solve's handZ, handFwd). No tables.
local function arcOrigin(s)
	local sol = s.sol
	local h, f = flight.tune.handHeight, 0
	if s.projectile ~= "kubb" and sol and sol.handZ then h, f = sol.handZ, sol.handFwd or 0 end
	local sw = sol and sol.swivel or 0
	return s.playerX + f * math.sin(sw), s.playerY + f * math.cos(sw), h
end

-- (self-tests) the planned arc's start and launch: a drive's leaves the hand going
-- down (engine 0.16)
throw.arcLaunch, throw.arcOrigin = arcLaunch, arcOrigin

-- The arc shows for a baton and a drilled kubb (not the Playdate's lobbed
-- kubb tosses, which have no plan).
local function arcShown(s)
	return throw.tune.arc and (s.drill or s.projectile ~= "kubb")
end

-- The plan view's fit (camera.shoulder): the planned arc (the one drawArc
-- shows; before point arcFitFrom, its first rise near the hand, only inside
-- the sides: it may come in from the lower edge; a drill's too), and the
-- target circle's four sides. Scratch arrays, filled in place: no tables per
-- frame.
local fitX, fitY, fitZ = {}, {}, {}
shoulderFit = function(s, c)
	local t = throw.tune
	local n, across = 0, 0
	if arcShown(s) and not s.watching then
		local vx, vy, vz, T = arcLaunch(s)
		local x0, y0, h = arcOrigin(s)
		local g = flight.tune.g
		across = t.arcFitFrom - t.arcSkip
		for i = t.arcSkip, t.arcPoints do
			local tt = T * i / t.arcPoints
			n = n + 1
			fitX[n], fitY[n], fitZ[n] = x0 + vx * tt, y0 + vy * tt, h + vz * tt - 0.5 * g * tt * tt
		end
	end
	local R = t.markerRadius
	for k = 0, 3 do
		n = n + 1
		local a = k * math.pi / 2
		fitX[n], fitY[n], fitZ[n] = s.markerX + R * math.cos(a), s.markerY + R * math.sin(a), 0
	end
	camera.shoulder(c, s.playerX, s.playerY, s.swivel, s.lineY, n, fitX, fitY, fitZ, across)
end

-- The arc while aiming (Jamie and Tyler, 2026-11-14; a drill's too,
-- 2026-11-15): the plan's clean throw from where the player stands onto the
-- target circle (a drilled kubb's to where it lands, just short of it), the arc
-- the plan view is framed for (shoulderFit). It shows the plan, not the throw: the
-- backswing, the flick and where the crank stops still decide it. A dashed
-- line of arcPoints projected points (every other gap drawn), ending in (or,
-- for a drill, just short of) the circle. Drawn over the world each aim frame, outside its caches; no tables.
drawArc = function(s, c)
	local t = throw.tune
	local vx, vy, vz, T = arcLaunch(s)
	local x0, y0, h = arcOrigin(s)
	local g = flight.tune.g
	local n = t.arcPoints
	gfx.setColor(gfx.kColorBlack)
	-- a plan waiting for the movement to stop (s.planStale, a kept drive): the last
	-- good plan's arc, greyed, so it does not pass for the throw from here
	if s.planStale then gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer2x2) end
	gfx.setLineWidth(t.arcWidth)
	local px, py = nil, nil
	for i = t.arcSkip, n do
		local tt = T * i / n
		local sx, sy = camera.project(c, x0 + vx * tt, y0 + vy * tt, h + vz * tt - 0.5 * g * tt * tt)
		if sx and px and i % 2 == 0 then gfx.drawLine(px, py, sx, sy) end
		px, py = sx, sy
	end
	gfx.setLineWidth(1)
	gfx.setColor(gfx.kColorBlack)
end

-- (self-tests) the aim camera for this frame, then where the target circle
-- and drawArc's arc fall on it: the circle's screen box (minX, minY, maxX,
-- maxY), the box of the arc's points on screen, and how many of its points
-- are on screen and in all. nil when no arc shows.
function throw.arcBox(s)
	if not arcShown(s) then return nil end
	aimCamera(s)
	local c, t = s.aimCam, throw.tune
	local vx, vy, vz, T = arcLaunch(s)
	local x0, y0, h = arcOrigin(s)
	local g = flight.tune.g
	local huge = math.huge
	local ring = { huge, huge, -huge, -huge }
	local arc = { huge, huge, -huge, -huge }
	local function add(b, sx, sy)
		if sx < b[1] then b[1] = sx end; if sx > b[3] then b[3] = sx end
		if sy < b[2] then b[2] = sy end; if sy > b[4] then b[4] = sy end
	end
	local on, all = 0, 0
	for i = t.arcSkip, t.arcPoints do
		local tt = T * i / t.arcPoints
		local sx, sy = camera.project(c, x0 + vx * tt, y0 + vy * tt, h + vz * tt - 0.5 * g * tt * tt)
		all = all + 1
		if sx and sy <= 240 then on = on + 1; add(arc, sx, sy) end
	end
	local R = t.markerRadius
	for k = 1, t.markerSegments do
		local a = 2 * math.pi * k / t.markerSegments
		local sx, sy = camera.project(c, s.markerX + R * math.cos(a), s.markerY + R * math.sin(a), 0)
		if not sx then return ring, arc, on, all, true end
		add(ring, sx, sy)
	end
	return ring, arc, on, all
end

drawMarker = function(s, c, line)
	local t = throw.tune
	local mx, my = s.markerX, s.markerY
	if line then
		local x0, y0, x1, y1 = camera.projectSegment(c, s.playerX, s.lineY, 0, mx, my, 0)
		if x0 then
			gfx.setLineWidth(2)
			gfx.setColor(gfx.kColorBlack)
			gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer2x2)
			gfx.drawLine(x0, y0, x1, y1)
		end
	end
	local n, R = t.markerSegments, t.markerRadius
	for i = 1, n do
		local a = 2 * math.pi * i / n
		local sx, sy = camera.project(c, mx + R * math.cos(a), my + R * math.sin(a), 0)
		if not sx then return end
		ringPts[2 * i - 1], ringPts[2 * i] = sx, sy
	end
	for i = 2 * n + 1, #ringPts do ringPts[i] = nil end
	local cx, cy = camera.project(c, mx, my, 0)
	local w = (ringPts[2 * n - 1] - ringPts[n - 1]) * 0.3
	for pass = 1, 2 do
		gfx.setColor(pass == 1 and gfx.kColorWhite or gfx.kColorBlack)
		gfx.setLineWidth(pass == 1 and 4 or 2)
		gfx.drawPolygon(unpack(ringPts))
		gfx.drawLine(cx - w, cy, cx + w, cy)
		gfx.drawLine(cx, cy - w * 0.6, cx, cy + w * 0.6)
	end
	gfx.setLineWidth(1)
	gfx.setColor(gfx.kColorBlack)
end

-- The wind for the next throw (core/wind: m/s in the view frame), or nil
-- for still air. The match sets it before each throw; practice has none.
function throw.setWind(s, wx, wy, text)
	s.windX, s.windY, s.windText = wx, wy, text
end

function throw.draw(s)
	s.drawStart = s.clock() - (s.frameStart or 0)
	local ok = throw.drawFrame(s)
	s.drawEnd = s.clock() - (s.frameStart or 0)
	return ok
end

-- What the prompt over the clock says while the player aims: WIND BACK
-- (idle, or short of the power target), FLICK! inside it, EASE OFF past it;
-- CRANK DOWN while the crank sits behind the bottom unarmed (it must come
-- down through 6 first); nothing during the flick.
local function promptFor(s, sw, sol)
	local ph = sw.phase
	if ph == "winding" then
		local b = sw.back
		if b < sol.powerLo then return "WIND BACK" end
		if b <= sol.powerHi then return "FLICK!" end
		return "EASE OFF"
	elseif ph == "idle" then
		if not s.armed and (s.arm or 0) < -3 then return "CRANK DOWN" end
		return "WIND BACK"
	end
	return nil
end

-- hud.clock's state for this frame (s.dial, reused).
local function dialState(s, aiming)
	local st, sw, sol = s.dial, s.swing, s.sol
	local P = nil   -- the targets shown: the player's plan, or the Playdate's
	if s.watching or s.scripted and not aiming then P = s.cpuPlan else P = sol end
	st.powerLo, st.powerHi = P and P.powerLo, P and P.powerHi
	st.releaseLo, st.releaseHi = P and P.releaseLo, P and P.releaseHi
	st.deadDeg, st.overDeg = swing.tune.startBackDeg, throw.tune.overDeg
	local stop = s.lastStop
	if stop and stop > 180 then stop = 180 end
	st.lastBack, st.lastStop, st.prompt = s.lastBack, stop, nil
	if s.mode == "cpuswing" then
		st.phase, st.arm, st.crank, st.back = s.cpuPhase, s.cpuArm, 0, s.cpuBack
		st.lastBack, st.lastStop = nil, nil
	elseif aiming and not s.watching then
		st.phase, st.arm, st.crank, st.back = sw.phase, sw.arm, s.arm or 0, sw.back
		st.prompt = promptFor(s, sw, sol)
		-- just flipped (throw.flipCrank): say so while the crank is still idle
		if s.flipNote > 0 and sw.phase == "idle" then st.prompt = "CRANK FLIPPED" end
	elseif aiming then
		-- the Playdate thinking: the hand at rest
		st.phase, st.arm, st.crank, st.back = "idle", 0, 0, 0
	else
		-- in flight and at rest: the hand where the crank stopped
		st.phase, st.arm, st.crank, st.back = "idle", 0, stop or 0, 0
	end
	return st
end

function throw.drawFrame(s)
	local aiming = s.mode == "aim" or s.mode == "cpuswing"
	local b = nil
	local n = s.nitems
	if not aiming then
		if s.projectile == "kubb" then n = n + 1 else b = s.baton end
	end
	render.advantageY = s.advY
	render.kidY = s.kidY
	local cam = s.viewCam or s.aimCam
	render.draw(cam, s.items, n, b)
	burst.draw(s.burst, cam)
	-- the target circle: while aiming (the Playdate's only when its plan says
	-- where), and under a drilled kubb's flight and rest
	local marker = (aiming and (not s.watching or s.cpuTarget)) or (not aiming and s.thisDrill)
	if marker then drawMarker(s, cam, s.drill) end
	if s.mode == "aim" and not s.watching and arcShown(s) then drawArc(s, cam) end

	local hs = s.hudState
	hs.playerX, hs.lineY = s.playerX, s.playerY
	if marker or not s.watching then
		hs.aimX, hs.aimY = s.markerX, s.markerY
	else
		hs.aimX, hs.aimY = flight.aimPreview(s.playerX, s.playerY, s.swivel, s.loftDeg, s.cpuSpeed or 9)
	end
	hs.baton = (not aiming) and s.baton or nil
	hs.pieces, hs.npieces = s.items, s.nitems
	hs.advY = s.advY
	hs.kidY = s.kidY
	local fl = s.flight
	if not aiming then
		hs.landX, hs.landY = fl.lx, fl.ly
	elseif s.last and s.last.landX then
		hs.landX, hs.landY = s.last.landX, s.last.landY
	else
		hs.landX, hs.landY = nil, nil
	end
	hud.minimap(hs)
	-- the wind (a match with WIND on): an arrow on the minimap, the speed above it
	if s.windText and (aiming or s.mode == "flight") then hud.wind(s.windText, s.windX, s.windY) end
	drawRail(s)

	-- s.covered: a card is over the pitch (the match's hand-off and winner
	-- cards), so the plaques stay out of the way
	if s.covered then return end
	-- throwing from the advantage line (yours or the Playdate's): a flag under
	-- the rail while aiming
	if aiming and s.advText then hud.advantage(s.advText) end
	-- the clock, always: the arm while aiming, the last throw's dots after it
	local st = dialState(s, aiming)
	hud.clock(st)
	s.promptText = st.prompt    -- (self-tests read it)
	local sw = s.swing
	s.hintText = nil
	if aiming and s.watching then
		hud.prompt("WATCH", true)
		s.promptText = "WATCH"
	elseif aiming then
		local kubb = s.projectile == "kubb"
		local pv = kubb and s.spin or s.tilt
		hud.planChip(kubb and "kubb" or "baton", pv)
		local idle = sw.phase == "idle" or sw.phase == "cooldown"
		-- the last throw's verdicts, until the next wind-up (and a drill's
		-- rest distance where the plan chip would be)
		if s.showVerdicts and idle then
			hud.verdicts(s.vPower, s.vRelease, s.vSteady, s.vSide)
			if pv == 0 and s.restText then hud.cutFlag(s.restText) end
		end
		if s.showReadout and s.readout and idle then hud.readout(s.readout) end
		s.arcWords = nil
		if s.planHeld and s.mode == "aim" then
			-- ARC with B held (engine 0.16): the planned launch angle, DRIVE under
			-- the knee, and in the hint what a lower arc does
			local drive = throw.isDrive(s)
			hud.arcChip(s.sol.loft or 0, drive)
			s.arcWords = throw.arcWords(s, drive)    -- (self-tests read it)
			hud.hint(s.arcWords)
		-- the nudge (device/crank): turning forward again and again, never back
		elseif sw.phase == "idle" and s.mode == "aim" and crank.nudgeShown(s.nudge, throw.tune) then
			s.hintText = s.nudgeText    -- (self-tests read it)
			hud.hint(s.nudgeText)
		end
		if s.input:docked() then hud.crankPrompt() end
	elseif s.last then
		-- after the release: the result flag; at rest the verdicts and a
		-- drilled kubb's rest distance
		hud.flag(s.flagText)
		if s.mode == "flight" then
			if s.slowMo then hud.slow() end
		else
			if s.showVerdicts then hud.verdicts(s.vPower, s.vRelease, s.vSteady, s.vSide) end
			if s.restText then hud.cutFlag(s.restText) end
		end
		if s.showReadout and s.readout then hud.readout(s.readout) end
	end
	-- HOW TO THROW's panel under the rail, while aiming
	if s.howto and s.mode == "aim" then tw.render.howto.draw(s.howto, s.camMix > 0) end
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
		-- the marker's distance, and beside it what the caller gave (a drill's
		-- score; a match's kubb toss gives nothing)
		r1, r2 = s.railDist, s.railR1
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
