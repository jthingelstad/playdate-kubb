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
--
-- Speed (AGENTS.md, "Drawing speed"): on the device a Lua call costs about
-- 9 us and a graphics call 20 to 50 us, so
-- - a frame that shows exactly what the previous one showed (same camera,
--   no pose changed, same baton) is a copy of a cached image of the world;
-- - each item keeps what depends only on its pose (world corners, the
--   shadow outline on the ground, face normals and shading), recomputed
--   only after world.setPose;
-- - projection is written out with the camera in locals, pieces wholly off
--   screen are skipped and colour changes that change nothing are skipped.
-- The pixels are the same as drawing everything from scratch.
import "CoreLibs/graphics"
import "core/tw"
import "core/camera"
import "core/quat"
import "core/body"

local gfx <const> = playdate.graphics
local camera = tw.camera
local toMatrix = tw.quat.toMatrix
local project, projectSegment = camera.project, camera.projectSegment
local unpack, floor, max, min, sqrt = table.unpack, math.floor, math.max, math.min, math.sqrt
local fillPolygon, drawPolygon, drawLine = gfx.fillPolygon, gfx.drawPolygon, gfx.drawLine
local setColor, setPattern, setLineWidth = gfx.setColor, gfx.setPattern, gfx.setLineWidth
local BLACK <const>, WHITE <const> = gfx.kColorBlack, gfx.kColorWhite

tw.render = tw.render or {}
local world = {}

world.tune = {
	shadowX = 0.55,   -- ground shadow offset per meter of height: light from the far left,
	shadowY = -0.30,  -- so shadows fall right and toward the thrower, beside the piece
	stakeHeight = 0.30, -- keep equal to tw.world.tune.stakeHeight (the physics post)
	stakeWidth = 2,   -- px
	dash = 0.20,      -- m, centerline dash and gap
	advDash = 0.10,   -- m, the advantage line's dash and gap (2 px wide, so it reads apart
	                  -- from the 1 px centerline)
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
	-- the king's carving, as fractions of its height and half-width
	kingCrown = 0.11, -- depth of the crown's cuts
	kingWaist = 0.55, -- where the bevel into the neck starts
	kingNeck = 0.66,  -- the top of the neck, under the head's shoulder
	kingInset = 0.3,  -- how far the neck is cut in
	cache = true,     -- reuse the last frame's world image when nothing changed
}

local BATON_L, BATON_D = 0.30, 0.044

-- Bumped by every world.setPose: part of the frame cache key.
local poseVersion = 0

-- The advantage line's y (the view frame), or nil for none. Set by the
-- scene; part of the frame cache key.
world.advantageY = nil

-- Pieces are drawn from an item list the scene keeps: one item per kubb or
-- king with a full pose. world.setPose fills the rotation matrix. Item
-- fields other than the pose are the renderer's caches; change a pose only
-- through world.setPose.
-- A "baton" item is a baton lying on the pitch (a match's debris): drawn
-- like the flying baton, from its pose (ax, ay, az = its long axis).
function world.item(id, kind)
	local k = tw.body.kinds[kind]
	local baton = (kind == "baton")
	return {
		id = id, kind = kind, king = (kind == "king"), baton = baton,
		hx = k.hx or k.r, hy = k.hy or k.r, hz = k.hz or k.length / 2,
		ax = 0, ay = 0, az = 1,
		x = 0, y = 0, z = k.hz, qw = 1, qx = 0, qy = 0, qz = 0,
		r11 = 1, r12 = 0, r13 = 0, r21 = 0, r22 = 1, r23 = 0, r31 = 0, r32 = 0, r33 = 1,
		toppled = false,
		stale = true,
	}
end

function world.setPose(it, x, y, z, qw, qx, qy, qz)
	it.x, it.y, it.z, it.qw, it.qx, it.qy, it.qz = x, y, z, qw, qx, qy, qz
	it.r11, it.r12, it.r13, it.r21, it.r22, it.r23, it.r31, it.r32, it.r33 = toMatrix(qw, qx, qy, qz)
	if it.baton then it.ax, it.ay, it.az = it.r13, it.r23, it.r33 end
	it.stale = true
	poseVersion = poseVersion + 1
end

-- The pose version: changes whenever any item's pose does (the HUD's
-- minimap caches on it).
function world.poseVersion() return poseVersion end

