-- Contact generation (narrow phase). Pure Lua: no playdate.*.
--
-- Contacts go into one reused buffer of parallel arrays (no tables per
-- contact). A contact is between body A and body B (B = false for the
-- ground), at world point P on A, with unit normal N pointing from B toward
-- A, and separation `sep` (negative = overlapping). Contacts are made a little
-- before touching (speculative, within `margin`), so fast pieces do not pass
-- through each other between steps.
--
-- Shapes (DESIGN 5):
--   box vs ground       the eight corners
--   capsule vs ground   the two end spheres (on a plane the lowest points of
--                       a capsule are always at its end spheres, so a baton
--                       lying flat rests on both and rolls about its axis)
--   capsule vs box      the closest points of the segment and the box, plus
--                       each end sphere, so a baton lying across a kubb rests
--   box vs box          corners of each box inside (or near) the other. This
--                       misses pure edge-on-edge contact (two edges crossing
--                       with no corner inside); acceptable at this scale
--   capsule vs capsule  closest points of the two segments
import "core/tw"

local sqrt, abs = math.sqrt, math.abs

local collide = {}

-- The contact buffer.
local C = {
	n = 0,
	A = {}, B = {}, slot = {},
	px = {}, py = {}, pz = {},
	nx = {}, ny = {}, nz = {},
	sep = {},
}
collide.C = C

function collide.reset()
	C.n = 0
end

local cA, cB, cSlot = C.A, C.B, C.slot
local cPx, cPy, cPz, cNx, cNy, cNz, cSep = C.px, C.py, C.pz, C.nx, C.ny, C.nz, C.sep

local function add(a, b, px, py, pz, nx, ny, nz, sep, slot)
	local i = C.n + 1
	C.n = i
	cA[i], cB[i], cSlot[i] = a, b, slot
	cPx[i], cPy[i], cPz[i] = px, py, pz
	cNx[i], cNy[i], cNz[i] = nx, ny, nz
	cSep[i] = sep
end
collide.add = add

local SX = { -1, 1, 1, -1, -1, 1, 1, -1 }
local SY = { -1, -1, 1, 1, -1, -1, 1, 1 }
local SZ = { -1, -1, -1, -1, 1, 1, 1, 1 }
collide.SX, collide.SY, collide.SZ = SX, SY, SZ

-- Box b against the ground plane z = 0: each corner below `margin`.
function collide.groundBox(b, margin)
	local hx, hy, hz = b.hx, b.hy, b.hz
	local ax, ay, az = b.r11 * hx, b.r21 * hx, b.r31 * hx
	local bx, by, bz = b.r12 * hy, b.r22 * hy, b.r32 * hy
	local cx, cy, cz = b.r13 * hz, b.r23 * hz, b.r33 * hz
	-- quick reject: the lowest corner is above the margin
	if b.z - (abs(az) + abs(bz) + abs(cz)) >= margin then return end
	local x0, y0, z0 = b.x, b.y, b.z
	for k = 1, 8 do
		local sx, sy, sz = SX[k], SY[k], SZ[k]
		local pz = z0 + sx * az + sy * bz + sz * cz
		if pz < margin then
			add(b, false, x0 + sx * ax + sy * bx + sz * cx, y0 + sx * ay + sy * by + sz * cy, pz,
				0, 0, 1, pz, k)
		end
	end
end

-- Capsule b against the ground: its two end spheres.
function collide.groundCapsule(b, margin)
	local hl, r = b.hl, b.r
	local ax, ay, az = b.r13 * hl, b.r23 * hl, b.r33 * hl
	local z1, z2 = b.z - az - r, b.z + az - r
	if z1 < margin then add(b, false, b.x - ax, b.y - ay, z1, 0, 0, 1, z1, 1) end
	if z2 < margin then add(b, false, b.x + ax, b.y + ay, z2, 0, 0, 1, z2, 2) end
end

