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

-- The functions below run for every pair and corner of every step, so they
-- write out add, pointBox, the extents and math.abs instead of calling them
-- (on the device a Lua call costs about 9 us, a C call about 4 us; see
-- AGENTS.md, "Physics"). The arithmetic is the same, term for term.

-- Box b against the ground plane z = 0: each corner below `margin`.
function collide.groundBox(b, margin)
	local hx, hy, hz = b.hx, b.hy, b.hz
	local r31, r32, r33 = b.r31, b.r32, b.r33
	local z0 = b.z
	local x0, y0 = b.x, b.y
	local az, bz, cz = r31 * hx, r32 * hy, r33 * hz
	-- quick reject: the lowest corner is above the margin
	local aaz, abz, acz = az, bz, cz
	if aaz < 0 then aaz = -aaz end
	if abz < 0 then abz = -abz end
	if acz < 0 then acz = -acz end
	if z0 - (aaz + abz + acz) >= margin then return end
	local ax, ay = b.r11 * hx, b.r21 * hx
	local bx, by = b.r12 * hy, b.r22 * hy
	local cx, cy = b.r13 * hz, b.r23 * hz
	local i = C.n
	for k = 1, 8 do
		local sx, sy, sz = SX[k], SY[k], SZ[k]
		local pz = z0 + sx * az + sy * bz + sz * cz
		if pz < margin then
			i = i + 1
			cA[i], cB[i], cSlot[i] = b, false, k
			cPx[i], cPy[i], cPz[i] = x0 + sx * ax + sy * bx + sz * cx, y0 + sx * ay + sy * by + sz * cy, pz
			cNx[i], cNy[i], cNz[i] = 0, 0, 1
			cSep[i] = pz
		end
	end
	C.n = i
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
-- (Written out again in cornersInto and sphereBox.)
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
collide.extent = extent

-- The pair's reference normal: of the six face axes of A and B, the one
-- along which they overlap least (separating-axis test), pointing from B
-- toward A. Corners that end up inside the other box use it, rather than
-- the nearest face of that box alone: identical kubbs side by side have
-- corners lying exactly on each other's side planes, and the nearest-face
-- rule then pushes sideways.
local refX, refY, refZ
local REF_COS = math.cos(math.rad(25)) -- a corner's own normal further off than this uses the reference
-- Returns the least overlap (negative = the gap along that axis).
local function referenceAxis(A, B)
	local dx, dy, dz = A.x - B.x, A.y - B.y, A.z - B.z
	local a11, a12, a13, a21, a22, a23, a31, a32, a33 =
		A.r11, A.r12, A.r13, A.r21, A.r22, A.r23, A.r31, A.r32, A.r33
	local b11, b12, b13, b21, b22, b23, b31, b32, b33 =
		B.r11, B.r12, B.r13, B.r21, B.r22, B.r23, B.r31, B.r32, B.r33
	local ahx, ahy, ahz, bhx, bhy, bhz = A.hx, A.hy, A.hz, B.hx, B.hy, B.hz
	local best = math.huge
	for k = 1, 6 do
		local lx, ly, lz
		if k == 1 then lx, ly, lz = a11, a21, a31
		elseif k == 2 then lx, ly, lz = a12, a22, a32
		elseif k == 3 then lx, ly, lz = a13, a23, a33
		elseif k == 4 then lx, ly, lz = b11, b21, b31
		elseif k == 5 then lx, ly, lz = b12, b22, b32
		else lx, ly, lz = b13, b23, b33 end
		local d = dx * lx + dy * ly + dz * lz
		local e1 = a11 * lx + a21 * ly + a31 * lz
		local e2 = a12 * lx + a22 * ly + a32 * lz
		local e3 = a13 * lx + a23 * ly + a33 * lz
		if e1 < 0 then e1 = -e1 end
		if e2 < 0 then e2 = -e2 end
		if e3 < 0 then e3 = -e3 end
		local f1 = b11 * lx + b21 * ly + b31 * lz
		local f2 = b12 * lx + b22 * ly + b32 * lz
		local f3 = b13 * lx + b23 * ly + b33 * lz
		if f1 < 0 then f1 = -f1 end
		if f2 < 0 then f2 = -f2 end
		if f3 < 0 then f3 = -f3 end
		local ad = d
		if ad < 0 then ad = -ad end
		local o = (ahx * e1 + ahy * e2 + ahz * e3) + (bhx * f1 + bhy * f2 + bhz * f3) - ad
		if o < best then
			best = o
			if d < 0 then lx, ly, lz = -lx, -ly, -lz end
			refX, refY, refZ = lx, ly, lz
		end
	end
	return best
