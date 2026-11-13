-- Draws the pitch, kubbs, king and baton through a core camera.
-- The pitch is not dithered (Jamie, 2026-11-13; DESIGN 3): white ground,
-- black lines, a dashed centerline and six stakes, a light pattern only
-- outside the sidelines, white above the horizon. Pieces are true-size 3D
-- boxes in any orientation (standing, falling, lying): black outline, faces
-- shaded by how they face the light (lit white, half-lit patterned, away
-- black), and a solid black shadow cast along the light onto the ground.
-- The shadow of a lying piece touches its ground edge, so it reads as on
-- the ground (the contact shadow). Painter's order: shadows first (they lie
-- on the ground), then pieces far to near by depth along the view axis.
import "CoreLibs/graphics"
import "core/tw"
import "core/camera"
import "core/quat"
import "core/body"

local gfx <const> = playdate.graphics
local camera = tw.camera
local toMatrix = tw.quat.toMatrix
local project, projectPoly, projectSegment = camera.project, camera.projectPoly, camera.projectSegment
local unpack, floor, max, min, sqrt = table.unpack, math.floor, math.max, math.min, math.sqrt

tw.render = tw.render or {}
local world = {}

world.tune = {
	shadowX = 0.55,   -- ground shadow offset per meter of height: light from the far left,
	shadowY = -0.30,  -- so shadows fall right and toward the thrower, beside the piece
	stakeHeight = 0.30, -- keep equal to tw.world.tune.stakeHeight (the physics post)
	stakeWidth = 2,   -- px
	dash = 0.20,      -- m, centerline dash and gap
	-- The light pattern outside the sidelines: sparse black dots (pattern
	-- bits: 1 = white, 0 = black). It covers the ground beside the pitch from
	-- behind the thrower to the far baseline; beyond the far baseline the
	-- ground stays white so the far base kubbs stand against white.
	outsidePattern = { 0x7F, 0xFF, 0xF7, 0xFF, 0x7F, 0xFF, 0xF7, 0xFF },
	outsideFrom = -20,  -- m (y) where the patterned strips start, behind the thrower
	outsideTo = 8,      -- m (y) where they end: the far baseline
	-- A half-lit face of a piece (a standing kubb's face toward the thrower).
	darkPattern = { 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55 },
	-- Face shading by n.L (L toward the light, from shadowX/shadowY): above
	-- litAbove white, above darkAbove the dark pattern, else black. With the
	-- default light a standing kubb shows a white top, white -x and +y faces,
	-- a patterned -y face and a black +x face, as in stage 1.
	litAbove = 0.2,
	darkAbove = -0.35,
	batonMinPx = 2,
}

local BATON_L, BATON_D = 0.30, 0.044

-- Pieces are drawn from an item list the scene keeps: one item per kubb or
-- king with a full pose. world.setPose fills the rotation matrix.
function world.item(id, kind)
	local k = tw.body.kinds[kind]
	return {
		id = id, kind = kind, king = (kind == "king"),
		hx = k.hx, hy = k.hy, hz = k.hz,
		x = 0, y = 0, z = k.hz, qw = 1, qx = 0, qy = 0, qz = 0,
		r11 = 1, r12 = 0, r13 = 0, r21 = 0, r22 = 1, r23 = 0, r31 = 0, r32 = 0, r33 = 1,
		toppled = false,
	}
end

function world.setPose(it, x, y, z, qw, qx, qy, qz)
	it.x, it.y, it.z, it.qw, it.qx, it.qy, it.qz = x, y, z, qw, qx, qy, qz
	it.r11, it.r12, it.r13, it.r21, it.r22, it.r23, it.r31, it.r32, it.r33 = toMatrix(qw, qx, qy, qz)
end

-- scratch, reused every frame
local poly = {}
local PX, PY, PZ = {}, {}, {}
local SX, SY = {}, {}
local WX, WY, WZ = {}, {}, {}
local order, depth = {}, {}

local function fillPoly(n)
	if n >= 3 then gfx.fillPolygon(unpack(poly, 1, 2 * n)) end
end

local function groundQuad(c, x0, y0, x1, y1)
	PX[1], PY[1] = x0, y0
	PX[2], PY[2] = x1, y0
	PX[3], PY[3] = x1, y1
	PX[4], PY[4] = x0, y1
	return projectPoly(c, 4, PX, PY, nil, poly)
end

local function line(c, x1, y1, z1, x2, y2, z2)
	local a, b, cc, d = projectSegment(c, x1, y1, z1, x2, y2, z2)
	if a then gfx.drawLine(a, b, cc, d) end
end

local function drawPitch(c)
	local t = world.tune
	-- outside the sidelines: a light pattern out to a far horizon line
	gfx.setPattern(t.outsidePattern)
	fillPoly(groundQuad(c, -60, t.outsideFrom, -2.5, t.outsideTo))
	fillPoly(groundQuad(c, 2.5, t.outsideFrom, 60, t.outsideTo))
	gfx.setColor(gfx.kColorBlack)
	gfx.setLineWidth(1)
	line(c, -2.5, 0, 0, -2.5, 8, 0)
	line(c, 2.5, 0, 0, 2.5, 8, 0)
	line(c, -2.5, 0, 0, 2.5, 0, 0)
	line(c, -2.5, 8, 0, 2.5, 8, 0)
	local x = -2.5
	while x < 2.5 do
		line(c, x, 4, 0, min(2.5, x + t.dash), 4, 0)
		x = x + 2 * t.dash
	end
	gfx.setLineWidth(t.stakeWidth)
	for i = 0, 2 do
		local y = 4 * i
		line(c, -2.5, y, 0, -2.5, y, t.stakeHeight)
		line(c, 2.5, y, 0, 2.5, y, t.stakeHeight)
	end
	gfx.setLineWidth(1)
end

-- 2D convex hull (monotone chain) of PX/PY[1..n] into HX/HY; returns the
-- count. No closures or tables, so no garbage.
local HX, HY, IDX = {}, {}, {}
local function hull(n)
	for i = 1, n do IDX[i] = i end
	for i = 2, n do -- insertion sort by x then y
		local v, j = IDX[i], i - 1
		while j >= 1 and (PX[IDX[j]] > PX[v] or (PX[IDX[j]] == PX[v] and PY[IDX[j]] > PY[v])) do
			IDX[j + 1] = IDX[j]
			j = j - 1
		end
		IDX[j + 1] = v
	end
	local k = 0
	for pass = 1, 2 do
		local start = k
		for s = 1, n do
			local i = (pass == 1) and IDX[s] or IDX[n + 1 - s]
			local px, py = PX[i], PY[i]
			while k >= start + 2 and
				(HX[k] - HX[k - 1]) * (py - HY[k - 1]) - (HY[k] - HY[k - 1]) * (px - HX[k - 1]) <= 0 do
				k = k - 1
			end
			k = k + 1
			HX[k], HY[k] = px, py
		end
		k = k - 1
	end
	return k
end

-- The 8 corners of a box item in world space into WX/WY/WZ. Corner
-- k = 1 + (sx > 0) + 2 (sy > 0) + 4 (sz > 0) for local signs sx, sy, sz.
local function corners(p)
	local ex1, ey1, ez1 = p.r11 * p.hx, p.r21 * p.hx, p.r31 * p.hx
	local ex2, ey2, ez2 = p.r12 * p.hy, p.r22 * p.hy, p.r32 * p.hy
	local ex3, ey3, ez3 = p.r13 * p.hz, p.r23 * p.hz, p.r33 * p.hz
	local k = 0
	for c3 = -1, 1, 2 do
		for c2 = -1, 1, 2 do
			for c1 = -1, 1, 2 do
				k = k + 1
				WX[k] = p.x + c1 * ex1 + c2 * ex2 + c3 * ex3
				WY[k] = p.y + c1 * ey1 + c2 * ey2 + c3 * ey3
				WZ[k] = p.z + c1 * ez1 + c2 * ez2 + c3 * ez3
			end
		end
	end
end

local function boxShadow(c, p)
	local t = world.tune
	corners(p)
	for i = 1, 8 do
		local z = max(0, WZ[i])
		PX[i], PY[i] = WX[i] + t.shadowX * z, WY[i] + t.shadowY * z
	end
	local n = hull(8)
	for j = 1, n do PX[j], PY[j] = HX[j], HY[j] end
	fillPoly(projectPoly(c, n, PX, PY, nil, poly))
end

local function batonEnds(b)
	local hl = BATON_L / 2
	return b.x - b.ax * hl, b.y - b.ay * hl, b.z - b.az * hl,
		b.x + b.ax * hl, b.y + b.ay * hl, b.z + b.az * hl
end

local function batonShadow(c, b)
	local t = world.tune
	local x1, y1, z1, x2, y2, z2 = batonEnds(b)
	-- cast from the top of the baton, so a baton lying on the ground still
	-- shows a sliver of shadow
	local r = BATON_D / 2
	z1, z2 = max(0, z1) + r, max(0, z2) + r
	local a, bb, cc, d = projectSegment(c, x1 + t.shadowX * z1, y1 + t.shadowY * z1, 0,
		x2 + t.shadowX * z2, y2 + t.shadowY * z2, 0)
	if not a then return end
	local _, _, dep = project(c, b.x, b.y, 0)
	local w = dep and max(2, floor(BATON_D * c.f / dep + 0.5)) or 2
	gfx.setLineCapStyle(gfx.kLineCapStyleRound)
	gfx.setLineWidth(w)
	gfx.drawLine(a, bb, cc, d)
end

-- The six faces: four corner indices in order around the face, and the
-- local axis (1 x, 2 y, 3 z) and sign of the outward normal.
local FACES = {
	{ 1, 3, 7, 5, 1, -1 }, { 2, 4, 8, 6, 1, 1 },
	{ 1, 2, 6, 5, 2, -1 }, { 3, 4, 8, 7, 2, 1 },
	{ 1, 2, 4, 3, 3, -1 }, { 5, 6, 8, 7, 3, 1 },
}

local LX, LY, LZ = 0, 0, 1
local function updateLight()
	local t = world.tune
	local lx, ly, lz = -t.shadowX, -t.shadowY, 1
	local n = sqrt(lx * lx + ly * ly + lz * lz)
	LX, LY, LZ = lx / n, ly / n, lz / n
end

local function drawBox(c, p)
	corners(p)
	for k = 1, 8 do
		local sx, sy = project(c, WX[k], WY[k], WZ[k])
		if not sx then return end
		SX[k], SY[k] = sx, sy
	end
	local t = world.tune
	gfx.setLineWidth(1)
	local cpx, cpy, cpz = c.px, c.py, c.pz
	for f = 1, 6 do
		local F = FACES[f]
		local axis, sgn = F[5], F[6]
		local nx, ny, nz, h
		if axis == 1 then nx, ny, nz, h = p.r11, p.r21, p.r31, p.hx
		elseif axis == 2 then nx, ny, nz, h = p.r12, p.r22, p.r32, p.hy
		else nx, ny, nz, h = p.r13, p.r23, p.r33, p.hz end
		nx, ny, nz = nx * sgn, ny * sgn, nz * sgn
		-- visible when the camera is in front of the face's plane
		local fx, fy, fz = p.x + nx * h, p.y + ny * h, p.z + nz * h
		if (cpx - fx) * nx + (cpy - fy) * ny + (cpz - fz) * nz > 0 then
			local a, b, cc, d = F[1], F[2], F[3], F[4]
			local lit = nx * LX + ny * LY + nz * LZ
			if lit > t.litAbove then
				gfx.setColor(gfx.kColorWhite)
			elseif lit > t.darkAbove then
				gfx.setPattern(t.darkPattern)
			else
				gfx.setColor(gfx.kColorBlack)
			end
			gfx.fillPolygon(SX[a], SY[a], SX[b], SY[b], SX[cc], SY[cc], SX[d], SY[d])
			gfx.setColor(gfx.kColorBlack)
			gfx.drawPolygon(SX[a], SY[a], SX[b], SY[b], SX[cc], SY[cc], SX[d], SY[d])
		end
	end
end

local function drawBaton(c, b)
	local x1, y1, z1, x2, y2, z2 = batonEnds(b)
	local a, bb, cc, d = projectSegment(c, x1, y1, z1, x2, y2, z2)
	if not a then return end
	local _, _, dep = project(c, b.x, b.y, b.z)
	local w = dep and max(world.tune.batonMinPx, floor(BATON_D * c.f / dep + 0.5)) or 2
	gfx.setColor(gfx.kColorBlack)
	gfx.setLineCapStyle(gfx.kLineCapStyleRound)
	gfx.setLineWidth(w + 2)
	gfx.drawLine(a, bb, cc, d)
	gfx.setColor(gfx.kColorWhite)
	gfx.setLineCapStyle(gfx.kLineCapStyleButt)
	gfx.setLineWidth(w)
	gfx.drawLine(a, bb, cc, d)
	gfx.setColor(gfx.kColorBlack)
	gfx.setLineWidth(1)
end

-- Draw everything. `items` holds n box items (world.item); `baton` is nil
-- or {x, y, z, ax, ay, az} (center and unit axis).
function world.draw(c, items, n, baton)
	gfx.clear(gfx.kColorWhite)
	drawPitch(c)
	updateLight()
	gfx.setColor(gfx.kColorBlack)
	for i = 1, n do boxShadow(c, items[i]) end
	if baton then batonShadow(c, baton) end
	-- far to near
	local m = n
	for i = 1, n do
		local p = items[i]
		local _, _, d = camera.toView(c, p.x, p.y, p.z)
		order[i], depth[i] = i, d
	end
	if baton then
		m = m + 1
		local _, _, d = camera.toView(c, baton.x, baton.y, baton.z)
		order[m], depth[m] = 0, d
	end
	for i = 2, m do
		local v, dv, j = order[i], depth[i], i - 1
		while j >= 1 and depth[j] < dv do
			order[j + 1], depth[j + 1] = order[j], depth[j]
			j = j - 1
		end
		order[j + 1], depth[j + 1] = v, dv
	end
	for i = 1, m do
		local k = order[i]
		if depth[i] > camera.tune.near then
			if k == 0 then drawBaton(c, baton) else drawBox(c, items[k]) end
		end
	end
	gfx.setColor(gfx.kColorBlack)
	gfx.setLineWidth(1)
	gfx.setLineCapStyle(gfx.kLineCapStyleButt)
end

tw.render.world = world