-- Drop the cached world image and every item's prepared shadow and shading
-- (after changing world.tune, say). Items compare their own generation with
-- this one, so no item list is needed here.
local cacheReady = false
local generation = 0
function world.invalidate()
	cacheReady = false
	generation = generation + 1
	poseVersion = poseVersion + 1
end

-- scratch, reused every frame
local poly = {}
local PX, PY = {}, {}
local SX, SY = {}, {}
local order, depth = {}, {}

-- Optional profiling (the device autobench): world.prof = { clock = fn }
-- and draw adds the seconds of each part into it.
world.prof = nil
local RP, rt = nil, 0
local function lap(name)
	if RP then
		local now = RP.clock()
		RP[name] = (RP[name] or 0) + now - rt
		rt = now
	end
end

-- The camera of the frame being drawn, in locals.
local CPX, CPY, CPZ, CFX, CFY, CFZ, CRX, CRY, CRZ, CUX, CUY, CUZ = 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 1
local CF, CCX, CCY, NEAR = 900, 200, 120, 0.05

-- camera.projectPoly for ground points (z = 0) xs/ys[1..n] into poly, with
-- the same arithmetic. Returns the number of screen points.
local vx, vy, vd = {}, {}, {}
local function projectGround(n, xs, ys)
	for i = 1, n do
		local dx, dy, dz = xs[i] - CPX, ys[i] - CPY, 0 - CPZ
		vx[i] = dx * CRX + dy * CRY + dz * CRZ
		vy[i] = dx * CUX + dy * CUY + dz * CUZ
		vd[i] = dx * CFX + dy * CFY + dz * CFZ
	end
	local m = 0
	local f, cx, cy, near = CF, CCX, CCY, NEAR
	for i = 1, n do
		local j = (i % n) + 1
		local ai, aj = vd[i] >= near, vd[j] >= near
		if ai then
			m = m + 1
			poly[2 * m - 1] = cx + f * vx[i] / vd[i]
			poly[2 * m] = cy - f * vy[i] / vd[i]
		end
		if ai ~= aj then
			local t = (near - vd[i]) / (vd[j] - vd[i])
			m = m + 1
			poly[2 * m - 1] = cx + f * (vx[i] + (vx[j] - vx[i]) * t) / near
			poly[2 * m] = cy - f * (vy[i] + (vy[j] - vy[i]) * t) / near
		end
	end
	return m
end

local function fillPoly(n)
	if n >= 3 then fillPolygon(unpack(poly, 1, 2 * n)) end
end

local function groundQuad(x0, y0, x1, y1)
	PX[1], PY[1] = x0, y0
	PX[2], PY[2] = x1, y0
	PX[3], PY[3] = x1, y1
	PX[4], PY[4] = x0, y1
	return projectGround(4, PX, PY)
end

-- camera.projectSegment written out, then drawLine.
local function line(x1, y1, z1, x2, y2, z2)
	local dx, dy, dz = x1 - CPX, y1 - CPY, z1 - CPZ
	local ax = dx * CRX + dy * CRY + dz * CRZ
	local ay = dx * CUX + dy * CUY + dz * CUZ
	local ad = dx * CFX + dy * CFY + dz * CFZ
	dx, dy, dz = x2 - CPX, y2 - CPY, z2 - CPZ
	local bx = dx * CRX + dy * CRY + dz * CRZ
	local by = dx * CUX + dy * CUY + dz * CUZ
	local bd = dx * CFX + dy * CFY + dz * CFZ
	local near = NEAR
	if ad < near and bd < near then return end
	if ad < near then
		local t = (near - ad) / (bd - ad)
		ax, ay, ad = ax + (bx - ax) * t, ay + (by - ay) * t, near
	elseif bd < near then
		local t = (near - bd) / (ad - bd)
		bx, by, bd = bx + (ax - bx) * t, by + (ay - by) * t, near
	end
	local f = CF
	drawLine(CCX + f * ax / ad, CCY - f * ay / ad, CCX + f * bx / bd, CCY - f * by / bd)