end

-- Corners of box A against box B (contacts on A, normals out of B).
-- (sx, sy, sz) is the reference normal from B toward A.
local function cornersInto(A, B, margin, sx_, sy_, sz_)
	local hx, hy, hz = A.hx, A.hy, A.hz
	local ax, ay, az = A.r11 * hx, A.r21 * hx, A.r31 * hx
	local bx, by, bz = A.r12 * hy, A.r22 * hy, A.r32 * hy
	local cx, cy, cz = A.r13 * hz, A.r23 * hz, A.r33 * hz
	local Ax, Ay, Az = A.x, A.y, A.z
	local Bx, By, Bz = B.x, B.y, B.z
	-- skip corners clearly outside B's bounding sphere plus margin
	local reach = B.radius + margin
	local reach2 = reach * reach
	local r11, r12, r13, r21, r22, r23, r31, r32, r33
	local Bhx, Bhy, Bhz
	local plane
	local i = C.n
	for k = 1, 8 do
		local sx, sy, sz = SX[k], SY[k], SZ[k]
		local px = Ax + sx * ax + sy * bx + sz * cx
		local py = Ay + sx * ay + sy * by + sz * cy
		local pz = Az + sx * az + sy * bz + sz * cz
		local ddx, ddy, ddz = px - Bx, py - By, pz - Bz
		if ddx * ddx + ddy * ddy + ddz * ddz < reach2 then
			if not r11 then
				r11, r12, r13, r21, r22, r23, r31, r32, r33 =
					B.r11, B.r12, B.r13, B.r21, B.r22, B.r23, B.r31, B.r32, B.r33
				Bhx, Bhy, Bhz = B.hx, B.hy, B.hz
			end
			-- pointBox(B, p), written out
			local lx = r11 * ddx + r21 * ddy + r31 * ddz
			local ly = r12 * ddx + r22 * ddy + r32 * ddz
			local lz = r13 * ddx + r23 * ddy + r33 * ddz
			local qx = lx > Bhx and Bhx or (lx < -Bhx and -Bhx or lx)
			local qy = ly > Bhy and Bhy or (ly < -Bhy and -Bhy or ly)
			local qz = lz > Bhz and Bhz or (lz < -Bhz and -Bhz or lz)
			local ex, ey, ez = lx - qx, ly - qy, lz - qz
			local d2 = ex * ex + ey * ey + ez * ez
			local lnx, lny, lnz, d
			if d2 > 1e-14 then
				d = sqrt(d2)
				lnx, lny, lnz = ex / d, ey / d, ez / d
			else
				-- inside: the face of least penetration
				local alx, aly, alz = lx, ly, lz
				if alx < 0 then alx = -alx end
				if aly < 0 then aly = -aly end
				if alz < 0 then alz = -alz end
				local px_, py_, pz_ = Bhx - alx, Bhy - aly, Bhz - alz
				if px_ <= py_ and px_ <= pz_ then
					lnx, lny, lnz, d = (lx >= 0) and 1 or -1, 0, 0, -px_
				elseif py_ <= pz_ then
					lnx, lny, lnz, d = 0, (ly >= 0) and 1 or -1, 0, -py_
				else
					lnx, lny, lnz, d = 0, 0, (lz >= 0) and 1 or -1, -pz_
				end
			end
			-- (a corner at margin or further adds nothing; a far corner can
			-- still lie on the reference plane, the back foot of a box leaning
			-- on another, but its distance is then margin too)
			if d < margin then
				local nx = r11 * lnx + r12 * lny + r13 * lnz
				local ny = r21 * lnx + r22 * lny + r23 * lnz
				local nz = r31 * lnx + r32 * lny + r33 * lnz
				if d <= 0 or nx * sx_ + ny * sy_ + nz * sz_ < REF_COS then
					-- inside, or near an edge of B: use the reference normal and
					-- the distance to B's face plane along it (never more than
					-- the true distance, so still a close contact)
					if not plane then
						local e1 = r11 * sx_ + r21 * sy_ + r31 * sz_
						local e2 = r12 * sx_ + r22 * sy_ + r32 * sz_
						local e3 = r13 * sx_ + r23 * sy_ + r33 * sz_
						if e1 < 0 then e1 = -e1 end
						if e2 < 0 then e2 = -e2 end
						if e3 < 0 then e3 = -e3 end
						plane = Bx * sx_ + By * sy_ + Bz * sz_ + (Bhx * e1 + Bhy * e2 + Bhz * e3)
					end
					local dp = px * sx_ + py * sy_ + pz * sz_ - plane
					if d <= 0 and dp > 0 then dp = 0 end
					d = dp
					nx, ny, nz = sx_, sy_, sz_
				end
				if d < margin then
					i = i + 1
					cA[i], cB[i], cSlot[i] = A, B, 0
					cPx[i], cPy[i], cPz[i] = px, py, pz
					cNx[i], cNy[i], cNz[i] = nx, ny, nz
					cSep[i] = d
				end
			end
		end
	end
	C.n = i