-- Closest point of box B to the world point p. Returns the distance from
-- the box surface (negative inside: minus the depth to the nearest face),
-- the world unit normal pointing out of the box toward p, and the box point.
local function pointBox(B, px, py, pz)
	local dx, dy, dz = px - B.x, py - B.y, pz - B.z
	local r11, r12, r13, r21, r22, r23, r31, r32, r33 =
		B.r11, B.r12, B.r13, B.r21, B.r22, B.r23, B.r31, B.r32, B.r33
	local lx = r11 * dx + r21 * dy + r31 * dz
	local ly = r12 * dx + r22 * dy + r32 * dz
	local lz = r13 * dx + r23 * dy + r33 * dz
	local hx, hy, hz = B.hx, B.hy, B.hz
	local qx = lx > hx and hx or (lx < -hx and -hx or lx)
	local qy = ly > hy and hy or (ly < -hy and -hy or ly)
	local qz = lz > hz and hz or (lz < -hz and -hz or lz)
	local ex, ey, ez = lx - qx, ly - qy, lz - qz
	local d2 = ex * ex + ey * ey + ez * ez
	local nx, ny, nz, dist
	if d2 > 1e-14 then
		dist = sqrt(d2)
		nx, ny, nz = ex / dist, ey / dist, ez / dist
	else
		-- inside: the face of least penetration
		local px_, py_, pz_ = hx - abs(lx), hy - abs(ly), hz - abs(lz)
		if px_ <= py_ and px_ <= pz_ then
			nx, ny, nz, dist = (lx >= 0) and 1 or -1, 0, 0, -px_
			qx = nx * hx
		elseif py_ <= pz_ then
			nx, ny, nz, dist = 0, (ly >= 0) and 1 or -1, 0, -py_
			qy = ny * hy
		else
			nx, ny, nz, dist = 0, 0, (lz >= 0) and 1 or -1, -pz_
			qz = nz * hz
		end
	end
	return dist,
		r11 * nx + r12 * ny + r13 * nz, r21 * nx + r22 * ny + r23 * nz, r31 * nx + r32 * ny + r33 * nz,
		B.x + r11 * qx + r12 * qy + r13 * qz, B.y + r21 * qx + r22 * qy + r23 * qz, B.z + r31 * qx + r32 * qy + r33 * qz
end
collide.pointBox = pointBox

-- Half extent of box b along the unit world axis (lx, ly, lz).
local function extent(b, lx, ly, lz)
	return b.hx * abs(b.r11 * lx + b.r21 * ly + b.r31 * lz)
		+ b.hy * abs(b.r12 * lx + b.r22 * ly + b.r32 * lz)
		+ b.hz * abs(b.r13 * lx + b.r23 * ly + b.r33 * lz)
end

-- The pair's reference normal: of the six face axes of A and B, the one
-- along which they overlap least (separating-axis test), pointing from B
-- toward A. Corners that end up inside the other box use it, rather than
-- the nearest face of that box alone: identical kubbs side by side have
-- corners lying exactly on each other's side planes, and the nearest-face
-- rule then pushes sideways.
local refX, refY, refZ
local REF_COS = math.cos(math.rad(25)) -- a corner's own normal further off than this uses the reference
local AX = { "r11", "r12", "r13" }
local AY = { "r21", "r22", "r23" }
local AZ = { "r31", "r32", "r33" }
local function referenceAxis(A, B)
	local dx, dy, dz = A.x - B.x, A.y - B.y, A.z - B.z
	local best = math.huge
	for pass = 1, 2 do
		local b = (pass == 1) and A or B
		for k = 1, 3 do
			local lx, ly, lz = b[AX[k]], b[AY[k]], b[AZ[k]]
			local d = dx * lx + dy * ly + dz * lz
			local o = extent(A, lx, ly, lz) + extent(B, lx, ly, lz) - abs(d)
			if o < best then
				best = o
				if d < 0 then lx, ly, lz = -lx, -ly, -lz end
				refX, refY, refZ = lx, ly, lz
			end
		end
	end
