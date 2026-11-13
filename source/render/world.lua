-- Draws the pitch, kubbs, king and baton through a core camera.
-- The pitch is not dithered (Jamie, 2026-11-13; DESIGN 3): white ground,
-- black lines, a dashed centerline and six stakes, a light pattern only
-- outside the sidelines, white above the horizon. Pieces are true-size 3D
-- boxes: black outline, white top, one dark side face, solid black shadow.
-- Painter's order: shadows first (they lie on the ground), then pieces far
-- to near by depth along the view axis.
import "CoreLibs/graphics"
import "core/tw"
import "core/camera"

local gfx <const> = playdate.graphics
local camera = tw.camera
local project, projectPoly, projectSegment = camera.project, camera.projectPoly, camera.projectSegment
local unpack, floor, max, min, sqrt = table.unpack, math.floor, math.max, math.min, math.sqrt

tw.render = tw.render or {}
local world = {}

world.tune = {
	shadowX = 0.55,   -- ground shadow offset per meter of height: light from the far left,
	shadowY = -0.30,  -- so shadows fall right and toward the thrower, beside the piece
	stakeHeight = 0.30,
	stakeWidth = 2,   -- px
	dash = 0.20,      -- m, centerline dash and gap
	-- The light pattern outside the sidelines: sparse black dots (pattern
	-- bits: 1 = white, 0 = black). It covers the ground beside the pitch from
	-- behind the thrower to the far baseline; beyond the far baseline the
	-- ground stays white so the far base kubbs stand against white.
	outsidePattern = { 0x7F, 0xFF, 0xF7, 0xFF, 0x7F, 0xFF, 0xF7, 0xFF },
	outsideFrom = -20,  -- m (y) where the patterned strips start, behind the thrower
	outsideTo = 8,      -- m (y) where they end: the far baseline
	-- The dark side face of a piece (the face toward the thrower, in shade).
	darkPattern = { 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55 },
	batonMinPx = 2,
}

local KUBB_W, KUBB_H, KING_W, KING_H = 0.07, 0.15, 0.09, 0.30
local BATON_L, BATON_D = 0.30, 0.044

-- The pieces standing in stage 1: 5 base kubbs on each baseline and the king.
world.pieces = {}
for _, y in ipairs { 0, 8 } do
	for x = -2, 2 do
		world.pieces[#world.pieces + 1] = { x = x, y = y, w = KUBB_W, h = KUBB_H }
	end
end
world.pieces[#world.pieces + 1] = { x = 0, y = 4, w = KING_W, h = KING_H, king = true }

-- Live targets for the aim camera's framing rule: the far base kubbs.
world.targets = {}
for _, p in ipairs(world.pieces) do
	if p.y == 8 then world.targets[#world.targets + 1] = p end
end

-- scratch, reused every frame
local poly = {}
local PX, PY, PZ = {}, {}, {}
local SX, SY = {}, {}
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

local SIGN = { -1, 1 }
local function boxShadow(c, p)
	local t = world.tune
	local hw = p.w / 2
	local ox, oy = t.shadowX * p.h, t.shadowY * p.h
	local i = 0
	for a = 1, 2 do
		for b = 1, 2 do
			local x, y = p.x + SIGN[a] * hw, p.y + SIGN[b] * hw
			i = i + 1
			PX[i], PY[i] = x, y
			i = i + 1
			PX[i], PY[i] = x + ox, y + oy
		end
	end
	local n = hull(i)
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

-- Corner k of a box: bottom 1-4, top 5-8, counter-clockwise from (-,-).
local CX = { -1, 1, 1, -1 }
local CY = { -1, -1, 1, 1 }

local function face(a, b, cc, d, fill)
	if fill == "dark" then
		gfx.setPattern(world.tune.darkPattern)
	else
		gfx.setColor(fill == "black" and gfx.kColorBlack or gfx.kColorWhite)
	end
	gfx.fillPolygon(SX[a], SY[a], SX[b], SY[b], SX[cc], SY[cc], SX[d], SY[d])
	gfx.setColor(gfx.kColorBlack)
	gfx.drawPolygon(SX[a], SY[a], SX[b], SY[b], SX[cc], SY[cc], SX[d], SY[d])
end

local function drawBox(c, p)
	local hw = p.w / 2
	for k = 1, 4 do
		local x, y = p.x + CX[k] * hw, p.y + CY[k] * hw
		local sx, sy = project(c, x, y, 0)
		if not sx then return end
		SX[k], SY[k] = sx, sy
		sx, sy = project(c, x, y, p.h)
		if not sx then return end
		SX[k + 4], SY[k + 4] = sx, sy
	end
	gfx.setLineWidth(1)
	-- side faces facing the camera: -y (front, in shade), +x (in shade), -x, +y
	if c.py < p.y - hw then face(1, 2, 6, 5, "dark") end
	if c.px > p.x + hw then face(2, 3, 7, 6, "black") end
	if c.px < p.x - hw then face(4, 1, 5, 8, "white") end
	if c.py > p.y + hw then face(3, 4, 8, 7, "white") end
	if c.pz > p.h then face(5, 6, 7, 8, "white") end
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

-- Draw everything. `baton` is nil or {x, y, z, ax, ay, az} (center and unit axis).
function world.draw(c, baton)
	gfx.clear(gfx.kColorWhite)
	drawPitch(c)
	local pieces = world.pieces
	gfx.setColor(gfx.kColorBlack)
	for i = 1, #pieces do boxShadow(c, pieces[i]) end
	if baton then batonShadow(c, baton) end
	-- far to near
	local n = #pieces
	for i = 1, n do
		local p = pieces[i]
		local _, _, d = camera.toView(c, p.x, p.y, 0)
		order[i], depth[i] = i, d
	end
	if baton then
		n = n + 1
		local _, _, d = camera.toView(c, baton.x, baton.y, baton.z)
		order[n], depth[n] = 0, d
	end
	for i = 2, n do
		local v, dv, j = order[i], depth[i], i - 1
		while j >= 1 and depth[j] < dv do
			order[j + 1], depth[j + 1] = order[j], depth[j]
			j = j - 1
		end
		order[j + 1], depth[j + 1] = v, dv
	end
	for i = 1, n do
		local k = order[i]
		if depth[i] > camera.tune.near then
			if k == 0 then drawBaton(c, baton) else drawBox(c, pieces[k]) end
		end
	end
	gfx.setColor(gfx.kColorBlack)
	gfx.setLineWidth(1)
	gfx.setLineCapStyle(gfx.kLineCapStyleButt)
end

tw.render.world = world
