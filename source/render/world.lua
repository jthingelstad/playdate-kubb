-- Draws the pitch, kubbs, king and baton through a core camera.
-- The pitch is not dithered (Jamie, 2026-11-13; DESIGN 3, "Woodcut"): white
-- ground, 2 px black lines, a dashed centerline (and advantage line), six
-- stakes with shadows, a sparse rough outside the sidelines and past the far
-- baseline, white above the horizon. Pieces are true-size
-- 3D boxes in any orientation (standing, falling, lying): black outline,
-- faces white, black when facing away from the light (the same look
-- standing, falling or lying), with wood grain and a king's collar and crown
-- up close; and a solid
-- black shadow cast along the light onto the ground.
-- The shadow of a lying piece touches its ground edge, so it reads as on
-- the ground (the contact shadow). Painter's order: shadows first (they lie
-- on the ground), then pieces far to near by depth along the view axis.
--
-- Speed (docs/notes/performance.md, "Drawing speed"): on the device a Lua call costs about
-- 9 us and a graphics call 20 to 50 us, so
-- - a frame that shows exactly what the previous one showed (same camera,
--   no pose changed, same baton) is a copy of a cached image of the world;
-- - each item keeps what depends only on its pose (world corners, the
--   shadow outline on the ground, face normals and shading), recomputed
--   only after world.setPose;
-- - projection is written out with the camera in locals, pieces wholly off
--   screen are skipped and colour changes that change nothing are skipped;
-- - while the camera holds still and only some pieces move (a throw after
--   it lands), the still pieces are drawn once into a background image and
--   each frame is that image plus the moving pieces (and any still piece
--   that overlaps them, so the depth order holds).
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
local unpack, floor, max, sqrt = table.unpack, math.floor, math.max, math.sqrt
local fillPolygon, drawPolygon, drawLine = gfx.fillPolygon, gfx.drawPolygon, gfx.drawLine
local setColor, setPattern, setLineWidth = gfx.setColor, gfx.setPattern, gfx.setLineWidth
local BLACK <const>, WHITE <const> = gfx.kColorBlack, gfx.kColorWhite

tw.render = tw.render or {}
local world = {}

world.tune = {
	shadowX = 0.55,   -- ground shadow offset per meter of height: light from the far left,
	shadowY = -0.30,  -- so shadows fall right and toward the thrower, beside the piece
	stakeHeight = 0.15, -- keep equal to tw.world.tune.stakeHeight (the physics post)
	stakeThick = 0.019, -- m, 3/4 inch (keep equal to 2 x tw.pitch.stakeRadius)
	stakeMinPx = 3,   -- px, the thinnest a stake is drawn, however far off
	lineWidth = 2,    -- px, the pitch's lines (docs/design "Lines")
	dash = 0.24,      -- m, the centerline's dash and gap: 6 on 4 off
	dashGap = 0.16,
	advDash = 0.10,   -- m, the advantage line's dash and gap: 2 on 2 off
	kidLineWidth = 1, -- px, the Kid line (a Kid match): thin and solid
	-- The rough outside the sidelines and past the far baseline: 2 x 1
	-- dashes on an 8 px grid (pattern bits: 1 = white, 0 = black), never on
	-- the pitch. Its phase follows the ground (see drawPitch).
	roughPattern = { 0xFF, 0x9F, 0xFF, 0xFF, 0xFF, 0xF9, 0xFF, 0xFF },
	-- each surface's rough (world.setSurface sets roughPattern from these):
	-- grass the short dashes above, sand a denser stipple, snow a sparse
	-- sprinkle on white
	roughBySurface = {
		grass = { 0xFF, 0x9F, 0xFF, 0xFF, 0xFF, 0xF9, 0xFF, 0xFF },
		sand = { 0xFF, 0xDF, 0xFF, 0xFB, 0xFF, 0x7F, 0xFF, 0xF7 },
		snow = { 0xFF, 0xFF, 0xFF, 0xEF, 0xFF, 0xFF, 0xFF, 0xFF },
	},
	rough = true,       -- false leaves the rough white (the autobench measures it)
	outsideFrom = -20,  -- m (y) where the strips beside the pitch start, behind the thrower
	roughFar = 200,     -- m (y) how far past the far baseline the rough goes (the horizon)
	-- Tones (docs/design "Tones"): a face is white unless it faces away from
	-- the light (n.L at or below awayBelow, L toward the light from
	-- shadowX/shadowY), then black. With the default light a standing kubb
	-- shows a white top and white front, left and back faces and a black
	-- right face. Pieces are never grey: a kubb or the king looks the same
	-- standing, falling and lying (Jamie, 2026-11-13).
	awayBelow = -0.35,
	thickFrom = 14,   -- px tall: outlines 2 px from here, 1 px below
	grainFrom = 17,   -- px tall: one grain line on the front face from here,
	grain2From = 30,  -- and two from here
	batonMinPx = 2,
	batonBand = 0.12, -- a flying baton's two black bands: each this fraction of
	batonBandAt = 0.1, -- its length, starting this fraction in from each end
	batonBandsFrom = 10, -- px long: bands from here
	-- the king's drawing, as fractions of its height
	kingCrown = 0.11,  -- depth of the crown's cuts
	kingCollar = 0.66, -- the black collar under the head: from here
	kingCollarTop = 0.73, -- to here
	kingRing = 0.6,    -- the thin ring
	kingDiamond = 0.47, -- the diamond's center, and its half-height
	kingDiamondH = 0.07,
	kingDetailFrom = 30, -- px tall: the ring and the diamond from here (the
	                     -- far king keeps the crown points and the collar)
	cache = true,     -- reuse the last frame's world image when nothing changed
	layer = true,     -- keep the pieces that hold still in a background image while the camera does
}

