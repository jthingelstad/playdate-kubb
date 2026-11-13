-- Pinhole cameras in the world frame of DESIGN.md section 2 (meters; x across,
-- y downfield, z up) projecting onto the 400x240 screen.
-- Pure Lua: no playdate.*.
--
-- A camera is a plain table (see camera.new). It is filled in place by
-- camera.lookAt / camera.aim / camera.impact / camera.follow so the game can
-- keep one table per camera and make no garbage per frame. camera.project
-- returns plain numbers (sx, sy, depth), never a table.
--
-- Every number that sets the framing is in camera.tune.
import "core/tw"

local sqrt, sin, cos, max, min, abs = math.sqrt, math.sin, math.cos, math.max, math.min, math.abs

local camera = {}

camera.SCREEN_W = 400
camera.SCREEN_H = 240

camera.tune = {
	near = 0.05,           -- m; points closer than this along the view axis are not projected
	aim = {
		back = 3.0,          -- m behind the throwing line (DESIGN 3), measured along the aim
		height = 3.4,        -- m above the ground (DESIGN 3)
		lookDist = 7.5,      -- m from the thrower, along the aim, to the ground point at screen center x
		cy = 110,            -- screen row of that ground point (the principal point)
		minTargetPx = 12.5,  -- farthest live target (a standing 0.15 m kubb) at least this tall
		fMin = 880,          -- px; the long lens of DESIGN 3 (about 26 degrees wide) ...
		fMax = 1000,         -- ... to about 23 degrees wide
		stepBackRef = 11,    -- m from the camera to the far baseline with the player on the line;
		                     -- the lens limit grows by stepBack / this when the player steps back
	},
	impact = {
		dist = 2.75,         -- m, horizontal, from the predicted landing point (DESIGN 3: 2.5 to 3)
		height = 0.9,        -- m (DESIGN 3: low, about 0.9)
		yaw = 0.42,          -- rad the camera sits off the line of flight, toward the pitch center
		lookUp = 0.08,       -- m above the landing point it looks at
		f = 700,             -- px; a standing kubb at the landing point is about 35 px tall
		cy = 132,
	},
	follow = {
		marginX = 30,        -- px kept between the baton's center and the screen edge while following
		marginTop = 60,
		marginBottom = 40,
		catchBy = 0.25,      -- fraction of the flight by which the baton must be in frame; before
		                     -- that it may still be below the frame (it rises into the aim view
		                     -- from the thrower's hand) and the camera does not chase it
		slack = 600,         -- px it may be below the frame at release, shrinking to 0 by catchBy
		midZoomOut = 0.45,   -- the lens widens by up to this fraction mid-flight, so the high
		                     -- baton and the pitch below it fit in one frame
	},
}

local KUBB_H <const> = 0.15

function camera.new()
	return {
		px = 0, py = 0, pz = 0,      -- position
		fx = 0, fy = 1, fz = 0,      -- forward (unit)
		rx = 1, ry = 0, rz = 0,      -- right (unit, horizontal)
		ux = 0, uy = 0, uz = 1,      -- up (unit)
		f = 900, cx = 200, cy = 120, -- focal length in px and principal point
		lx = 0, ly = 1, lz = 0,      -- the point looked at
	}
end

-- Point the camera at (tx, ty, tz) from (px, py, pz). The right vector stays
-- horizontal, so the horizon is level. Not for looking straight down.
function camera.lookAt(c, px, py, pz, tx, ty, tz)
	c.px, c.py, c.pz = px, py, pz
	c.lx, c.ly, c.lz = tx, ty, tz
	local fx, fy, fz = tx - px, ty - py, tz - pz
	local n = sqrt(fx * fx + fy * fy + fz * fz)
	fx, fy, fz = fx / n, fy / n, fz / n
	local rx, ry = fy, -fx
	local rn = sqrt(rx * rx + ry * ry)
	rx, ry = rx / rn, ry / rn
	c.fx, c.fy, c.fz = fx, fy, fz
	c.rx, c.ry, c.rz = rx, ry, 0
	-- up = right x forward
	c.ux = ry * fz
	c.uy = -rx * fz
	c.uz = rx * fy - ry * fx
	return c
end

-- Camera-space coordinates: right, up, depth (along the view axis).
function camera.toView(c, x, y, z)
	local dx, dy, dz = x - c.px, y - c.py, z - c.pz
	return dx * c.rx + dy * c.ry + dz * c.rz,
		dx * c.ux + dy * c.uy + dz * c.uz,
		dx * c.fx + dy * c.fy + dz * c.fz
end

-- Screen position of a world point: sx, sy, depth. Returns nil when the
-- point is behind the near plane.
function camera.project(c, x, y, z)
	local dx, dy, dz = x - c.px, y - c.py, z - c.pz
	local d = dx * c.fx + dy * c.fy + dz * c.fz
	if d < camera.tune.near then return nil end
	local s = c.f / d
	return c.cx + s * (dx * c.rx + dy * c.ry + dz * c.rz),
		c.cy - s * (dx * c.ux + dy * c.uy + dz * c.uz),
		d
end

-- Screen size in px of a standing upright segment of height h at (x, y):
-- the distance between its projected base and top.
function camera.uprightPx(c, x, y, h)
	local ax, ay = camera.project(c, x, y, 0)
	local bx, by = camera.project(c, x, y, h)
	if not ax or not bx then return 0 end
	return sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- Unit aim direction for a swivel angle in radians (0 = straight downfield,
-- positive = to the right, toward +x).
function camera.aimDir(swivel)
	return sin(swivel), cos(swivel)
end

-- The aim camera (DESIGN 3): a crane behind the thrower standing at
-- (playerX, lineY), looking along the swivel. `targets` is an array of
-- {x=, y=} live targets (standing kubbs): the focal length is the smallest in
-- [fMin, fMax] that shows the farthest of them at least minTargetPx tall.
-- `stepBack` (m, optional) is how far behind the throwing line the player
-- stands: the lens limit grows in proportion, so stepping back does not
-- shrink the targets below minTargetPx.
function camera.aim(c, playerX, lineY, swivel, targets, stepBack)
	local t = camera.tune.aim
	local dx, dy = camera.aimDir(swivel)
	camera.lookAt(c,
		playerX - dx * t.back, lineY - dy * t.back, t.height,
		playerX + dx * t.lookDist, lineY + dy * t.lookDist, 0)
	c.cx, c.cy = camera.SCREEN_W / 2, t.cy
	c.f = 1
	local need = t.fMin
	if targets then
		for i = 1, #targets do
			local k = targets[i]
			local px = camera.uprightPx(c, k.x, k.y, KUBB_H)
			if px > 0 then need = max(need, t.minTargetPx / px) end
		end
	end
	local fMax = t.fMax * (1 + (stepBack or 0) / t.stepBackRef)
	c.f = min(fMax, max(t.fMin, need))
	return c
end

-- The impact camera (DESIGN 3): low and close to the predicted landing point
-- (lx, ly), set back along the line of flight (dirX, dirY, unit horizontal)
-- and turned off it by tune.impact.yaw toward the pitch center.
function camera.impact(c, lx, ly, dirX, dirY)
	local t = camera.tune.impact
	local side = (lx > 0) and 1 or -1           -- swing the camera toward x = 0
	local a = t.yaw * side
	local ca, sa = cos(a), sin(a)
	-- rotate the backwards direction (-dir) by a about z
	local bx, by = -dirX, -dirY
	bx, by = bx * ca - by * sa, bx * sa + by * ca
	camera.lookAt(c, lx + bx * t.dist, ly + by * t.dist, t.height, lx, ly, t.lookUp)
	c.f, c.cx, c.cy = t.f, camera.SCREEN_W / 2, t.cy
	return c
end

local function smooth(s)
	if s <= 0 then return 0 elseif s >= 1 then return 1 end
	return s * s * (3 - 2 * s)
end
camera.smooth = smooth

-- Is the screen point inside the frame less the follow margins? `slack`
-- extends the bottom edge downward.
local function inFrame(sx, sy, slack)
	local m = camera.tune.follow
	return sx and sx >= m.marginX and sx <= camera.SCREEN_W - m.marginX
		and sy >= m.marginTop and sy <= camera.SCREEN_H - m.marginBottom + slack
end

-- The follow camera: blends from camera a (aim) to camera b (impact) as s
-- goes 0 -> 1 over the flight, eased. The baton at (bx, by, bz) is kept in
-- frame: if it would fall outside, the look point is pulled toward it just
-- far enough (found by bisection). Right after release the baton is still
-- below the aim view; it is allowed to rise into frame on its own until
-- tune.follow.catchBy of the flight, so the shot starts as the aim view.
function camera.follow(c, a, b, s, bx, by, bz)
	local e = smooth(s)
	local px = a.px + (b.px - a.px) * e
	local py = a.py + (b.py - a.py) * e
	local pz = a.pz + (b.pz - a.pz) * e
	local lx = a.lx + (b.lx - a.lx) * e
	local ly = a.ly + (b.ly - a.ly) * e
	local lz = a.lz + (b.lz - a.lz) * e
	-- focal length blends in log space so the zoom feels even
	local f = a.f * (b.f / a.f) ^ e
	f = f * (1 - camera.tune.follow.midZoomOut * math.sin(math.pi * e))
	c.f, c.cx = f, a.cx
	c.cy = a.cy + (b.cy - a.cy) * e
	camera.lookAt(c, px, py, pz, lx, ly, lz)
	if not bx then return c end
	local m = camera.tune.follow
	local slack = m.slack * (1 - min(1, s / m.catchBy))
	local sx, sy = camera.project(c, bx, by, bz)
	if not inFrame(sx, sy, slack) then
		local lo, hi = 0, 1
		for _ = 1, 12 do
			local w = (lo + hi) / 2
			camera.lookAt(c, px, py, pz, lx + (bx - lx) * w, ly + (by - ly) * w, lz + (bz - lz) * w)
			sx, sy = camera.project(c, bx, by, bz)
			if inFrame(sx, sy, slack) then hi = w else lo = w end
		end
		camera.lookAt(c, px, py, pz, lx + (bx - lx) * hi, ly + (by - ly) * hi, lz + (bz - lz) * hi)
	end
	return c
end

-- Clip a ground-plane (z = 0) or general polygon against the near plane and
-- project it. `xs, ys, zs` hold n world points; the screen polygon is written
-- as x1, y1, x2, y2, ... into `out` (reused). Returns the number of screen
-- points (0 when it is all behind the camera).
local vx, vy, vd = {}, {}, {}
function camera.projectPoly(c, n, xs, ys, zs, out)
	local near = camera.tune.near
	for i = 1, n do
		vx[i], vy[i], vd[i] = camera.toView(c, xs[i], ys[i], zs and zs[i] or 0)
	end
	local m = 0
	local f, cx, cy = c.f, c.cx, c.cy
	for i = 1, n do
		local j = (i % n) + 1
		local ai, aj = vd[i] >= near, vd[j] >= near
		if ai then
			m = m + 1
			out[2 * m - 1] = cx + f * vx[i] / vd[i]
			out[2 * m] = cy - f * vy[i] / vd[i]
		end
		if ai ~= aj then
			local t = (near - vd[i]) / (vd[j] - vd[i])
			m = m + 1
			out[2 * m - 1] = cx + f * (vx[i] + (vx[j] - vx[i]) * t) / near
			out[2 * m] = cy - f * (vy[i] + (vy[j] - vy[i]) * t) / near
		end
	end
	return m
end

-- Clip a segment against the near plane and project it. Returns
-- x1, y1, x2, y2 on screen, or nil when it is all behind the camera.
function camera.projectSegment(c, x1, y1, z1, x2, y2, z2)
	local near = camera.tune.near
	local ax, ay, ad = camera.toView(c, x1, y1, z1)
	local bx, by, bd = camera.toView(c, x2, y2, z2)
	if ad < near and bd < near then return nil end
	if ad < near then
		local t = (near - ad) / (bd - ad)
		ax, ay, ad = ax + (bx - ax) * t, ay + (by - ay) * t, near
	elseif bd < near then
		local t = (near - bd) / (ad - bd)
		bx, by, bd = bx + (ax - bx) * t, by + (ay - by) * t, near
	end
	local f = c.f
	return c.cx + f * ax / ad, c.cy - f * ay / ad, c.cx + f * bx / bd, c.cy - f * by / bd
end

-- The minimap (DESIGN 3): a 45 x 72 px top-down pitch at 9 px per meter with
-- the far baseline (y = 8) at the top. ox, oy is its top-left pixel.
camera.minimap = { scale = 9, w = 45, h = 72, ox = 349, oy = 4 }

function camera.toMinimap(x, y)
	local m = camera.minimap
	return m.ox + (x + 2.5) * m.scale, m.oy + (8 - y) * m.scale
end

tw.camera = camera