end

local function drawPitch()
	local t = world.tune
	-- outside the sidelines: a light pattern out to a far horizon line
	setPattern(t.outsidePattern)
	fillPoly(groundQuad(-60, t.outsideFrom, -2.5, t.outsideTo))
	fillPoly(groundQuad(2.5, t.outsideFrom, 60, t.outsideTo))
	lap("outside")
	setColor(BLACK)
	setLineWidth(1)
	line(-2.5, 0, 0, -2.5, 8, 0)
	line(2.5, 0, 0, 2.5, 8, 0)
	line(-2.5, 0, 0, 2.5, 0, 0)
	line(-2.5, 8, 0, 2.5, 8, 0)
	local dash = t.dash
	local x = -2.5
	while x < 2.5 do
		local x2 = x + dash
		if x2 > 2.5 then x2 = 2.5 end
		line(x, 4, 0, x2, 4, 0)
		x = x + 2 * dash
	end
	-- the advantage line (the match, II.B.6): a dotted 2 px line across the pitch
	local ay = world.advantageY
	if ay then
		setLineWidth(2)
		local ad = t.advDash
		x = -2.5
		while x < 2.5 do
			local x2 = x + ad
			if x2 > 2.5 then x2 = 2.5 end
			line(x, ay, 0, x2, ay, 0)
			x = x + 2 * ad
		end
	end
	setLineWidth(t.stakeWidth)
	local sh = t.stakeHeight
	for i = 0, 2 do
		local y = 4 * i
		line(-2.5, y, 0, -2.5, y, sh)
		line(2.5, y, 0, 2.5, y, sh)
	end
	setLineWidth(1)
	lap("lines")
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

-- What an item's pose alone decides: the 8 world corners (corner
-- k = 1 + (sx > 0) + 2 (sy > 0) + 4 (sz > 0) for local signs sx, sy, sz),
-- the shadow's outline on the ground, and per face the outward normal, the
-- face center and the shading (1 white, 2 pattern, 3 black).
local function prepare(p)
	local WX, WY, WZ = p.WX, p.WY, p.WZ
	if not WX then
		WX, WY, WZ = {}, {}, {}
		p.WX, p.WY, p.WZ = WX, WY, WZ
		p.HX, p.HY, p.FN = {}, {}, {}
	end
	local x, y, z, hx, hy, hz = p.x, p.y, p.z, p.hx, p.hy, p.hz
	local r11, r12, r13, r21, r22, r23, r31, r32, r33 =
		p.r11, p.r12, p.r13, p.r21, p.r22, p.r23, p.r31, p.r32, p.r33
	local ex1, ey1, ez1 = r11 * hx, r21 * hx, r31 * hx
	local ex2, ey2, ez2 = r12 * hy, r22 * hy, r32 * hy
	local ex3, ey3, ez3 = r13 * hz, r23 * hz, r33 * hz
	local k = 0
	for c3 = -1, 1, 2 do
		for c2 = -1, 1, 2 do
			for c1 = -1, 1, 2 do
				k = k + 1
				WX[k] = x + c1 * ex1 + c2 * ex2 + c3 * ex3
				WY[k] = y + c1 * ey1 + c2 * ey2 + c3 * ey3
				WZ[k] = z + c1 * ez1 + c2 * ez2 + c3 * ez3
			end
		end
	end
	-- the shadow: the corners cast along the light onto the ground, and
	-- their convex hull
	local t = world.tune
	local shx, shy = t.shadowX, t.shadowY
	for i = 1, 8 do
		local zz = WZ[i]
		if not (zz > 0) then zz = 0 end
		PX[i], PY[i] = WX[i] + shx * zz, WY[i] + shy * zz
	end
	local n = hull(8)
	local PHX, PHY = p.HX, p.HY
	for j = 1, n do PHX[j], PHY[j] = HX[j], HY[j] end
	p.hn = n
	-- faces
	local FN = p.FN
	local litAbove, darkAbove = t.litAbove, t.darkAbove
	for f = 1, 6 do
		local F = FACES[f]
		local axis, sgn = F[5], F[6]
		local nx, ny, nz, h
		if axis == 1 then nx, ny, nz, h = r11, r21, r31, hx
		elseif axis == 2 then nx, ny, nz, h = r12, r22, r32, hy
		else nx, ny, nz, h = r13, r23, r33, hz end
		nx, ny, nz = nx * sgn, ny * sgn, nz * sgn
		local o = 7 * f - 7
		FN[o + 1], FN[o + 2], FN[o + 3] = nx, ny, nz
		FN[o + 4], FN[o + 5], FN[o + 6] = x + nx * h, y + ny * h, z + nz * h
		local lit = nx * LX + ny * LY + nz * LZ
		FN[o + 7] = (lit > litAbove) and 1 or ((lit > darkAbove) and 2 or 3)
	end
	p.stale = false
	p.gen = generation
