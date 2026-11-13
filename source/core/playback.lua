-- Compute ahead and play back (DESIGN 5). The physics runs at a fixed step
-- (world.tune.dt) as far ahead of the screen as the frame budget allows and
-- records every body's pose once per display frame. The scene shows recorded
-- frames at the display rate; if the simulation falls behind, the scene
-- waits on the last recorded frame (playback slows) instead of skipping.
-- Pure Lua: the clock is passed in.
--
-- Storage: one flat number array per body, 7 numbers per frame
-- (x, y, z, qw, qx, qy, qz), starting at the first frame the body was awake.
-- Before that the body sits at its starting pose. A body woken late costs
-- nothing until then; a standing kubb nobody touches costs nothing at all.
--
--   local pb = playback.new(w, 1 / 50)
--   each frame: playback.advance(pb, budgetSeconds, clock)
--               if pb.frame < pb.frames then pb.frame = pb.frame + 1 end
--               playback.pose(pb, i, pb.frame) for each body index i
--   pb.done and pb.frame == pb.frames: the throw is over
import "core/tw"
import "core/world"

local world = tw.world

local playback = {}

local function record(pb)
	local w = pb.w
	local f = pb.frames
	for i = 1, w.n do
		local b = w.bodies[i]
		local r = pb.rec[i]
		if not r then
			r = { start = -1, data = {}, x = b.x, y = b.y, z = b.z, qw = b.qw, qx = b.qx, qy = b.qy, qz = b.qz }
			pb.rec[i] = r
		end
		if r.start < 0 and b.everAwake then r.start = f end
		if r.start >= 0 then
			local d, k = r.data, (f - r.start) * 7
			d[k + 1], d[k + 2], d[k + 3] = b.x, b.y, b.z
			d[k + 4], d[k + 5], d[k + 6], d[k + 7] = b.qw, b.qx, b.qy, b.qz
		end
	end
end

-- A playback of world w (already built and launched) at frameDt per frame.
function playback.new(w, frameDt)
	local pb = {
		w = w,
		frameDt = frameDt,
		frames = 0,       -- last recorded frame (frame 0 is the start)
		frame = 0,        -- the frame on screen; the scene advances it
		done = false,     -- the world came to rest (or ran out of time)
		rec = {},
		steps = 0,        -- physics steps taken
		busy = 0,         -- seconds spent in advance()
		awakeMax = 0,     -- the most bodies awake in any step
		contactsMax = 0,  -- the most contacts in any step
	}
	record(pb)
	return pb
end

-- Step the world until `ahead` frames past the one on screen are recorded,
-- the world is at rest, or `budget` seconds of clock() have gone by.
-- Returns the number of steps taken.
function playback.advance(pb, budget, clock, ahead)
	if pb.done then return 0 end
	local w = pb.w
	local t0 = clock()
	local stop = t0 + budget
	local want = pb.frame + (ahead or 1000000)
	local n = 0
	local dt = world.tune.dt
	while pb.frames < want do
		world.step(w)
		n = n + 1
		if w.awakeCount > pb.awakeMax then pb.awakeMax = w.awakeCount end
		if w.contacts > pb.contactsMax then pb.contactsMax = w.contacts end
		local rest = world.isAtRest(w)
		-- record each display frame this step reached (within half a step)
		while w.time + dt * 0.5 >= (pb.frames + 1) * pb.frameDt do
			pb.frames = pb.frames + 1
			record(pb)
		end
		if rest then
			pb.frames = pb.frames + 1
			record(pb)
			pb.done = true
			break
		end
		if clock() >= stop then break end
	end
	pb.steps = pb.steps + n
	pb.busy = pb.busy + (clock() - t0)
	return n
end

-- Pose of body index i at frame f (clamped to what is recorded).
function playback.pose(pb, i, f)
	local r = pb.rec[i]
	if f > pb.frames then f = pb.frames end
	if r.start < 0 or f < r.start then
		return r.x, r.y, r.z, r.qw, r.qx, r.qy, r.qz
	end
	local d, k = r.data, (f - r.start) * 7
	return d[k + 1], d[k + 2], d[k + 3], d[k + 4], d[k + 5], d[k + 6], d[k + 7]
end

-- Slow motion around a hit. Because the physics runs ahead of the screen,
-- the time of the first hit is known before it is shown. Returns the speed
-- of the picture (1 = real time) at screen time `t` for a hit at `hitTime`
-- (nil = no hit known): slowRate from `lead` seconds before the hit until
-- `hold` seconds after it, then easing back to 1 over `ease` seconds.
playback.slow = { rate = 0.3, lead = 0.10, hold = 0.45, ease = 0.35 }

function playback.speed(t, hitTime)
	if not hitTime then return 1 end
	local k = playback.slow
	local d = t - hitTime
	if d < -k.lead then return 1 end
	if d <= k.hold then return k.rate end
	local e = (d - k.hold) / k.ease
	if e >= 1 then return 1 end
	return k.rate + (1 - k.rate) * e
end

-- Run to the end without a clock (tests, the desktop).
function playback.finish(pb)
	while not pb.done do playback.advance(pb, math.huge, function() return 0 end) end
	return pb
end

-- Bytes of pose data held (8 per number; a rough figure for the readout).
function playback.size(pb)
	local n = 0
	for i = 1, #pb.rec do n = n + #pb.rec[i].data end
	return n * 8
end

tw.playback = playback