local BATON_L, BATON_D = 0.30, 0.044

-- Bumped by every world.setPose: part of the frame cache key.
local poseVersion = 0

-- The advantage line's y (the view frame), or nil for none. Set by the
-- scene; part of the frame cache key.
world.advantageY = nil
-- A Kid match's Kid line (engine 0.15; the view frame), or nil: drawn as a thin
-- solid line, so it reads apart from the advantage line's dashes and the
-- centerline's. Set by the scene; part of the frame cache key.
world.kidY = nil

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
	-- the same pose again changes nothing (and keeps the caches)
	if it.pv and x == it.x and y == it.y and z == it.z and qw == it.qw and qx == it.qx and qy == it.qy
		and qz == it.qz then return end
	it.x, it.y, it.z, it.qw, it.qx, it.qy, it.qz = x, y, z, qw, qx, qy, qz
	it.r11, it.r12, it.r13, it.r21, it.r22, it.r23, it.r31, it.r32, it.r33 = toMatrix(qw, qx, qy, qz)
	if it.baton then it.ax, it.ay, it.az = it.r13, it.r23, it.r33 end
	it.stale = true
	poseVersion = poseVersion + 1
	it.pv = poseVersion
end

-- The pose version: changes whenever any item's pose does (the HUD's
-- minimap caches on it).
function world.poseVersion() return poseVersion end

-- Drop the cached world image and every item's prepared shadow and shading
-- (after changing world.tune, say). Items compare their own generation with
-- this one, so no item list is needed here.
local cacheReady = false
local layerReady = false
local generation = 0
-- The ground's look for a surface (core/world's name: grass, sand, snow).
-- Changes the rough and drops the caches only when it is a different one.
function world.setSurface(name)
	local p = world.tune.roughBySurface[name]
	if p and world.tune.roughPattern ~= p then
		world.tune.roughPattern = p
		world.invalidate()
	end
end

-- One look (Jamie's Settings sheet, 2026-11-20: kubb sets are for the web
-- and the iPhone; "We exclude Playdate here becaue the black & white display
-- and size of display makes this irrelevnat, plus the CPU cannot handle
-- it."): bare wood, the classic set. The painted sets were here from
-- 2026-11-14 to 2026-11-20 (docs/notes/match.md "Kubb sets").

-- Seen from the pitch's other end (1.1.0, the Playdate's turn against the Playdate:
-- scenes/throw s.turned): the pieces and the camera stay in the thrower's view frame,
-- the camera at the far end looking back. The ground's white runs on behind the
-- near baseline (y = 8 here) and the rough lies past y = 0, and the light comes from
-- the viewer's far left as always, so the shadows turn too (shadowX, shadowY).
-- Only when it changes, then the caches are dropped.
world.turned = false
function world.setTurned(on)
	on = on and true or false
	if world.turned == on then return end
	world.turned = on
	local t = world.tune
	t.shadowX, t.shadowY = -t.shadowX, -t.shadowY
	world.invalidate()
end

function world.invalidate()
	cacheReady = false
	layerReady = false
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

-- One ground point (z = 0) to the screen, or nil when it is behind the near
-- plane.
local function projectPoint(x, y)
	local dx, dy, dz = x - CPX, y - CPY, -CPZ
	local d = dx * CFX + dy * CFY + dz * CFZ
	if d < NEAR then return nil end
	return CCX + CF * (dx * CRX + dy * CRY + dz * CRZ) / d, CCY - CF * (dx * CUX + dy * CUY + dz * CUZ) / d
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