end

-- Corners of box A against box B (contacts on A, normals out of B).
-- (sx, sy, sz) is the reference normal from B toward A.
local function cornersInto(A, B, margin, sx_, sy_, sz_)
	local hx, hy, hz = A.hx, A.hy, A.hz
	local ax, ay, az = A.r11 * hx, A.r21 * hx, A.r31 * hx
	local bx, by, bz = A.r12 * hy, A.r22 * hy, A.r32 * hy
	local cx, cy, cz = A.r13 * hz, A.r23 * hz, A.r33 * hz
	-- skip corners clearly outside B's bounding sphere plus margin
	local reach = B.radius + margin
	local reach2 = reach * reach
	for k = 1, 8 do
		local sx, sy, sz = SX[k], SY[k], SZ[k]
		local px = A.x + sx * ax + sy * bx + sz * cx
		local py = A.y + sx * ay + sy * by + sz * cy
		local pz = A.z + sx * az + sy * bz + sz * cz
		local ddx, ddy, ddz = px - B.x, py - B.y, pz - B.z
		if ddx * ddx + ddy * ddy + ddz * ddz < reach2 then
			local d, nx, ny, nz = pointBox(B, px, py, pz)
			if d >= margin then
				-- no contact: a far corner can still lie on the reference
				-- plane (the back foot of a box leaning on another)
				d = margin
			elseif d <= 0 or nx * sx_ + ny * sy_ + nz * sz_ < REF_COS then
				-- inside, or near an edge of B: use the reference normal and
				-- the distance to B's face plane along it (never more than
				-- the true distance, so still a close contact)
				local plane = B.x * sx_ + B.y * sy_ + B.z * sz_ + extent(B, sx_, sy_, sz_)
				local dp = px * sx_ + py * sy_ + pz * sz_ - plane
				if d <= 0 and dp > 0 then dp = 0 end
				d = dp
				nx, ny, nz = sx_, sy_, sz_
			end
			if d < margin then add(A, B, px, py, pz, nx, ny, nz, d, 0) end
		end
	end
end

function collide.boxBox(A, B, margin)
	referenceAxis(A, B)
	local nx, ny, nz = refX, refY, refZ
	cornersInto(A, B, margin, nx, ny, nz)
	cornersInto(B, A, margin, -nx, -ny, -nz)
end

-- Sphere (center c, radius r) belonging to capsule A against box B.
local function sphereBox(A, B, cx, cy, cz, r, margin)
	local d, nx, ny, nz = pointBox(B, cx, cy, cz)
	local sep = d - r
	if sep < margin then
		add(A, B, cx - nx * r, cy - ny * r, cz - nz * r, nx, ny, nz, sep, 0)
		return true
	end
	return false
end

