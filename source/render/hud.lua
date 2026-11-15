-- HUD, in the Woodcut look (docs/design/README.md "HUD", boards/HUD.png):
-- a black rail on top, plaques along the bottom, nothing in the middle.
--
--   rail      0 0 400 14, always: pennant, team name, baton or kubb pips
--             (hollow = thrown, underlined = this one), the targets on the right
--   prompt    316 158 70 15, aiming: what to do next; white on black for FLICK!
--   clock     the throw as a clock (hud.clock): face at 351 207, r 30 with a
--             2 px drop shadow (319 177 to 383 239), always in the throw scene
--   plan chip 250 182 62 15, aiming: TILT or SPIN set (widening to the left)
--   rest flag 250 182 62 15 (hud.cutFlag, the plan chip's place), after a
--             drilled kubb stops: how far from the target circle it rests
--   flag      right edge 316, 199, h 15, after a release: the result
--   slow      right edge 316, 182, h 15, in flight while the slow motion plays
--   verdicts  73 222 158 15, after a throw: power, release, steadiness
--   minimap   frame 4 162 49 76, always
-- Everything else stays out of the clear area (the full width down to y 156,
-- then x 58 to 246 down to y 222).
--
-- Speed (AGENTS.md, "Drawing speed"): a graphics call costs 20 to 50 us on the
-- device and a line of text about 0.6 ms. The rail and every plaque is an
-- image drawn again only when a value it shows changes, so a normal frame
-- makes no text call. The clock and the minimap are layers: drawn straight to
-- the screen while their inputs change from frame to frame, and once a frame
-- repeats the last one's inputs, drawn into an image that is copied until an
-- input changes. A layer image is filled through gfx.setDrawOffset, so the
-- same code in screen coordinates fills the screen or the image, and layers
-- sit on the 8 px grid so patterns keep their phase: the pixels are the same
-- either way.
import "CoreLibs/graphics"
import "CoreLibs/ui"
import "core/tw"
import "core/camera"
import "render/world"

local gfx <const> = playdate.graphics
local camera = tw.camera
local rworld = tw.render.world
local floor, cos, sin, rad, max, min, abs, sqrt = math.floor, math.cos, math.sin, math.rad, math.max, math.min, math.abs, math.sqrt
local CLEAR <const>, BLACK <const>, WHITE <const> = gfx.kColorClear, gfx.kColorBlack, gfx.kColorWhite

tw.render = tw.render or {}
local hud = {}

hud.tune = {
	-- Labels: Roobert 10 Bold from the system, capitals only (DESIGN "Type").
	labelFont = "/System/Fonts/Roobert-10-Bold.pft",
	-- The display font: big numbers and words. Throwing Wood Display at cap 16
	-- (render/ui, AGENTS.md "Woodcut type"); the system font if it cannot be loaded.
	displayFont = "fonts/ThrowingWoodDisplay-16",
	labelTop = 2,       -- px from a label's box top to its font's cell top (centres the caps)
	displayTop = -2,    -- the same for the display font
	shadow = 2,         -- px the plaques' drop shadow sits right and down
	rail = { h = 14, pennantX = 4, nameX = 17, pipsX = 188, rightX = 395, gap = 6, dotGap = 4 },
	prompt = { x = 316, y = 158, w = 70, h = 15 },
	-- a flag in the plan chip's place (a drilled kubb's rest distance after it stops)
	cutFlag = { x = 250, y = 182, w = 62, h = 15 },
	-- the result after a release, left of the clock (x + w is its right
	-- edge; a long word widens it to the left)
	flag = { x = 240, y = 199, w = 76, h = 15 },
	-- while the slow motion around a hit plays (playback.speed below 1): an
	-- inverted flag over the result flag, so a deliberate slow-down reads
	-- apart from the physics falling behind (which shows nothing)
	slow = { x = 240, y = 182, w = 76, h = 15, text = "SLOW MOTION" },
	-- throwing from the advantage line (Jamie, 2026-11-14: "a big deal"): an
	-- inverted flag centred under the rail, with how far up the line is
	advantage = { y = 18, h = 15 },
	-- the wind: its label above the minimap, and the arrow's length on it
	wind = { x = 4, y = 145, h = 15, baseLen = 10, perMps = 2.5, maxLen = 30 },
	-- The throw as a clock (DESIGN 4, hud.clock): a white face in a 2 px black
	-- frame with a drop shadow, centred under the prompt flag. ring: the band
	-- inside the frame that holds the zones and targets; ticks inside it
	-- (tick, the long ones at 12, 3, 6 and 9 tickLong); the hand reaches to
	-- `hand` px from the centre (the idle crank's to `crankHand`); dots on the
	-- ring for the backswing peak and the last throw (dotR).
	clock = { x = 351, y = 207, r = 30, frame = 2, ring = 5, tick = 3, tickLong = 5, sliceIn = 5, hand = 20,
		crankHand = 20, hub = 3, dotR = 3 },
	-- After a throw (hud.verdicts): power, release, steadiness as one plate of
	-- three cells, a miss white on black. Below the clear area, right of the
	-- minimap.
	verdicts = { x = 73, y = 222, w = 180, h = 15 },   -- w: STEADY needs room in its third (it touched at 158)
	-- While aiming (hud.planChip): the tilt or spin B has set, in the cut
	-- flag's place (widening to the left)
	planChip = { x = 250, y = 182, w = 62, h = 15 },
	readoutX = 4, readoutY = 17,  -- the System Menu "Readout" line, just under the rail
	cardPad = 10, cardGap = 6, cardRise = 20,              -- hand-off and winner card: padding,
	                                                       -- line gap, px above screen center
	cache = true,                                          -- cache unchanged parts as images
}

-- the only grey (DESIGN "Tones"): a 50% checker
local GREY <const> = { 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA }

-- ---------- fonts ----------

local fonts = {}
local function font(path)
	local f = fonts[path]
	if f == nil then
		f = gfx.font.new(path) or gfx.getSystemFont(gfx.font.kVariantBold) or gfx.getSystemFont()
		fonts[path] = f
	end
	return f
end
function hud.labelFont() return font(hud.tune.labelFont) end
function hud.displayFont() return font(hud.tune.displayFont) end

-- Text with its top-left cell corner at x, y, black or white.
local function text(f, s, x, y, white)
	if white then gfx.setImageDrawMode(gfx.kDrawModeFillWhite) end
	f:drawText(s, x, y)
	if white then gfx.setImageDrawMode(gfx.kDrawModeCopy) end
end

-- ---------- layers (clock, minimap) ----------

-- A layer: an image covering screen x0..x1, y0..y1, widened to the 8 px
-- grid so patterns and dithers keep their phase.
local function newLayer(x0, y0, x1, y1)
	local x, y = x0 - x0 % 8, y0 - y0 % 8
	local w, h = x1 + 1 - x, y1 + 1 - y
	w, h = w + (-w) % 8, h + (-h) % 8
	return { x = x, y = y, w = w, h = h, img = nil, ready = false }
end

-- Start drawing a layer whose inputs are `same` as last frame's. Returns
-- nil when the cached image was drawn (nothing else to do); otherwise 0, 0
-- (the part draws at screen coordinates; filling the image, the draw offset
-- maps them into it).
local function begin(L, same)
	if not hud.tune.cache or not same then
		L.ready = false
		return 0, 0
	end
	if L.ready then
		L.img:draw(L.x, L.y)
		return nil
	end
	if not L.img then L.img = gfx.image.new(L.w, L.h, CLEAR) else L.img:clear(CLEAR) end
	gfx.pushContext(L.img)
	gfx.setDrawOffset(-L.x, -L.y)
	L.filling = true
	return 0, 0
end

local function finish(L)
	if L.filling then
		gfx.setDrawOffset(0, 0)
		gfx.popContext()
		L.filling = false
		L.ready = true
		L.img:draw(L.x, L.y)
	end
end

-- ---------- plates: an image per part, redrawn when its key changes ----------

-- A plate holds one image for a fixed screen box (x, y, w, h, the drop
-- shadow included) and the key it was drawn for. plateBegin returns true when
-- the image must be drawn again (pushed and cleared: draw in plate
-- coordinates), false when the old one is still good.
local function newPlate(x, y, w, h)
	return { x = x, y = y, w = w, h = h, img = nil, k1 = nil, k2 = nil, k3 = nil, k4 = nil, k5 = nil, k6 = nil }
end

local function plateBegin(P, k1, k2, k3, k4, k5, k6)
	if hud.tune.cache and P.img and P.k1 == k1 and P.k2 == k2 and P.k3 == k3 and P.k4 == k4 and P.k5 == k5
		and P.k6 == k6 then
		return false
	end
	P.k1, P.k2, P.k3, P.k4, P.k5, P.k6 = k1, k2, k3, k4, k5, k6
	if not P.img then P.img = gfx.image.new(P.w, P.h, CLEAR) else P.img:clear(CLEAR) end
	gfx.pushContext(P.img)
	return true
end

local function plateEnd(P)
	gfx.popContext()
end

-- A white plaque with a 2 px black frame and a drop shadow, its outer box at
-- x, y (plate coordinates), w by h.
local function plaque(x, y, w, h, black)
	local sh = hud.tune.shadow
	gfx.setColor(BLACK)
	gfx.fillRect(x + sh, y + sh, w, h)
	gfx.fillRect(x, y, w, h)
	if not black then
		gfx.setColor(WHITE)
		gfx.fillRect(x + 2, y + 2, w - 4, h - 4)
		gfx.setColor(BLACK)
	end
end

-- A one-line flag: a plaque with a label in it, centred (or from the left
-- at `left` px), black on white or white on black (`inverted`).
local function flagIn(x, y, w, h, s, inverted, left)
	plaque(x, y, w, h, inverted)
	local f = hud.labelFont()
	local tx = left and (x + left) or (x + floor((w - f:getTextWidth(s)) / 2))
	text(f, s, tx, y + hud.tune.labelTop, inverted)
end

-- ---------- the rail ----------

local railPlate = newPlate(0, 0, 400, 14)

-- The rail. name: the team (or "PRACTICE"); kind: "baton" | "kubb" | nil
-- (no pips); n, of: this throw and the throws of its kind this turn; right1,
-- right2: the targets ("FIELD 2", "BASE 5"), joined by a dot.
function hud.rail(name, kind, n, of, right1, right2)
	local P = railPlate
	if plateBegin(P, name, kind, n, of, right1, right2) then
		local t = hud.tune.rail
		local f = hud.labelFont()
		local top = hud.tune.labelTop - 1
		gfx.setColor(BLACK)
		gfx.fillRect(0, 0, 400, t.h)
		gfx.setColor(WHITE)
		-- the pennant
		local px = t.pennantX
		gfx.fillRect(px, 3, 1, 9)
		gfx.fillPolygon(px + 1, 3, px + 9, 5, px + 1, 8)
		if name then text(f, name, t.nameX, top, true) end
		if kind and of and of > 0 then
			local pw, ph, step, py = 3, 8, 7, 3
			if kind == "kubb" then pw, ph, step, py = 5, 6, 10, 4 end
			local width = (of - 1) * step + pw
			local x0 = t.pipsX - floor(width / 2)
			gfx.setColor(WHITE)
			for i = 1, of do
				local x = x0 + (i - 1) * step
				if i < n then
					gfx.drawRect(x, py, pw, ph)
				else
					gfx.fillRect(x, py, pw, ph)
				end
				if i == n then gfx.fillRect(x - 1, 12, pw + 2, 1) end
			end
			local label = (kind == "kubb") and "KUBBS" or "BATONS"
			text(f, label, x0 - t.gap - f:getTextWidth(label), top, true)
		end
		local x = t.rightX
		if right2 then
			x = x - f:getTextWidth(right2)
			text(f, right2, x, top, true)
			x = x - t.dotGap - 2
			gfx.setColor(WHITE)
			gfx.fillRect(x, 6, 2, 2)
			x = x - t.dotGap
		end
		if right1 then text(f, right1, x - f:getTextWidth(right1), top, true) end
		plateEnd(P)
	end
	P.img:draw(P.x, P.y)
end

-- ---------- the prompt flag and the cut flag ----------

local promptPlate = newPlate(0, 0, 0, 0)
-- s: the prompt (12 characters at most), or nil for none; inverted: white on
-- black (FLICK). The flag widens to its text, from its left edge.
function hud.prompt(s, inverted)
	if not s then return end
	local t, P = hud.tune.prompt, promptPlate
	if P.k1 ~= s or P.k2 ~= inverted or not hud.tune.cache then
		-- a longer prompt widens the flag; past the screen's edge it moves left
		local w = max(t.w, hud.labelFont():getTextWidth(s) + 10)
		if w + hud.tune.shadow ~= P.w then P.img = nil end
		P.x, P.y, P.w, P.h = min(t.x, 398 - hud.tune.shadow - w), t.y, w + hud.tune.shadow, t.h + hud.tune.shadow
	end
	if plateBegin(P, s, inverted) then
		flagIn(0, 0, P.w - hud.tune.shadow, t.h, s, inverted)
		plateEnd(P)
	end
	P.img:draw(P.x, P.y)
end

local cutPlate
function hud.cutFlag(s)
	local t = hud.tune.cutFlag
	local sh = hud.tune.shadow
	local P = cutPlate
	if not P or P.k1 ~= s or not hud.tune.cache then
		-- a word wider than the plaque widens the flag to the left
		local w = max(t.w, hud.labelFont():getTextWidth(s) + 10)
		if not P or P.w ~= w + sh then
			P = newPlate(t.x, t.y, w + sh, t.h + sh)
			cutPlate = P
		end
		P.x = t.x + t.w - w
	end
	if plateBegin(P, s) then
		flagIn(0, 0, P.w - sh, t.h, s, false)
		plateEnd(P)
	end
	P.img:draw(P.x, P.y)
end

-- ---------- the minimap ----------

local function dot(x, y, size, ox, oy)
	local sx, sy = camera.toMinimap(x, y)
	gfx.fillRect(floor(sx - size / 2 + 0.5) + ox, floor(sy - size / 2 + 0.5) + oy, size, size)
end

local mm = camera.minimap
local mapLayer = newLayer(mm.ox - 2, mm.oy - 2, mm.ox + mm.w + 6, 239)
local mapKey = {}

-- state: playerX, lineY, aimX, aimY (aim preview landing), baton (or nil),
-- landX, landY (or nil), pieces and npieces (render/world items), advY
-- (the advantage line, or nil)
function hud.minimap(state)
	local m = camera.minimap
	local ox, oy, w, h = m.ox, m.oy, m.w, m.h
	-- the frame and the pieces: a layer keyed on the poses and toppled flags
	local pieces, np = state.pieces, state.npieces or 0
	local mask = 0
	for i = 1, np do
		if pieces[i].toppled then mask = mask | (1 << (i - 1)) end
	end
	local ver = rworld.poseVersion()
	local K = mapKey
	local adv = state.advY or false
	local same = K[1] == ver and K[2] == pieces and K[3] == np and K[4] == mask and K[5] == adv
	K[1], K[2], K[3], K[4], K[5] = ver, pieces, np, mask, adv
	local dx, dy = begin(mapLayer, same)
	if dx then
		-- the plaque: its 2 px frame is the pitch's edge
		local sh = hud.tune.shadow
		local fx, fy, fw, fh = ox - 2 + dx, oy - 2 + dy, w + 4, h + 4
		gfx.setColor(BLACK)
		gfx.fillRect(fx + sh, fy + sh, fw, fh)
		gfx.fillRect(fx, fy, fw, fh)
		gfx.setColor(WHITE)
		gfx.fillRect(fx + 2, fy + 2, fw - 4, fh - 4)
		gfx.setColor(BLACK)
		gfx.setLineWidth(1)
		-- the centerline: 1 on 2 off
		for x = 0, w - 1, 3 do gfx.drawPixel(ox + x + dx, oy + h / 2 + dy) end
		-- the advantage line: every other pixel, a row of its own
		if adv then
			local _, ay = camera.toMinimap(0, adv)
			ay = floor(ay + 0.5)
			for x = 0, w - 1, 2 do gfx.drawPixel(ox + x + dx, ay + dy) end
		end
		-- standing pieces are solid (the king bigger), fallen ones hollow
		for i = 1, np do
			local p = pieces[i]
			local y = p.y
			if y >= 8 then y = 7.7 elseif y <= 0 then y = 0.3 end
			if p.baton then
				dot(p.x, y, 1, dx, dy)
			elseif p.toppled then
				local sx, sy = camera.toMinimap(p.x, y)
				gfx.drawRect(floor(sx - 1) + dx, floor(sy - 0.5) + dy, 3, 2)
			else
				dot(p.x, y, p.king and 3 or 2, dx, dy)
			end
		end
		finish(mapLayer)
	end
	gfx.setColor(BLACK)
	gfx.setLineWidth(1)
	-- aim line from the player to the full-power landing point
	local px, py = camera.toMinimap(state.playerX, state.lineY)
	if state.aimX then
		-- clipped to the minimap's frame (a full-power preview can land past
		-- the far baseline or the sidelines)
		local x0, y0, x1, y1 = state.playerX, state.lineY, state.aimX, state.aimY
		local t = 1
		local ymax, xmax = 8 + 1 / m.scale, 2.5
		if y1 > ymax then t = min(t, (ymax - y0) / (y1 - y0)) end
		if x1 > xmax then t = min(t, (xmax - x0) / (x1 - x0)) end
		if x1 < -xmax then t = min(t, (-xmax - x0) / (x1 - x0)) end
		local ax, ay = camera.toMinimap(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)
		gfx.drawLine(px, py, ax, ay)
	end
	-- the player: a small triangle pointing up the pitch, just behind the line
	local tx, ty = floor(px + 0.5), floor(py + 0.5)
	gfx.fillPolygon(tx - 2, ty + 4, tx + 3, ty + 4, tx, ty)
	if state.landX then
		local lx, ly = camera.toMinimap(state.landX, state.landY)
		gfx.drawLine(lx - 2, ly - 2, lx + 2, ly + 2)
		gfx.drawLine(lx - 2, ly + 2, lx + 2, ly - 2)
	end
	if state.baton then
		-- held to the frame's edge when it flies past it
		local bx, by = state.baton.x, state.baton.y
		if by > 8.1 then by = 8.1 elseif by < -0.1 then by = -0.1 end
		if bx > 2.6 then bx = 2.6 elseif bx < -2.6 then bx = -2.6 end
		dot(bx, by, 3, 0, 0)
	end