-- The rough (docs/design "Tones"): 2 x 1 dashes on an 8 px grid, outside the
-- sidelines and past the far baseline. A Playdate pattern is anchored to
-- the screen, so a moving camera would slide the ground under a pattern that
-- stays put (it swims). The pattern is instead shifted to the pixel phase of
-- one point on the ground (the far baseline's middle) as projected this
-- frame, so it travels with the pitch. The 64 shifted patterns are made
-- once. The same camera gives the same phase, so the cached frame and the
-- background layer see the pixels a full redraw would.
local ROUGH = {}
local function makeRough()
	local base = world.tune.roughPattern
	for dy = 0, 7 do
		for dx = 0, 7 do
			local p = {}
			for r = 1, 8 do
				local b = base[((r - 1 - dy) % 8) + 1]
				p[r] = ((b >> dx) | (b << (8 - dx))) & 0xFF
			end
			ROUGH[dy * 8 + dx + 1] = p
		end
	end
	ROUGH.base = base
end

-- A dashed ground line from (x0, y) to (x1, y): `on` m drawn, `off` m gap.
local function dashes(x0, x1, y, on, off)
	local x = x0
	while x < x1 do
		local x2 = x + on
		if x2 > x1 then x2 = x1 end
		line(x, y, 0, x2, y, 0)
		x = x2 + off
	end
end

local function drawPitch()
	local t = world.tune
	if ROUGH.base ~= t.roughPattern then makeRough() end
	-- turned (world.setTurned): the pitch is seen from its other end, so the far
	-- baseline is y = 0 and the near ground runs on past y = 8
	local turned = world.turned
	-- the rough's phase: the far baseline's middle, projected
	local phase = 1
	do
		local dx, dy, dz = -CPX, (turned and 0 or 8) - CPY, -CPZ
		local d = dx * CFX + dy * CFY + dz * CFZ
		if d > NEAR then
			local s = CF / d
			local sx = floor(CCX + s * (dx * CRX + dy * CRY + dz * CRZ))
			local sy = floor(CCY - s * (dx * CUX + dy * CUY + dz * CUZ))
			phase = (sy % 8) * 8 + (sx % 8) + 1
		end
	end
	if t.rough then
		setPattern(ROUGH[phase])
		local far = t.roughFar
		-- All the ground short of the far edge is rough but the pitch's own
		-- footprint, so: fill the screen below the far edge (projected, a
		-- straight line, tilted when the camera turns), then the footprint
		-- white. Two fills that stay on the screen; three ground quads 120 m
		-- wide cost twice as much on the device. The old quads are the
		-- fallback if an end of the far edge is behind the camera. The far
		-- edge is `far` metres out along the camera's own heading on the
		-- ground, so it holds whichever way the camera looks (the impact
		-- camera's half circle looks back down the pitch); looking down the
		-- pitch from behind the baseline it is the old y = far within a metre.
		local hx, hy = CFX, CFY
		local hl = sqrt(hx * hx + hy * hy)
		local ax, ay, bx, by
		if hl > 0.01 then
			hx, hy = hx / hl, hy / hl
			local cx, cy = CPX + hx * far, CPY + hy * far
			ax, ay = projectPoint(cx + hy * 60, cy - hx * 60)
			bx, by = projectPoint(cx - hy * 60, cy + hx * 60)
			if ax and bx and bx < ax then ax, ay, bx, by = bx, by, ax, ay end
		end
		if ax and bx and bx - ax > 1 then
			local k = (by - ay) / (bx - ax)
			fillPolygon(-1, ay + (-1 - ax) * k, 401, ay + (401 - ax) * k, 401, 241, -1, 241)
			setColor(WHITE)
			if turned then fillPoly(groundQuad(-2.5, 0, 2.5, 8 - t.outsideFrom))
			else fillPoly(groundQuad(-2.5, t.outsideFrom, 2.5, 8)) end
		elseif turned then
			fillPoly(groundQuad(-60, 0, -2.5, 8 - t.outsideFrom))
			fillPoly(groundQuad(2.5, 0, 60, 8 - t.outsideFrom))
			fillPoly(groundQuad(-60, -far, 60, 0))
		else
			fillPoly(groundQuad(-60, t.outsideFrom, -2.5, 8))
			fillPoly(groundQuad(2.5, t.outsideFrom, 60, 8))
			fillPoly(groundQuad(-60, 8, 60, far))
		end
	end
	lap("outside")
	setColor(BLACK)
	setLineWidth(t.lineWidth)
	line(-2.5, 0, 0, -2.5, 8, 0)
	line(2.5, 0, 0, 2.5, 8, 0)
	line(-2.5, 0, 0, 2.5, 0, 0)
	line(-2.5, 8, 0, 2.5, 8, 0)
	-- the centerline: 6 on 4 off
	dashes(-2.5, 2.5, 4, t.dash, t.dashGap)
	-- the advantage line (the match, II.B.6): 2 on 2 off
	local ay = world.advantageY
	if ay then dashes(-2.5, 2.5, ay, t.advDash, t.advDash) end
	-- the Kid line (a Kid match): every kubb and every baton at a kubb is thrown from it
	local ky = world.kidY
	if ky then
		setLineWidth(t.kidLineWidth)
		line(-2.5, ky, 0, 2.5, ky, 0)
		setLineWidth(t.lineWidth)
	end
	-- the stakes (Jamie, 2026-11-14: a real pitch's wooden stakes, 3/4 inch thick
	-- and 6 inches out of the ground): solid posts their true width at their
	-- distance, never thinner than stakeMinPx, and no shadow (a shadow line at a
	-- corner read as the pitch's lines running on past it)
	local sh, thick, minPx = t.stakeHeight, t.stakeThick * CF, t.stakeMinPx
	for i = 0, 2 do
		local y = 4 * i
		for sx = -2.5, 2.5, 5 do
			local d = (sx - CPX) * CFX + (y - CPY) * CFY - CPZ * CFZ
			if d > NEAR then
				local w = thick / d
				if w < minPx then w = minPx end
				setLineWidth(floor(w + 0.5))
				line(sx, y, 0, sx, y, sh)
			end
		end
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
	local away = t.awayBelow
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
		FN[o + 7] = (lit <= away) and 3 or 1
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

-- The king is the same box to the physics, but it is drawn as a real one
-- (docs/design "Pieces"): a straight body and a head whose top is a crown of
-- four points (two V cuts in each side, down to a floor inside), a black
-- collar under the head and, at near sizes, a thin ring and one diamond.
--
-- Every extra point lies on one of the box's four vertical edges, a
-- fraction u of the way up. On entry SX/SY[1..8] hold the projected
-- corners; the rings above bottom corners 1..4 go to 9..12 (the ring),
-- 13..16 (the collar's foot), 17..20 (the collar's top, under the head) and
-- 21..24 (the crown's floor).
local function shadeOn(shade)
	if shade == 1 then setColor(WHITE) else setColor(BLACK) end
end

-- A cap: the ring at base L, in the order of face F.
local function kingCap(L, F, shade)
	local a, b, c, d = L + F[1], L + F[2], L + F[3], L + F[4]
	shadeOn(shade)
	fillPolygon(SX[a], SY[a], SX[b], SY[b], SX[c], SY[c], SX[d], SY[d])
	setColor(BLACK)
	drawPolygon(SX[a], SY[a], SX[b], SY[b], SX[c], SY[c], SX[d], SY[d])
end

-- One side of the king: the body up to the crown's floor and the crown's
-- two cuts. inner: the far side, whose inner wall shows through the near
-- cuts (only the crown part).
local function kingFace(a, b, shade, inner)
	local fax, fay, fbx, fby = SX[20 + a], SY[20 + a], SX[20 + b], SY[20 + b]   -- the crown's floor
	local tax, tay, tbx, tby = SX[4 + a], SY[4 + a], SX[4 + b], SY[4 + b]       -- the top corners
	local v1x, v1y = fax + (fbx - fax) * 0.25, fay + (fby - fay) * 0.25
	local v2x, v2y = fax + (fbx - fax) * 0.75, fay + (fby - fay) * 0.75
	local px, py = (tax + tbx) / 2, (tay + tby) / 2
	local ax, ay, bx, by = SX[a], SY[a], SX[b], SY[b]
	if inner then ax, ay, bx, by = SX[16 + a], SY[16 + a], SX[16 + b], SY[16 + b] end
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

local KING_U = {}
local function drawKing(p, FN, tall)
	local WX, WY, WZ = p.WX, p.WY, p.WZ
	local t = world.tune
	local f, cx, cy, near = CF, CCX, CCY, NEAR
	local cpx, cpy, cpz = CPX, CPY, CPZ
	KING_U[1], KING_U[2], KING_U[3], KING_U[4] = t.kingRing, t.kingCollar, t.kingCollarTop, 1 - t.kingCrown
	for row = 1, 4 do
		local u = KING_U[row]
		for k = 1, 4 do
			local dx = WX[k] + (WX[k + 4] - WX[k]) * u - cpx
			local dy = WY[k] + (WY[k + 4] - WY[k]) * u - cpy
			local dz = WZ[k] + (WZ[k + 4] - WZ[k]) * u - cpz
			local d = dx * CFX + dy * CFY + dz * CFZ
			if d < near then return end
			local sc = f / d
			SX[4 + 4 * row + k] = cx + sc * (dx * CRX + dy * CRY + dz * CRZ)
			SY[4 + 4 * row + k] = cy - sc * (dx * CUX + dy * CUY + dz * CUZ)
		end
	end
	-- which sides face the camera, and which end of the king it looks at
	local ux, uy, uz = WX[5] - WX[1], WY[5] - WY[1], WZ[5] - WZ[1]
	local above = (cpx - p.x) * ux + (cpy - p.y) * uy + (cpz - p.z) * uz > 0
	if above then
		-- the far sides' inner walls through the cuts, and the crown's floor
		for fi = 1, 4 do
			local o = 7 * fi - 7
			if (cpx - FN[o + 4]) * FN[o + 1] + (cpy - FN[o + 5]) * FN[o + 2] + (cpz - FN[o + 6]) * FN[o + 3] <= 0 then
				local F = FACES[fi]
				kingFace(F[1], F[2], 3, true)
			end
		end
		local F = FACES[5]
		shadeOn(FN[42])
		fillPolygon(SX[20 + F[1]], SY[20 + F[1]], SX[20 + F[2]], SY[20 + F[2]],
			SX[20 + F[3]], SY[20 + F[3]], SX[20 + F[4]], SY[20 + F[4]])
		setColor(BLACK)
	else
		kingCap(0, FACES[5], FN[35])
	end
	local detail = tall >= t.kingDetailFrom
	for fi = 1, 4 do
		local o = 7 * fi - 7
		if (cpx - FN[o + 4]) * FN[o + 1] + (cpy - FN[o + 5]) * FN[o + 2] + (cpz - FN[o + 6]) * FN[o + 3] > 0 then
			local F = FACES[fi]
			local a, b = F[1], F[2]
			local shade = FN[o + 7]
			kingFace(a, b, shade, false)
			if shade ~= 3 then
				-- the collar (black on a light face; a black face needs none)
				fillPolygon(SX[12 + a], SY[12 + a], SX[12 + b], SY[12 + b], SX[16 + b], SY[16 + b], SX[16 + a], SY[16 + a])
				if detail then
					drawLine(SX[8 + a], SY[8 + a], SX[8 + b], SY[8 + b])
					-- the diamond, in the middle of the face (screen-space
					-- interpolation: fine at these sizes)
					local u, h = t.kingDiamond, t.kingDiamondH
					local lx0, ly0, rx0, ry0 = SX[a], SY[a], SX[b], SY[b]
					local lx1, ly1, rx1, ry1 = SX[4 + a] - lx0, SY[4 + a] - ly0, SX[4 + b] - rx0, SY[4 + b] - ry0
					local mx = (lx0 + rx0 + (lx1 + rx1) * u) / 2
					local my = (ly0 + ry0 + (ly1 + ry1) * u) / 2
					local vx, vy = (lx1 + rx1) * h / 2, (ly1 + ry1) * h / 2
					local wx, wy = (rx0 - lx0) * 0.22, (ry0 - ly0) * 0.22
					fillPolygon(mx + vx, my + vy, mx + wx, my + wy, mx - vx, my - vy, mx - wx, my - wy)
				end
			end
		end
	end
end

-- Grain: one or two lines along the long axis of the front face (the white
-- side face that looks most at the camera), at 17 px and taller.
local function grain(p, FN, tall)
	local t = world.tune
	local best, bf = 0, nil
	local cpx, cpy, cpz = CPX, CPY, CPZ
	for fi = 1, 4 do
		local o = 7 * fi - 7
		if FN[o + 7] == 1 then
			local dx, dy, dz = cpx - FN[o + 4], cpy - FN[o + 5], cpz - FN[o + 6]
			local v = (dx * FN[o + 1] + dy * FN[o + 2] + dz * FN[o + 3]) / sqrt(dx * dx + dy * dy + dz * dz)
			if v > best then best, bf = v, fi end
		end
	end
	-- seen nearly edge-on, grain would only thicken the outline
	if not bf or best < 0.35 then return end
	local F = FACES[bf]
	local a, b, c, d = F[1], F[2], F[3], F[4]
	-- a and b at the foot, d above a and c above b
	local ax, ay, bx, by = SX[a], SY[a], SX[b], SY[b]
	local ux0, uy0, ux1, uy1 = SX[d] - ax, SY[d] - ay, SX[c] - bx, SY[c] - by
	local n = (tall >= t.grain2From) and 2 or 1
	for i = 1, n do
		-- across the face, and from and to up its length (the board's lines)
		local s, u0, u1 = 0.5, 0.18, 0.76
		if n == 2 then
			if i == 1 then s, u0, u1 = 0.3, 0.2, 0.83 else s, u0, u1 = 0.65, 0.09, 0.71 end
		end
		local x0, y0 = ax + (bx - ax) * s, ay + (by - ay) * s
		local vx, vy = ux0 + (ux1 - ux0) * s, uy0 + (uy1 - uy0) * s
		drawLine(x0 + vx * u0, y0 + vy * u0, x0 + vx * u1, y0 + vy * u1)
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
	local t = world.tune
	local FN = p.FN
	local cpx, cpy, cpz = CPX, CPY, CPZ
	-- its size on screen decides the line weight and the detail: its length
	-- at its distance, so it is the same standing, falling or lying (a piece
	-- never changes its look, Jamie 2026-11-13)
	local dc = (p.x - CPX) * CFX + (p.y - CPY) * CFY + (p.z - CPZ) * CFZ
	local tall = (dc > near) and f * 2 * p.hz / dc or y1 - y0
	local thick = tall >= t.thickFrom
	if thick then setLineWidth(2) end
	if p.king then
		drawKing(p, FN, tall)
	else
		for fi = 1, 6 do
			local o = 7 * fi - 7
			local nx, ny, nz = FN[o + 1], FN[o + 2], FN[o + 3]
			-- visible when the camera is in front of the face's plane
			if (cpx - FN[o + 4]) * nx + (cpy - FN[o + 5]) * ny + (cpz - FN[o + 6]) * nz > 0 then
				local F = FACES[fi]
				local a, b, cc, d = F[1], F[2], F[3], F[4]
				local shade = FN[o + 7]
				if shade == 1 then setColor(WHITE) end
				fillPolygon(SX[a], SY[a], SX[b], SY[b], SX[cc], SY[cc], SX[d], SY[d])
				if shade ~= 3 then setColor(BLACK) end
				drawPolygon(SX[a], SY[a], SX[b], SY[b], SX[cc], SY[cc], SX[d], SY[d])
			end
		end
		if tall >= t.grainFrom then
			if thick then setLineWidth(1) end
			grain(p, FN, tall)
			return
		end
	end
	if thick then setLineWidth(1) end
end

local function drawBaton(c, b)
	local x1, y1, z1, x2, y2, z2 = batonEnds(b)
	local a, bb, cc, d = projectSegment(c, x1, y1, z1, x2, y2, z2)
	if not a then return end
	local _, _, dep = project(c, b.x, b.y, b.z)
	local t = world.tune
	local w = dep and max(t.batonMinPx, floor(BATON_D * c.f / dep + 0.5)) or 2
	setColor(BLACK)
	gfx.setLineCapStyle(gfx.kLineCapStyleRound)
	setLineWidth(w + 2)
	drawLine(a, bb, cc, d)
	gfx.setLineCapStyle(gfx.kLineCapStyleButt)
	-- white with two black bands, in the air and at rest alike (a piece
	-- never changes its look)
	setColor(WHITE)
	setLineWidth(w)
	drawLine(a, bb, cc, d)
	setColor(BLACK)
	local ex, ey = cc - a, d - bb
	if ex * ex + ey * ey >= t.batonBandsFrom * t.batonBandsFrom then
		local u0, u1 = t.batonBandAt, t.batonBandAt + t.batonBand
		drawLine(a + ex * u0, bb + ey * u0, a + ex * u1, bb + ey * u1)
		drawLine(cc - ex * u1, d - ey * u1, cc - ex * u0, d - ey * u0)
	end
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
local K2 = {}   -- the previous frame's camera (the layer is made once it holds)
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
	k[26] = world.kidY or false
	local same = true
	for i = 1, 26 do
		local v = k[i]
		if K[i] ~= v then K[i] = v; same = false end
	end
	return same
end

-- The layer: a background image of the pitch and the pieces that held still
-- when it was made (in[i] true), for one camera (LK, the camera part of the
-- frame key) and item list. Valid while the camera and the list are the same
-- and none of those pieces has moved since (pose version bgVersion). Each
-- background piece keeps its screen box (piece and shadow) for the overlap
-- test.
local LK = {}
local bgImg = nil
local bgVersion, bgItems, bgN, bgAdv, bgKid = -1, nil, 0, nil, nil
local inBg = {}
local BX0, BY0, BX1, BY1 = {}, {}, {}, {}
local group = {}
local lastVersion = 0   -- poseVersion when the previous frame was drawn

-- Self-tests set world.verify = {} to check every layered frame against a
-- full redraw: frames (layered frames seen) and bad (pixels that differed).
world.verify = nil

-- Frames drawn each way since the scene last cleared it (the autobench and
-- the self-tests read it): cached (a copy of the last frame), layer (built
-- or drawn from the layer), full (from scratch).
world.count = { cached = 0, layer = 0, built = 0, full = 0 }

-- The screen box of item p (or the flying baton when p is nil and b given)
-- with its shadow, padded for line widths; false when it is partly behind
-- the camera (then it overlaps everything).
local function box(c, p, b)
	local x0, y0, x1, y1 = 1e9, 1e9, -1e9, -1e9
	if b or p.baton then
		local q = b or p
		local t = world.tune
		local ax, ay, az, bx, by, bz = batonEnds(q)
		local r = BATON_D / 2
		local z1, z2 = max(0, az) + r, max(0, bz) + r
		for k = 1, 4 do
			local px, py, pz
			if k == 1 then px, py, pz = ax, ay, az
			elseif k == 2 then px, py, pz = bx, by, bz
			elseif k == 3 then px, py, pz = ax + t.shadowX * z1, ay + t.shadowY * z1, 0
			else px, py, pz = bx + t.shadowX * z2, by + t.shadowY * z2, 0 end
			local sx, sy = project(c, px, py, pz)
			if not sx then return false end
			if sx < x0 then x0 = sx end
			if sx > x1 then x1 = sx end
			if sy < y0 then y0 = sy end
			if sy > y1 then y1 = sy end
		end
		local _, _, dep = project(c, q.x, q.y, q.z)
		local w = (dep and max(world.tune.batonMinPx, floor(BATON_D * c.f / dep + 0.5)) or 2) + 2
		local pad = w / 2 + 2
		return x0 - pad, y0 - pad, x1 + pad, y1 + pad
	end
	local WX, WY, WZ = p.WX, p.WY, p.WZ
	local f, cx, cy, near = CF, CCX, CCY, NEAR
	for k = 1, 8 do
		local dx, dy, dz = WX[k] - CPX, WY[k] - CPY, WZ[k] - CPZ
		local d = dx * CFX + dy * CFY + dz * CFZ
		if d < near then return false end
		local sc = f / d
		local sx = cx + sc * (dx * CRX + dy * CRY + dz * CRZ)
		local sy = cy - sc * (dx * CUX + dy * CUY + dz * CUZ)
		if sx < x0 then x0 = sx end
		if sx > x1 then x1 = sx end
		if sy < y0 then y0 = sy end
		if sy > y1 then y1 = sy end
	end
	local m = projectGround(p.hn, p.HX, p.HY)
	for k = 1, m do
		local sx, sy = poly[2 * k - 1], poly[2 * k]
		if sx < x0 then x0 = sx end
		if sx > x1 then x1 = sx end
		if sy < y0 then y0 = sy end
		if sy > y1 then y1 = sy end
	end
	if m < 3 and p.hn >= 3 then return false end
	return x0 - 2, y0 - 2, x1 + 2, y1 + 2
end

-- Draw items in the list (and the flying baton when withBaton): shadows,
-- then the pieces far to near, exactly as drawAll orders them.
local function drawSome(c, items, n, baton, list, nl, withBaton)
	setColor(BLACK)
	for j = 1, nl do
		local p = items[list[j]]
		if p.baton then batonShadow(c, p) else boxShadow(p) end
	end
	if withBaton then batonShadow(c, baton) end
	local m = 0
	for j = 1, nl do
		local p = items[list[j]]
		m = m + 1
		order[m], depth[m] = list[j], (p.x - CPX) * CFX + (p.y - CPY) * CFY + (p.z - CPZ) * CFZ
	end
	if withBaton then
		m = m + 1
		order[m], depth[m] = 0, (baton.x - CPX) * CFX + (baton.y - CPY) * CFY + (baton.z - CPZ) * CFZ
	end
	-- drawAll sorts every item with the flying baton last; a stable sort of
	-- a subset in the same order keeps the same relative order
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
		if depth[i] > NEAR then
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
end

-- Is the layer usable for this frame (same camera, same list, no
-- background piece moved)?
local function layerValid(items, n)
	if not layerReady or items ~= bgItems or n ~= bgN or (world.advantageY or false) ~= bgAdv
		or (world.kidY or false) ~= bgKid then return false end
	local k = KEY
	for i = 1, 15 do if LK[i] ~= k[i] then return false end end
	for i = 1, n do
		if inBg[i] and (items[i].pv or 0) > bgVersion then return false end
	end
	return true
end

-- Make the layer: everything that did not move since the previous frame.
local function buildLayer(c, items, n)
	if not bgImg then bgImg = gfx.image.new(400, 240, WHITE) end
	local list, nl = group, 0
	for i = 1, n do
		local still = (items[i].pv or 0) <= lastVersion
		inBg[i] = still
		if still then nl = nl + 1; list[nl] = i end
	end
	gfx.pushContext(bgImg)
	gfx.clear(WHITE)
	drawPitch()
	drawSome(c, items, n, nil, list, nl, false)
	gfx.popContext()
	for i = 1, n do
		if inBg[i] then
			local x0, y0, x1, y1 = box(c, items[i])
			if x0 then
				BX0[i], BY0[i], BX1[i], BY1[i] = x0, y0, x1, y1
			else
				BX0[i], BY0[i], BX1[i], BY1[i] = -1e9, -1e9, 1e9, 1e9
			end
		end
	end
	for i = 1, 15 do LK[i] = KEY[i] end
	bgItems, bgN, bgAdv, bgKid, bgVersion = items, n, world.advantageY or false, world.kidY or false, poseVersion
	layerReady = true
end

-- The frame from the layer: the background, then the moving pieces and the
-- background pieces that overlap them (and so on, until nothing more
-- overlaps), redrawn in depth order on top.
local GX0, GY0, GX1, GY1, GIN = {}, {}, {}, {}, {}
local function drawLayered(c, items, n, baton)
	bgImg:draw(0, 0)
	local ng = 0
	local list, nl = group, 0
	for i = 1, n do
		GIN[i] = false
		if not inBg[i] then
			GIN[i] = true
			nl = nl + 1; list[nl] = i
			local x0, y0, x1, y1 = box(c, items[i])
			if not x0 then x0, y0, x1, y1 = -1e9, -1e9, 1e9, 1e9 end
			ng = ng + 1
			GX0[ng], GY0[ng], GX1[ng], GY1[ng] = x0, y0, x1, y1
		end
	end
	if baton then
		local x0, y0, x1, y1 = box(c, nil, baton)
		if not x0 then x0, y0, x1, y1 = -1e9, -1e9, 1e9, 1e9 end
		ng = ng + 1
		GX0[ng], GY0[ng], GX1[ng], GY1[ng] = x0, y0, x1, y1
	end
	local grew = true
	while grew do
		grew = false
		for i = 1, n do
			if not GIN[i] then
				local a0, b0, a1, b1 = BX0[i], BY0[i], BX1[i], BY1[i]
				for g = 1, ng do
					if a0 <= GX1[g] and a1 >= GX0[g] and b0 <= GY1[g] and b1 >= GY0[g] then
						GIN[i] = true
						nl = nl + 1; list[nl] = i
						ng = ng + 1
						GX0[ng], GY0[ng], GX1[ng], GY1[ng] = a0, b0, a1, b1
						grew = true
						break
					end
				end
			end
		end
	end
	-- in item order, as drawAll draws them
	for i = 2, nl do
		local v, j = list[i], i - 1
		while j >= 1 and list[j] > v do list[j + 1] = list[j]; j = j - 1 end
		list[j + 1] = v
	end
	drawSome(c, items, n, baton, list, nl, baton ~= nil)
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
		world.count.cached = world.count.cached + 1
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
	-- the layer, once the camera has held still for a frame
	if world.tune.layer and cache then
		local camSame = true
		for i = 1, 15 do if K2[i] ~= KEY[i] then camSame = false end; K2[i] = KEY[i] end
		local valid = layerValid(items, n)
		if valid or (camSame and items == K2.items and n == K2.n) then
			local C = world.count
			if not valid then buildLayer(c, items, n); C.built = C.built + 1 end
			C.layer = C.layer + 1
			local V = world.verify
			if V then
				-- self-test: the layered frame must equal a full redraw
				V.a = V.a or gfx.image.new(400, 240, WHITE)
				V.b = V.b or gfx.image.new(400, 240, WHITE)
				gfx.pushContext(V.a); drawLayered(c, items, n, baton); gfx.popContext()
				gfx.pushContext(V.b); drawAll(c, items, n, baton); gfx.popContext()
				local bad = 0
				for y = 0, 239 do
					for x = 0, 399 do
						if V.a:sample(x, y) ~= V.b:sample(x, y) then bad = bad + 1 end
					end
				end
				V.frames, V.bad = (V.frames or 0) + 1, (V.bad or 0) + bad
				if bad > 0 and not V.shot then V.shot = true; V.a:draw(0, 0) else V.b:draw(0, 0) end
			else
				drawLayered(c, items, n, baton)
			end
			lastVersion = poseVersion
			lap("layer")
			return
		end
		K2.items, K2.n = items, n
	end
	lastVersion = poseVersion
	world.count.full = world.count.full + 1
	drawAll(c, items, n, baton)
end

tw.render.world = world
