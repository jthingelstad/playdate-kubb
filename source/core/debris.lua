-- What lies on the pitch within a turn that the rules engine does not keep:
-- the batons already thrown and the kubbs they knocked down. In Kubb a
-- toppled kubb and a thrown baton stay where they came to rest until the
-- turn is over; a later baton can hit them, be deflected by them, or push
-- them into a standing kubb. The engine is still the judge (it has the
-- toppled kubbs in a hand already); this module only carries their poses
-- from throw to throw so the next throw's physics world has them as bodies.
-- Pure Lua: no playdate.*. Not a per-frame path: once per throw.
--
-- It also carries the exact body pose (tilt, height, which face is down) of
-- every lying kubb the engine does keep on the pitch: during the inkast the
-- tossed kubbs lie where they landed (in bounds or out) until they are raised
-- or picked up for a rethrow, and the engine's
-- pose ({x, y, angle}) would lay them flat on a face. An exact pose is used
-- only while the engine's pose is the one it was recorded with.
--
--   local d = debris.new()
--   debris.begin(d, turn)                  -- a new turn clears everything
--   local list = debris.pieces(d, side)    -- tw.world pieces, view frame
--   debris.applyExact(d, pieces, side)     -- exact poses onto outcome.pieces
--   ... the throw ...
--   debris.carry(d, res, side)             -- struck debris moves
--   debris.add(d, id, kind, res, side)     -- a baton or newly downed kubb
--   debris.recordExact(d, g, res, side)
--
-- Poses are kept in the world frame (core/frame) and handed out in the
-- thrower's view frame, so Team B's turned view is the same pitch.
import "core/tw"
import "core/frame"

local frame = tw.frame

local debris = {}

debris.tune = {
	matchEps = 1e-6,   -- m; an exact pose applies while the engine's x, y are these
}

function debris.new()
	return { turn = nil, list = {}, exact = {} }
end

-- Clear everything (the hand-off: the pitch is the engine's again).
function debris.clear(d)
	d.list, d.exact = {}, {}
end

-- Start (or continue) turn `turn`: a different turn clears the debris.
function debris.begin(d, turn)
	if d.turn ~= turn then
		debris.clear(d)
		d.turn = turn
	end
end

function debris.count(d) return #d.list end

-- A world-frame pose from a result body (view frame of `side`).
local function fromBody(side, rb)
	local x, y = frame.point(side, rb.x, rb.y)
	local qw, qx, qy, qz = frame.quat(side, rb.qw, rb.qx, rb.qy, rb.qz)
	return x, y, rb.z, qw, qx, qy, qz
end

local function setFrom(e, side, rb)
	e.x, e.y, e.z, e.qw, e.qx, e.qy, e.qz = fromBody(side, rb)
end

local function find(d, id)
	for i, e in ipairs(d.list) do
		if e.id == id then return e, i end
	end
	return nil
end

-- Add (or move) piece `id` of `kind` ("kubb" | "baton") at its rest pose in
-- `res` (tw.world result, view frame of `side`). Returns the entry, or nil
-- when the result has no such body.
function debris.add(d, id, kind, res, side)
	local rb = res.bodies[id]
	if not rb then return nil end
	local e = find(d, id)
	if not e then
		e = { id = id, kind = kind }
		d.list[#d.list + 1] = e
	end
	setFrom(e, side, rb)
	return e
end

-- Move every debris piece to where this throw left it (struck or not: a
-- body that never woke rests where it started).
function debris.carry(d, res, side)
	for _, e in ipairs(d.list) do
		local rb = res.bodies[e.id]
		if rb then setFrom(e, side, rb) end
	end
end

-- The debris as tw.world pieces (full poses, already down) in `side`'s view
-- frame: { id, kind, x, y, z, qw..qz, toppled = true, debris = true }.
function debris.pieces(d, side)
	local out = {}
	for i, e in ipairs(d.list) do
		local x, y = frame.point(side, e.x, e.y)
		local qw, qx, qy, qz = frame.quat(side, e.qw, e.qx, e.qy, e.qz)
		out[i] = { id = e.id, kind = e.kind, x = x, y = y, z = e.z, qw = qw, qx = qx, qy = qy, qz = qz,
			toppled = true, debris = true }
	end
	return out
end

-- Remember the exact body pose of every kubb the engine has lying on the
-- pitch whose engine pose is where its body came to rest.
function debris.recordExact(d, g, res, side)
	local eps = debris.tune.matchEps
	local keep = {}
	for _, k in ipairs(g:onPitch()) do
		local p = k.pose
		if not p.standing then
			local rb = res.bodies[k.id]
			local e
			if rb then
				local x, y = frame.point(side, rb.x, rb.y)
				if (x - p.x) ^ 2 + (y - p.y) ^ 2 <= eps * eps then
					e = { ex = p.x, ey = p.y }
					setFrom(e, side, rb)
				end
			end
			-- a kubb this throw did not reach keeps the pose it had
			if not e then
				local old = d.exact[k.id]
				if old and (old.ex - p.x) ^ 2 + (old.ey - p.y) ^ 2 <= eps * eps then e = old end
			end
			keep[k.id] = e
		end
	end
	d.exact = keep
end

-- Put the exact poses onto outcome.pieces (view frame of `side`): each lying
-- piece whose engine pose is the recorded one gets the body's pose and z.
function debris.applyExact(d, pieces, side)
	local eps = debris.tune.matchEps
	for _, p in ipairs(pieces) do
		local e = d.exact[p.id]
		if e and p.toppled and p.pose and (e.ex - p.pose.x) ^ 2 + (e.ey - p.pose.y) ^ 2 <= eps * eps then
			p.x, p.y = frame.point(side, e.x, e.y)
			p.qw, p.qx, p.qy, p.qz = frame.quat(side, e.qw, e.qx, e.qy, e.qz)
			p.z = e.z
		end
	end
end

tw.debris = debris