end

-- ---------- the wind ----------

local windPlate
-- The wind (core/wind; a match with WIND on): an arrow across the minimap's
-- middle the way the wind blows in the thrower's view (wx, wy m/s: x across,
-- y down the pitch, so up the map), longer the stronger, and the speed on a
-- small inverted label above the minimap (one cached image per text). Over
-- the minimap's layer, every frame: a line, a head, one image.
function hud.wind(text, wx, wy)
	local m = camera.minimap
	local t = hud.tune.wind
	local sp = sqrt(wx * wx + wy * wy)
	if sp > 0.01 then
		local cx, cy = m.ox + m.w / 2, m.oy + m.h / 2
		local L = min(t.maxLen, t.baseLen + t.perMps * sp)
		local ux, uy = wx / sp, -wy / sp
		local hx, hy = cx + ux * L / 2, cy + uy * L / 2
		local qx, qy = cx - ux * L / 2, cy - uy * L / 2
		gfx.setColor(BLACK)
		gfx.setLineWidth(2)
		gfx.drawLine(qx, qy, hx, hy)
		gfx.setLineWidth(1)
		local px, py = -uy, ux
		local hw, hl = 3, 5
		gfx.fillPolygon(hx + ux * 2, hy + uy * 2, hx - ux * hl + px * hw, hy - uy * hl + py * hw,
			hx - ux * hl - px * hw, hy - uy * hl - py * hw)
	end
	local sh = hud.tune.shadow
	local P = windPlate
	if not P or P.k1 ~= text or not hud.tune.cache then
		local w = hud.labelFont():getTextWidth(text) + 10
		if not P or P.w ~= w + sh then
			P = newPlate(t.x, t.y, w + sh, t.h + sh)
			windPlate = P
		end
	end
	if plateBegin(P, text) then
		flagIn(0, 0, P.w - sh, t.h, text, true)
		plateEnd(P)
	end
	P.img:draw(P.x, P.y)