end

function collide.boxBox(A, B, margin)
	-- separated along a face axis by margin or more: no corner of either box
	-- can come within margin of the other (every corner's distance is at
	-- least that gap), so there is nothing to add
	if referenceAxis(A, B) <= -margin then return end
	local nx, ny, nz = refX, refY, refZ
	cornersInto(A, B, margin, nx, ny, nz)
	cornersInto(B, A, margin, -nx, -ny, -nz)
end

-- How a baton meets a kubb or the king: the box's edges and corners rounded
-- to this radius (m). The box is met as one of half sides less this, swept
-- by a ball of this radius, so a baton that catches an edge gets a normal
-- between the two faces instead of the top face's straight up (Tyler's play
-- test, 2026-11-15: a baton clipping a kubb's top edge pressed it down
-- instead of tipping it, and seemed to pass through it). Wood is never a
-- knife edge; boxes still meet the ground and each other square.
collide.tune = {
	batonRound = 0.01,
}
local ROUND = collide.tune

-- Sphere (center c, radius r) belonging to capsule A against box B
-- (pointBox written out), B's edges rounded by ROUND.batonRound (not for a
-- stake). The contact point is on the sphere, as before.
local function sphereBox(A, B, cx, cy, cz, r, margin)
	local Bx, By, Bz = B.x, B.y, B.z
	local dx, dy, dz = cx - Bx, cy - By, cz - Bz
	local r11, r12, r13, r21, r22, r23, r31, r32, r33 =
		B.r11, B.r12, B.r13, B.r21, B.r22, B.r23, B.r31, B.r32, B.r33
	local lx = r11 * dx + r21 * dy + r31 * dz
	local ly = r12 * dx + r22 * dy + r32 * dz
	local lz = r13 * dx + r23 * dy + r33 * dz
	-- (a stake is a capsule too: it meets boxes square, so a wall of drilled
	-- kubbs against it is as measured)
	local br = ROUND.batonRound
	if A.static then br = 0 end
	local hx, hy, hz = B.hx - br, B.hy - br, B.hz - br
	local qx = lx > hx and hx or (lx < -hx and -hx or lx)
	local qy = ly > hy and hy or (ly < -hy and -hy or ly)
	local qz = lz > hz and hz or (lz < -hz and -hz or lz)
	local ex, ey, ez = lx - qx, ly - qy, lz - qz
	local d2 = ex * ex + ey * ey + ez * ez
	local lnx, lny, lnz, d
	if d2 > 1e-14 then
		d = sqrt(d2)
		lnx, lny, lnz = ex / d, ey / d, ez / d
	else
		local alx, aly, alz = lx, ly, lz
		if alx < 0 then alx = -alx end
		if aly < 0 then aly = -aly end
		if alz < 0 then alz = -alz end
		local px_, py_, pz_ = hx - alx, hy - aly, hz - alz
		if px_ <= py_ and px_ <= pz_ then
			lnx, lny, lnz, d = (lx >= 0) and 1 or -1, 0, 0, -px_
		elseif py_ <= pz_ then
			lnx, lny, lnz, d = 0, (ly >= 0) and 1 or -1, 0, -py_
		else
			lnx, lny, lnz, d = 0, 0, (lz >= 0) and 1 or -1, -pz_
		end
	end
	local sep = d - r - br
	if sep < margin then
		local nx = r11 * lnx + r12 * lny + r13 * lnz
		local ny = r21 * lnx + r22 * lny + r23 * lnz
		local nz = r31 * lnx + r32 * lny + r33 * lnz
		local i = C.n + 1
		C.n = i
		cA[i], cB[i], cSlot[i] = A, B, 0
		cPx[i], cPy[i], cPz[i] = cx - nx * r, cy - ny * r, cz - nz * r
		cNx[i], cNy[i], cNz[i] = nx, ny, nz
		cSep[i] = sep
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
		local dt_ = nt - t
		if dt_ < 1e-4 and dt_ > -1e-4 then t = nt break end
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