end

local function boxShadow(p)
	fillPoly(projectGround(p.hn, p.HX, p.HY))
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
	setLineWidth(w)
	drawLine(a, bb, cc, d)
	gfx.setLineCapStyle(gfx.kLineCapStyleButt)
	setLineWidth(1)
end

-- The king is the same box to the physics, but it is drawn carved, like a
-- real one: a body, a waist cut in above it (a bevel up to a narrower neck,
-- with a square shoulder under the head), and a head whose top is a crown
-- of low teeth (two V cuts in each side, down to a floor inside).
--
-- Every extra point lies on one of the box's four vertical edges, a
-- fraction u of the way up and pulled a fraction s toward the axis. On
-- entry SX/SY[1..8] hold the projected corners; the rings above bottom
-- corners 1..4 go to 9..12 (A: top of the body), 13..16 (B: the neck),
-- 17..20 (C: under the head) and 21..24 (D: the crown's floor).
local function shadeOn(shade)
	if shade == 1 then setColor(WHITE)
	elseif shade == 2 then setPattern(world.tune.darkPattern)
	else setColor(BLACK) end
end

-- One side of a section between two rings (bases L and H into SX/SY).
local function kingSide(L, H, a, b, shade)
	shadeOn(shade)
	fillPolygon(SX[L + a], SY[L + a], SX[L + b], SY[L + b], SX[H + b], SY[H + b], SX[H + a], SY[H + a])
	setColor(BLACK)
	drawPolygon(SX[L + a], SY[L + a], SX[L + b], SY[L + b], SX[H + b], SY[H + b], SX[H + a], SY[H + a])
end

-- A cap: the ring at base L, in the order of face F.
local function kingCap(L, F, shade)
	local a, b, c, d = L + F[1], L + F[2], L + F[3], L + F[4]
	shadeOn(shade)
	fillPolygon(SX[a], SY[a], SX[b], SY[b], SX[c], SY[c], SX[d], SY[d])
	setColor(BLACK)
	drawPolygon(SX[a], SY[a], SX[b], SY[b], SX[c], SY[c], SX[d], SY[d])
end

-- One side of the head, with the crown's two cuts. inner: the far side,
-- whose inner wall shows through the near cuts.
local function kingHeadSide(a, b, shade, inner)
	local ax, ay, bx, by = SX[16 + a], SY[16 + a], SX[16 + b], SY[16 + b]       -- under the head
	local fax, fay, fbx, fby = SX[20 + a], SY[20 + a], SX[20 + b], SY[20 + b]   -- the crown's floor
	local tax, tay, tbx, tby = SX[4 + a], SY[4 + a], SX[4 + b], SY[4 + b]       -- the top corners
	local v1x, v1y = fax + (fbx - fax) * 0.25, fay + (fby - fay) * 0.25
	local v2x, v2y = fax + (fbx - fax) * 0.75, fay + (fby - fay) * 0.75
	local px, py = (tax + tbx) / 2, (tay + tby) / 2
	shadeOn(inner and 3 or shade)
	-- up to the floor, then the three teeth: a concave polygon is not safe
	-- to fill in one piece
	fillPolygon(ax, ay, bx, by, fbx, fby, fax, fay)
	fillPolygon(fax, fay, v1x, v1y, tax, tay)
	fillPolygon(v1x, v1y, v2x, v2y, px, py)
	fillPolygon(v2x, v2y, fbx, fby, tbx, tby)
	setColor(BLACK)
	if not inner then
		drawPolygon(ax, ay, bx, by, tbx, tby, v2x, v2y, px, py, v1x, v1y, tax, tay)
	end
end

local KING_U, KING_S = {}, {}
local function drawKing(p, FN)
	local WX, WY, WZ = p.WX, p.WY, p.WZ
	local t = world.tune
	local f, cx, cy, near = CF, CCX, CCY, NEAR
	local cpx, cpy, cpz = CPX, CPY, CPZ
	KING_U[1], KING_S[1] = t.kingWaist, 0
	KING_U[2], KING_S[2] = t.kingNeck, t.kingInset
	KING_U[3], KING_S[3] = t.kingNeck, 0
	KING_U[4], KING_S[4] = 1 - t.kingCrown, 0
	-- the axis: from the middle of the bottom to the middle of the top
	local bx = (WX[1] + WX[2] + WX[3] + WX[4]) / 4
	local by = (WY[1] + WY[2] + WY[3] + WY[4]) / 4
	local bz = (WZ[1] + WZ[2] + WZ[3] + WZ[4]) / 4
	local ux, uy, uz = 2 * (p.x - bx), 2 * (p.y - by), 2 * (p.z - bz)
	for row = 1, 4 do
		local u, s = KING_U[row], KING_S[row]
		local mx, my, mz = bx + ux * u, by + uy * u, bz + uz * u
		for k = 1, 4 do
			local wx = WX[k] + (WX[k + 4] - WX[k]) * u
			local wy = WY[k] + (WY[k + 4] - WY[k]) * u
			local wz = WZ[k] + (WZ[k + 4] - WZ[k]) * u
			local dx, dy, dz = wx + (mx - wx) * s - cpx, wy + (my - wy) * s - cpy, wz + (mz - wz) * s - cpz
			local d = dx * CFX + dy * CFY + dz * CFZ
			if d < near then return end
			local sc = f / d
			SX[4 + 4 * row + k] = cx + sc * (dx * CRX + dy * CRY + dz * CRZ)
			SY[4 + 4 * row + k] = cy - sc * (dx * CUX + dy * CUY + dz * CUZ)
		end
	end
	-- which sides face the camera, and which end of the king it looks at
	local s1, s2, s3, s4
	for fi = 1, 4 do
		local o = 7 * fi - 7
		local front = (cpx - FN[o + 4]) * FN[o + 1] + (cpy - FN[o + 5]) * FN[o + 2] + (cpz - FN[o + 6]) * FN[o + 3] > 0
		if fi == 1 then s1 = front elseif fi == 2 then s2 = front elseif fi == 3 then s3 = front else s4 = front end
	end
	local above = (cpx - p.x) * ux + (cpy - p.y) * uy + (cpz - p.z) * uz > 0
	local topShade, bottomShade = FN[42], FN[35]
	-- the three sections, the far one first
	for step = 1, 3 do
		local sec = above and step or (4 - step)
		if sec == 3 then
			-- the head: from below its underside shows, from above the far
			-- sides' inner walls and the crown's floor
			if above then
				for fi = 1, 4 do
					local F = FACES[fi]
					local front = (fi == 1 and s1) or (fi == 2 and s2) or (fi == 3 and s3) or (fi == 4 and s4)
					if not front then kingHeadSide(F[1], F[2], 3, true) end
				end
				local F = FACES[5]
				shadeOn(topShade)
				fillPolygon(SX[20 + F[1]], SY[20 + F[1]], SX[20 + F[2]], SY[20 + F[2]],
					SX[20 + F[3]], SY[20 + F[3]], SX[20 + F[4]], SY[20 + F[4]])
				setColor(BLACK)
			else
				kingCap(16, FACES[5], bottomShade)
			end
			for fi = 1, 4 do
				local F = FACES[fi]
				local front = (fi == 1 and s1) or (fi == 2 and s2) or (fi == 3 and s3) or (fi == 4 and s4)
				if front then kingHeadSide(F[1], F[2], FN[7 * fi], false) end
			end
		else
			local L, H = 0, 8
			if sec == 2 then L, H = 8, 12 end
			if sec == 1 and not above then kingCap(0, FACES[5], bottomShade) end
			for fi = 1, 4 do
				local F = FACES[fi]
				local front = (fi == 1 and s1) or (fi == 2 and s2) or (fi == 3 and s3) or (fi == 4 and s4)
				if front then kingSide(L, H, F[1], F[2], FN[7 * fi]) end
			end
		end
	end
end

-- Draw one box (line width 1 and colour black on entry and exit).
local function drawBox(p)
	local WX, WY, WZ = p.WX, p.WY, p.WZ
	local f, cx, cy, near = CF, CCX, CCY, NEAR
	local x0, x1, y0, y1 = 1e9, -1e9, 1e9, -1e9
	for k = 1, 8 do
		-- camera.project written out
		local dx, dy, dz = WX[k] - CPX, WY[k] - CPY, WZ[k] - CPZ
		local d = dx * CFX + dy * CFY + dz * CFZ
		if d < near then return end
		local s = f / d
		local sx = cx + s * (dx * CRX + dy * CRY + dz * CRZ)
		local sy = cy - s * (dx * CUX + dy * CUY + dz * CUZ)
		SX[k], SY[k] = sx, sy
		if sx < x0 then x0 = sx end
		if sx > x1 then x1 = sx end
		if sy < y0 then y0 = sy end
		if sy > y1 then y1 = sy end
	end
	-- wholly off screen: nothing to draw
	if x1 < -2 or x0 > 402 or y1 < -2 or y0 > 242 then return end
	local FN = p.FN
	local cpx, cpy, cpz = CPX, CPY, CPZ
	if p.king then return drawKing(p, FN) end
	for fi = 1, 6 do
		local o = 7 * fi - 7
		local nx, ny, nz = FN[o + 1], FN[o + 2], FN[o + 3]
		-- visible when the camera is in front of the face's plane
		if (cpx - FN[o + 4]) * nx + (cpy - FN[o + 5]) * ny + (cpz - FN[o + 6]) * nz > 0 then
			local F = FACES[fi]
			local a, b, cc, d = F[1], F[2], F[3], F[4]
			local shade = FN[o + 7]
			if shade == 1 then
				setColor(WHITE)
			elseif shade == 2 then
				setPattern(world.tune.darkPattern)
			end
			fillPolygon(SX[a], SY[a], SX[b], SY[b], SX[cc], SY[cc], SX[d], SY[d])
			if shade ~= 3 then setColor(BLACK) end
			drawPolygon(SX[a], SY[a], SX[b], SY[b], SX[cc], SY[cc], SX[d], SY[d])
		end
	end
end

local function drawBaton(c, b)
	local x1, y1, z1, x2, y2, z2 = batonEnds(b)
	local a, bb, cc, d = projectSegment(c, x1, y1, z1, x2, y2, z2)
	if not a then return end
	local _, _, dep = project(c, b.x, b.y, b.z)
	local w = dep and max(world.tune.batonMinPx, floor(BATON_D * c.f / dep + 0.5)) or 2
	setColor(BLACK)
	gfx.setLineCapStyle(gfx.kLineCapStyleRound)
	setLineWidth(w + 2)
	drawLine(a, bb, cc, d)
	setColor(WHITE)
	gfx.setLineCapStyle(gfx.kLineCapStyleButt)
	setLineWidth(w)
	drawLine(a, bb, cc, d)
	setColor(BLACK)
	setLineWidth(1)
end

local function drawAll(c, items, n, baton)
	gfx.clear(WHITE)
	lap("clear")
	drawPitch()
	setColor(BLACK)
	for i = 1, n do
		local p = items[i]
		if p.baton then batonShadow(c, p) else boxShadow(p) end
	end
	if baton then batonShadow(c, baton) end
	lap("shadows")
	-- far to near
	local m = n
	for i = 1, n do
		local p = items[i]
		-- camera.toView's depth
		local d = (p.x - CPX) * CFX + (p.y - CPY) * CFY + (p.z - CPZ) * CFZ
		order[i], depth[i] = i, d
	end
	if baton then
		m = m + 1
		local d = (baton.x - CPX) * CFX + (baton.y - CPY) * CFY + (baton.z - CPZ) * CFZ
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
	local near = NEAR
	for i = 1, m do
		local k = order[i]
		if depth[i] > near then
			if k == 0 then drawBaton(c, baton)
			else
				local p = items[k]
				if p.baton then drawBaton(c, p) else drawBox(p) end
			end
		end
	end
	setColor(BLACK)
	setLineWidth(1)
	gfx.setLineCapStyle(gfx.kLineCapStyleButt)
	lap("pieces")
end

-- The frame cache: the key of the last frame drawn (camera, items, poses,
-- baton, advantage line) and an image of the world for it.
local K = {}
local KEY = {}
local cacheImg = nil

-- Fill the key for this frame; true when it equals the last frame's.
local function sameKey(items, n, baton)
	local k = KEY
	k[1], k[2], k[3], k[4], k[5], k[6] = CPX, CPY, CPZ, CFX, CFY, CFZ
	k[7], k[8], k[9], k[10], k[11], k[12] = CRX, CRY, CRZ, CUX, CUY, CUZ
	k[13], k[14], k[15], k[16], k[17], k[18] = CF, CCX, CCY, items, n, poseVersion
	if baton then
		k[19], k[20], k[21], k[22], k[23], k[24] = baton.x, baton.y, baton.z, baton.ax, baton.ay, baton.az
	else
		k[19], k[20], k[21], k[22], k[23], k[24] = false, false, false, false, false, false
	end
	k[25] = world.advantageY or false
	local same = true
	for i = 1, 25 do
		local v = k[i]
		if K[i] ~= v then K[i] = v; same = false end
	end
	return same
end

-- Draw everything. `items` holds n items (world.item: boxes, and batons
-- lying on the pitch); `baton` is nil
-- or {x, y, z, ax, ay, az} (center and unit axis).
function world.draw(c, items, n, baton)
	RP = world.prof
	if RP then rt = RP.clock() end
	CPX, CPY, CPZ, CFX, CFY, CFZ = c.px, c.py, c.pz, c.fx, c.fy, c.fz
	CRX, CRY, CRZ, CUX, CUY, CUZ = c.rx, c.ry, c.rz, c.ux, c.uy, c.uz
	CF, CCX, CCY, NEAR = c.f, c.cx, c.cy, camera.tune.near
	updateLight()
	for i = 1, n do
		local p = items[i]
		-- a lying baton is drawn from its pose alone (nothing to prepare)
		if (p.stale ~= false or p.gen ~= generation) and not p.baton then prepare(p) end
	end
	lap("prepare")
	local cache = world.tune.cache
	local same = sameKey(items, n, baton)
	if cache and same and cacheReady then
		cacheImg:draw(0, 0)
		lap("cached")
		return
	end
	if cache and same then
		-- the second frame in a row with nothing changed: draw into the
		-- cache, then show it
		if not cacheImg then cacheImg = gfx.image.new(400, 240, WHITE) end
		gfx.pushContext(cacheImg)
		drawAll(c, items, n, baton)
		gfx.popContext()
		cacheImg:draw(0, 0)
		cacheReady = true
		lap("cached")
		return
	end
	cacheReady = false
	drawAll(c, items, n, baton)
end

tw.render.world = world