end

-- ---------- after the release: the result flag ----------

local flagPlate, slowPlate, advPlate
-- s: the result in 12 characters or fewer (hud.short), or nil.
-- The slow motion flag (hud.tune.slow): one cached image.
function hud.slow()
	local t = hud.tune.slow
	local sh = hud.tune.shadow
	local P = slowPlate
	if not P then
		-- as wide as the word needs, widening to the left
		local w = max(t.w, hud.labelFont():getTextWidth(t.text) + 10)
		P = newPlate(t.x + t.w - w, t.y, w + sh, t.h + sh)
		slowPlate = P
	end
	if plateBegin(P, t.text) then
		flagIn(0, 0, P.w - sh, t.h, t.text, true)
		plateEnd(P)
	end
	P.img:draw(P.x, P.y)
end

-- The advantage line flag (hud.tune.advantage): text from hud.advantageText.
-- One cached image, redrawn only when the text changes.
function hud.advantageText(meters) return string.format("ADVANTAGE LINE  %.1f M", meters) end
function hud.advantage(text)
	local t = hud.tune.advantage
	local sh = hud.tune.shadow
	local P = advPlate
	if not P or P.k1 ~= text or not hud.tune.cache then
		local w = hud.labelFont():getTextWidth(text) + 14
		if not P or P.w ~= w + sh then
			P = newPlate(0, t.y, w + sh, t.h + sh)
			advPlate = P
		end
		P.x = floor((400 - w) / 2)
	end
	if plateBegin(P, text) then
		flagIn(0, 0, P.w - sh, t.h, text, true)
		plateEnd(P)
	end
	P.img:draw(P.x, P.y)