-- Capsule A against box B.
function collide.capsuleBox(A, B, margin)
	local hl, r = A.hl, A.r
	local ax, ay, az = A.r13 * hl, A.r23 * hl, A.r33 * hl
	local x1, y1, z1 = A.x - ax, A.y - ay, A.z - az
	local x2, y2, z2 = A.x + ax, A.y + ay, A.z + az
	-- the segment in B's local frame
	local r11, r12, r13, r21, r22, r23, r31, r32, r33 =
		B.r11, B.r12, B.r13, B.r21, B.r22, B.r23, B.r31, B.r32, B.r33
	local dx, dy, dz = x1 - B.x, y1 - B.y, z1 - B.z
	local p1x = r11 * dx + r21 * dy + r31 * dz
	local p1y = r12 * dx + r22 * dy + r32 * dz
	local p1z = r13 * dx + r23 * dy + r33 * dz
	dx, dy, dz = x2 - B.x, y2 - B.y, z2 - B.z
	local ux = r11 * dx + r21 * dy + r31 * dz - p1x
	local uy = r12 * dx + r22 * dy + r32 * dz - p1y
	local uz = r13 * dx + r23 * dy + r33 * dz - p1z
	local uu = ux * ux + uy * uy + uz * uz
	local hx, hy, hz = B.hx, B.hy, B.hz
	-- closest points by alternating projection (segment <-> box), starting
	-- from the segment point nearest the box center
	local t = -(p1x * ux + p1y * uy + p1z * uz) / uu
	if t < 0 then t = 0 elseif t > 1 then t = 1 end
	for _ = 1, 6 do
		local sx, sy, sz = p1x + ux * t, p1y + uy * t, p1z + uz * t
		local qx = sx > hx and hx or (sx < -hx and -hx or sx)
		local qy = sy > hy and hy or (sy < -hy and -hy or sy)
		local qz = sz > hz and hz or (sz < -hz and -hz or sz)
		local nt = ((qx - p1x) * ux + (qy - p1y) * uy + (qz - p1z) * uz) / uu
		if nt < 0 then nt = 0 elseif nt > 1 then nt = 1 end
		if abs(nt - t) < 1e-4 then t = nt break end
		t = nt
	end
	local found = false
	-- the closest pair
	local cx, cy, cz = x1 + 2 * ax * t, y1 + 2 * ay * t, z1 + 2 * az * t
	found = sphereBox(A, B, cx, cy, cz, r, margin)
	-- the end spheres, when they are not the closest point already
	if t > 0.2 then
		if sphereBox(A, B, x1, y1, z1, r, margin) then found = true end
	end
	if t < 0.8 then
		if sphereBox(A, B, x2, y2, z2, r, margin) then found = true end
	end
	return found
end

-- Capsule A against capsule B: closest points of two segments (Ericson,
-- Real-Time Collision Detection 5.1.9).
function collide.capsuleCapsule(A, B, margin)
	local ax, ay, az = A.r13 * A.hl, A.r23 * A.hl, A.r33 * A.hl
	local bx, by, bz = B.r13 * B.hl, B.r23 * B.hl, B.r33 * B.hl
	local p1x, p1y, p1z = A.x - ax, A.y - ay, A.z - az
	local p2x, p2y, p2z = B.x - bx, B.y - by, B.z - bz
	local d1x, d1y, d1z = 2 * ax, 2 * ay, 2 * az
	local d2x, d2y, d2z = 2 * bx, 2 * by, 2 * bz
	local rx, ry, rz = p1x - p2x, p1y - p2y, p1z - p2z
	local a = d1x * d1x + d1y * d1y + d1z * d1z
	local e = d2x * d2x + d2y * d2y + d2z * d2z
	local f = d2x * rx + d2y * ry + d2z * rz
	local c = d1x * rx + d1y * ry + d1z * rz
	local b = d1x * d2x + d1y * d2y + d1z * d2z
	local den = a * e - b * b
	local s = 0
	if den > 1e-12 then
		s = (b * f - c * e) / den
		if s < 0 then s = 0 elseif s > 1 then s = 1 end
	end
	local t = (b * s + f) / e
	if t < 0 then
		t = 0
		s = -c / a
		if s < 0 then s = 0 elseif s > 1 then s = 1 end
	elseif t > 1 then
		t = 1
		s = (b - c) / a
		if s < 0 then s = 0 elseif s > 1 then s = 1 end
	end
	local cax, cay, caz = p1x + d1x * s, p1y + d1y * s, p1z + d1z * s
	local cbx, cby, cbz = p2x + d2x * t, p2y + d2y * t, p2z + d2z * t
	local nx, ny, nz = cax - cbx, cay - cby, caz - cbz
	local d = sqrt(nx * nx + ny * ny + nz * nz)
	if d < 1e-9 then
		nx, ny, nz, d = 0, 0, 1, 0
	else
		nx, ny, nz = nx / d, ny / d, nz / d
	end
	local sep = d - A.r - B.r
	if sep < margin then
		add(A, B, cax - nx * A.r, cay - ny * A.r, caz - nz * A.r, nx, ny, nz, sep, 0)
		return true
	end
	return false
end

tw.collide = collide