end

function hud.flag(s)
	if not s then return end
	local t = hud.tune.flag
	local sh = hud.tune.shadow
	local P = flagPlate
	if not P or P.k1 ~= s or not hud.tune.cache then
		-- a long word widens the flag to the left
		local w = max(t.w, hud.labelFont():getTextWidth(s) + 10)
		if not P or P.w ~= w + sh then
			P = newPlate(0, t.y, w + sh, t.h + sh)
			flagPlate = P
		end
		P.x = t.x + t.w - w
	end
	if plateBegin(P, s) then
		flagIn(0, 0, P.w - sh, t.h, s, false)
		plateEnd(P)
	end
	P.img:draw(P.x, P.y)
end

-- The match's result line (core/match m.text) as a flag: its first part, in
-- words a newcomer can read (the RC review of 2026-11-15: KING EARLY and
-- PUT BACK did not say what happened; the flag widens to the left, up to
-- about 180 px). Once per throw, not per frame.
local SHORT = {
	{ "^king down early", "KING TOO EARLY: GAME OVER" }, { "^king down", "KING DOWN" }, { "^resigned", "RESIGNED" },
	{ "^missed the king", "KING STANDS" }, { "^missed", "MISS" }, { "^helicopter", "HELICOPTER: DOESN'T COUNT" },
	{ "^own%-half kubb hit", "OWN HALF HIT: PUT BACK" }, { "^own half hit", "OWN HALF HIT: KUBB OUT" },
	{ "^kubb in for now", "IN FOR NOW" }, { "^kubb out for now", "OUT FOR NOW" },
	{ "^kubb in", "IN" }, { "^all in", "ALL IN" }, { "^kubb out: rethrown", "OUT: THROW AGAIN" },
	{ "^(%d+) out: rethrown", "%1 OUT: THROW AGAIN" }, { "^out twice", "OUT TWICE: PUNISHMENT" },
	{ "^(%d+) punishment", "%1 PUNISHMENT KUBBS" }, { "^on a kubb", "ON A KUBB: LOWERED" }, { "rescue", "RESCUE" },
}
function hud.short(s)
	if not s then return nil end
	local first = s:match("^[^;]*")
	for _, r in ipairs(SHORT) do
		if first:find(r[1]) then return (first:gsub("^.*$", function(m) return (m:gsub(r[1] .. ".*$", r[2])) end)) end
	end
	-- kubbs down: "2 field kubbs and base kubb down"
	if first:find("down$") then
		local n = 0
		for c in first:gmatch("(%d*) ?[fb]%a+ kubbs?") do n = n + (c == "" and 1 or tonumber(c)) end
		if n > 0 then return n .. " DOWN" end
	end
	return first:upper():sub(1, 12)
end

-- ---------- the debug readout (System Menu "Readout") ----------

-- A boxed text label: white box, black frame, the text inside. Cached as an
-- image per string.
local boxes, nboxes = {}, 0
local function textBox(s, padL, padT, padR, padB)
	local b = boxes[s]
	if not b then
		if nboxes >= 32 then boxes, nboxes = {}, 0 end
		local w, h = gfx.getTextSize(s)
		local bw, bh = w + padL + padR, h + padT + padB
		local img = gfx.image.new(bw, bh, CLEAR)
		gfx.pushContext(img)
		gfx.setColor(WHITE)
		gfx.fillRect(0, 0, bw, bh)
		gfx.setColor(BLACK)
		gfx.setLineWidth(1)
		gfx.drawRect(0, 0, bw, bh)
		gfx.drawText(s, padL, padT)
		gfx.popContext()
		b = { img = img, w = w, h = h }
		boxes[s] = b
		nboxes = nboxes + 1
	end
	return b
end

-- The debug readout for a throw (the practice pitch's "Pitch: readout"),
-- built once per throw, not per frame: the backswing against the power
-- target's centre, the stop against the release target's (degrees on the
-- clock), the flick's speed (deg/s) and the shake (0 steady .. 1); then
-- HELICOPTER for an illegal throw, and how far it carried and what fell, or
-- for a drilled kubb how far from the target circle it rests. `l` is the
-- throw scene's s.last.
function hud.readoutText(l)
	local s = string.format("back %d/%d stop %d/%d flick %d shake %.2f", floor((l.back or 0) + 0.5),
		floor((l.planBack or 0) + 0.5), floor((l.stop or 0) + 0.5), floor((l.plan or 0) + 0.5),
		floor((l.flick or 0) + 0.5), l.shake or 0)
	if l.legal == false then s = s .. " HELICOPTER" end
	if l.drill then
		if l.restCm then s = s .. string.format(" rest %.2f m", l.restCm / 100) end
	else
		s = s .. string.format(" %.2f m", l.distance or 0)
		if l.down then s = s .. string.format(" down %d", l.down) end
	end
	return s
end

-- The readout, just under the rail at the left (only with "Readout" on).
function hud.readout(s)
	local t = hud.tune
	local b = textBox(s, 2, 2, 2, 1)
	b.img:draw(t.readoutX - 2, t.readoutY - 2)
end

-- ---------- the throw as a clock (DESIGN 4, "The throw: the crank as a clock") ----------

-- The dead zone (6 to 7: nothing has started): sparse dots. Overpowered (11
-- to 12): a diagonal hatch. Targets: solid black. (Pattern bits: 1 = white.)
local DEAD <const> = { 0x77, 0xFF, 0xDD, 0xFF, 0x77, 0xFF, 0xDD, 0xFF }
local HATCH <const> = { 0x33, 0x99, 0xCC, 0x66, 0x33, 0x99, 0xCC, 0x66 }

local ct = hud.tune.clock
local clockLayer = newLayer(ct.x - ct.r - 2, ct.y - ct.r - 2, ct.x + ct.r + hud.tune.shadow, 239)
local clockKey = {}
local faceImg = nil
local faceKey = {}

-- The point at radius R for an arm angle (forward degrees from the bottom of
-- the turn: 0 = 6 o'clock, -90 = 9, +90 = 3, +-180 = 12). drawArc's angles
-- are the clock's (0 = up, clockwise), so an arm angle a is drawArc's 180 - a.
local function onClock(cx, cy, R, arm)
	local a = rad(180 - arm)
	return cx + R * sin(a), cy - R * cos(a)
end

-- A target: the slice between arm angles a0 < a1 from radius r0 to r1, grey
-- in a black outline, and solid black across the ring (rm, width w) so the
-- hand, which stops short of the ring, never hides it. With a pattern, a
-- zone: the slice in that pattern alone. (Only when the face is drawn again,
-- not per frame.)
local slicePts = {}
local function slice(cx, cy, r0, r1, a0, a1, rm, w, pattern)
	local P, n = slicePts, 0
	local function add(x, y) P[n + 1], P[n + 2] = floor(x + 0.5), floor(y + 0.5); n = n + 2 end
	add(onClock(cx, cy, r0, a0))
	local steps = max(1, floor((a1 - a0) / 4 + 0.5))
	for i = 0, steps do add(onClock(cx, cy, r1, a0 + (a1 - a0) * i / steps)) end
	add(onClock(cx, cy, r0, a1))
	for i = #P, n + 1, -1 do P[i] = nil end
	gfx.setPattern(pattern or GREY)
	gfx.fillPolygon(table.unpack(P))
	gfx.setColor(BLACK)
	if pattern then return end   -- a zone: the pattern alone
	gfx.drawPolygon(table.unpack(P))
	gfx.setLineWidth(w)
	gfx.drawArc(cx, cy, rm, 180 - a1, 180 - a0)
	gfx.setLineWidth(1)
end

-- A hollow dot on the ring: the last throw's backswing peak or stop.
local function lastDot(cx, cy, R, arm, dr)
	local x, y = onClock(cx, cy, R, arm)
	gfx.setColor(WHITE)
	gfx.fillCircleAtPoint(x, y, dr + 1)
	gfx.setColor(BLACK)
	gfx.drawCircleAtPoint(x, y, dr)
end

-- What changes only when the player re-aims (targets) or throws (the last
-- dots): the face, the ring with its zones and targets, the ticks.
local function drawFace(cx, cy, pLo, pHi, rLo, rHi, dead, over, lastBack, lastStop)
	local t = hud.tune.clock
	local r, sh = t.r, hud.tune.shadow
	local ro = r - t.frame              -- the ring's outer edge
	local ri = ro - t.ring              -- and its inner edge
	local rm = (ro + ri) / 2
	gfx.setColor(BLACK)
	gfx.fillCircleAtPoint(cx + sh, cy + sh, r)
	gfx.fillCircleAtPoint(cx, cy, r)
	gfx.setColor(WHITE)
	gfx.fillCircleAtPoint(cx, cy, ro)
	-- the zones: slices in their patterns
	if dead and dead > 0 then slice(cx, cy, t.sliceIn, ro, -dead, 0, rm, t.ring, DEAD) end
	if over and over < 180 then slice(cx, cy, t.sliceIn, ro, -180, -over, rm, t.ring, HATCH) end
	-- the targets: slices from near the hub to the frame, grey in a black
	-- outline (the drill band's look), so even a narrow one reads and the hand
	-- shows over it
	if pLo and pHi and pHi > pLo then slice(cx, cy, t.sliceIn, ro, -pHi, -pLo, rm, t.ring) end
	if rLo and rHi and rHi > rLo then slice(cx, cy, t.sliceIn, ro, rLo, rHi, rm, t.ring) end
	-- the ring's inner edge
	gfx.drawCircleAtPoint(cx, cy, ri)
	-- the hours, inside the ring
	for h = 0, 11 do
		local arm = h * 30
		local long = (h % 3 == 0)
		local x0, y0 = onClock(cx, cy, ri - 1, arm)
		local x1, y1 = onClock(cx, cy, ri - (long and t.tickLong or t.tick), arm)
		gfx.setLineWidth(long and 2 or 1)
		gfx.drawLine(x0, y0, x1, y1)
	end
	gfx.setLineWidth(1)
	if lastBack then lastDot(cx, cy, rm, -lastBack, t.dotR) end
	if lastStop then lastDot(cx, cy, rm, lastStop, t.dotR) end
end

local function q(v) return v and floor(v + 0.5) or false end

-- The throw gauge as a clock (aiming only). st is a table the scene owns and
-- reuses (nothing is made per frame):
--   phase      "idle" | "winding" | "swinging" | "cooldown"
--   arm        the arm's position, forward degrees from the bottom of the turn
--              (negative on the backswing side: -120 = 10 o'clock, +90 = 3)
--   crank      the idle crank's position as an arm angle (shown while idle)
--   back       the farthest backswing so far (positive degrees), or 0
--   powerLo, powerHi      the power target (backswing degrees, positive)
--   releaseLo, releaseHi  the release target (forward degrees)
--   deadDeg, overDeg      6 to deadDeg is dead; past overDeg is overpowered
--   lastBack, lastStop    the last throw's peak and stop (or nil): hollow dots
--   prompt     a short word for the prompt flag over the dial, or nil; one
--              ending in "!" (FLICK!) is white on black
-- Backswing on the left, forward on the right, as the player reads a clock.
-- The face, ring, zones, targets, ticks and last dots are one image keyed on
-- those values; the hand and the live peak are drawn over it, and the whole
-- dial is a layer (a frame that repeats the last one's inputs is one copy).
function hud.clock(st)
	local t = hud.tune.clock
	local cx, cy = t.x, t.y
	local phase = st.phase
	local live = (phase == "winding" or phase == "swinging")
	local hand = q(phase == "idle" and (st.crank or 0) or (st.arm or 0))
	local back = live and q(st.back or 0) or 0
	local pLo, pHi, rLo, rHi = q(st.powerLo), q(st.powerHi), q(st.releaseLo), q(st.releaseHi)
	local dead, over, lb, ls = q(st.deadDeg), q(st.overDeg), q(st.lastBack), q(st.lastStop)
	local K = clockKey
	local same = K[1] == phase and K[2] == hand and K[3] == back and K[4] == pLo and K[5] == pHi and K[6] == rLo
		and K[7] == rHi and K[8] == dead and K[9] == over and K[10] == lb and K[11] == ls
	K[1], K[2], K[3], K[4], K[5], K[6], K[7], K[8], K[9], K[10], K[11] =
		phase, hand, back, pLo, pHi, rLo, rHi, dead, over, lb, ls
	local L = clockLayer
	if begin(L, same) then
		local F = faceKey
		if not hud.tune.cache then
			drawFace(cx, cy, pLo or nil, pHi or nil, rLo or nil, rHi or nil, dead or nil, over or nil, lb or nil, ls or nil)
		else
			if not faceImg or F[1] ~= pLo or F[2] ~= pHi or F[3] ~= rLo or F[4] ~= rHi or F[5] ~= dead
				or F[6] ~= over or F[7] ~= lb or F[8] ~= ls then
				F[1], F[2], F[3], F[4], F[5], F[6], F[7], F[8] = pLo, pHi, rLo, rHi, dead, over, lb, ls
				faceImg = faceImg or gfx.image.new(L.w, L.h, CLEAR)
				faceImg:clear(CLEAR)
				gfx.pushContext(faceImg)
				drawFace(cx - L.x, cy - L.y, pLo or nil, pHi or nil, rLo or nil, rHi or nil, dead or nil, over or nil,
					lb or nil, ls or nil)
				gfx.popContext()
			end
			faceImg:draw(L.x, L.y)
		end
		local rm = t.r - t.frame - t.ring / 2
		-- the live backswing peak: a black dot in a white ring, so it reads on
		-- a target as well as on the bare ring
		if back > 0 then
			local x, y = onClock(cx, cy, rm, -back)
			gfx.setColor(WHITE)
			gfx.fillCircleAtPoint(x, y, t.dotR + 1)
			gfx.setColor(BLACK)
			gfx.fillCircleAtPoint(x, y, t.dotR - 1)
		end
		-- the hand: thick while throwing, thin where the idle crank sits
		local hx, hy = onClock(cx, cy, live and t.hand or t.crankHand, hand)
		if live then
			-- a white edge, so the hand shows over a grey target
			gfx.setColor(WHITE)
			gfx.setLineWidth(5)
			gfx.drawLine(cx, cy, hx, hy)
		end
		gfx.setColor(BLACK)
		gfx.setLineWidth(live and 3 or 1)
		gfx.drawLine(cx, cy, hx, hy)
		gfx.setLineWidth(1)
		gfx.fillCircleAtPoint(cx, cy, t.hub)
		finish(L)
	end
	if st.prompt then hud.prompt(st.prompt, st.prompt:sub(-1) == "!") end
end

-- ---------- after the throw: the verdicts; while aiming: the plan chip ----------

local verdictPlate
local POWER_V <const> = { [-2] = "SLOW", [-1] = "SHORT", [0] = "ON", [1] = "LONG" }
local RELEASE_V <const> = { [-1] = "LOW", [0] = "ON", [1] = "HIGH" }

-- powerV, releaseV: -1 | 0 | 1 (short / on / long, low / on / high; powerV -2: slow flick);
-- steady: true for STEADY, false for SHAKY. One plate of three cells in a
-- row, a miss white on black; drawn again only when a verdict changes.
function hud.verdicts(powerV, releaseV, steady)
	local t = hud.tune.verdicts
	local sh = hud.tune.shadow
	verdictPlate = verdictPlate or newPlate(t.x, t.y, t.w + sh, t.h + sh)
	steady = steady and true or false
	if plateBegin(verdictPlate, powerV, releaseV, steady) then
		plaque(0, 0, t.w, t.h)
		local f = hud.labelFont()
		local cw = floor((t.w - 4 - 4) / 3)   -- three cells inside the frame, 2 px rules between
		for i = 1, 3 do
			local s, miss
			if i == 1 then s, miss = POWER_V[powerV] or "?", powerV ~= 0
			elseif i == 2 then s, miss = RELEASE_V[releaseV] or "?", releaseV ~= 0
			else s, miss = steady and "STEADY" or "SHAKY", not steady end
			local x = 2 + (i - 1) * (cw + 2)
			local w = (i == 3) and (t.w - 2 - x) or cw
			if i > 1 then gfx.setColor(BLACK); gfx.fillRect(x - 2, 0, 2, t.h) end
			if miss then gfx.setColor(BLACK); gfx.fillRect(x, 2, w, t.h - 4) end
			text(f, s, x + floor((w - f:getTextWidth(s)) / 2), hud.tune.labelTop, miss)
		end
		plateEnd(verdictPlate)
	end
	verdictPlate.img:draw(t.x, t.y)
end

local planPlate
-- kind: "baton" | "kubb"; value: the tilt in degrees (baton, one decimal) or
-- the spin in steps (kubb), negative = left. Nothing at 0: TILT L 5°,
-- TILT R 2.5°, SPIN L 2. A flag in the cut flag's place, widening to the
-- left; the string is made only when kind or value changes.
function hud.planChip(kind, value)
	if not value or value == 0 then return end
	local t = hud.tune.planChip
	local sh = hud.tune.shadow
	local P = planPlate
	if not P or P.k1 ~= kind or P.k2 ~= value or not hud.tune.cache then
		local f = hud.labelFont()
		local s
		if kind == "kubb" then
			s = string.format("SPIN %s %d", value < 0 and "L" or "R", floor(abs(value) + 0.5))
		else
			local v = floor(abs(value) * 10 + 0.5)
			s = string.format("TILT %s %d", value < 0 and "L" or "R", v // 10)
			if v % 10 ~= 0 then s = s .. "." .. (v % 10) end
		end
		local deg = (kind ~= "kubb")
		local tw_ = f:getTextWidth(s) + (deg and 5 or 0)
		local w = max(t.w, tw_ + 10)
		if not P or P.w ~= w + sh then
			P = newPlate(t.x, t.y, w + sh, t.h + sh)
			planPlate = P
		end
		P.x = t.x + t.w - w
		P.k1, P.k2 = nil, nil   -- (plateBegin below sets them and redraws)
		P.s, P.deg, P.tw = s, deg, tw_
	end
	if plateBegin(P, kind, value) then
		local w = P.w - sh
		plaque(0, 0, w, t.h)
		local f = hud.labelFont()
		local x = floor((w - P.tw) / 2)
		text(f, P.s, x, hud.tune.labelTop)
		-- the degree sign (the font has none): a 3 px ring, as on the loft plaque
		if P.deg then gfx.drawRect(x + f:getTextWidth(P.s) + 1, hud.tune.labelTop + 1, 3, 3) end
		plateEnd(P)
	end
	P.img:draw(P.x, P.y)
end

-- A card in the middle of the screen over the world: a title line and up to
-- two more (nil to skip). The whole card is one cached image per set of
-- strings, so a frame showing it costs one image draw.
local cards, ncards = {}, 0
function hud.card(title, line2, line3)
	-- looked up by the strings themselves (no key string built per frame)
	local k2, k3 = line2 or "", line3 or ""
	local c = cards[title] and cards[title][k2] and cards[title][k2][k3]
	if not c then
		if ncards >= 8 then cards, ncards = {}, 0 end
		local lines = { title, line2, line3 }
		local w, h = 0, 0
		local sizes = {}
		for i = 1, 3 do
			if lines[i] then
				local lw, lh = gfx.getTextSize(lines[i])
				sizes[i] = { lw, lh }
				w = max(w, lw)
				h = h + lh + (i > 1 and hud.tune.cardGap or 0)
			end
		end
		local pad = hud.tune.cardPad
		local bw, bh = w + 2 * pad, h + 2 * pad
		local img = gfx.image.new(bw, bh, CLEAR)
		gfx.pushContext(img)
		gfx.setColor(gfx.kColorWhite)
		gfx.fillRoundRect(0, 0, bw, bh, 4)
		gfx.setColor(gfx.kColorBlack)
		gfx.setLineWidth(2)
		gfx.drawRoundRect(1, 1, bw - 2, bh - 2, 4)
		gfx.setLineWidth(1)
		local y = pad
		for i = 1, 3 do
			if lines[i] then
				gfx.drawText(lines[i], floor((bw - sizes[i][1]) / 2), y)
				y = y + sizes[i][2] + hud.tune.cardGap
			end
		end
		gfx.popContext()
		c = { img = img, w = bw, h = bh }
		cards[title] = cards[title] or {}
		cards[title][k2] = cards[title][k2] or {}
		cards[title][k2][k3] = c
		ncards = ncards + 1
	end
	c.img:draw(floor((camera.SCREEN_W - c.w) / 2), floor((camera.SCREEN_H - c.h) / 2) - hud.tune.cardRise)
end

function hud.crankPrompt()
	playdate.ui.crankIndicator:draw()
end

tw.render.hud = hud
