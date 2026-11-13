-- HUD: the minimap (DESIGN 3), loft gauge, wind-up/power meter, the debug
-- readout line and the crank prompt.
--
-- Speed (AGENTS.md, "Drawing speed"): text and the HUD's many small shapes
-- cost milliseconds a frame on the device, so each part is a layer: drawn
-- straight to the screen while its inputs change from frame to frame, and
-- once a frame repeats the last frame's inputs, drawn into an image that is
-- then copied until an input changes. Text boxes are cached as images by
-- their string. A layer image is filled through gfx.setDrawOffset, so the
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
local floor, cos, sin, rad, max, min = math.floor, math.cos, math.sin, math.rad, math.max, math.min
local CLEAR <const> = gfx.kColorClear

tw.render = tw.render or {}
local hud = {}

hud.tune = {
	panelX = 4, panelY = 194, panelW = 76, panelH = 42,  -- loft + power panel, bottom left
	readoutX = 4, readoutY = 3,                            -- debug readout, top left
	statusGap = 1,                                         -- px between the match status lines
	cardPad = 10, cardGap = 6, cardRise = 20,              -- hand-off and winner card: padding,
	                                                       -- line gap, px above screen center
	gaugeX = 200, gaugeY = 198, gaugeR = 30,               -- throw gauge: arm pivot and arm length
	gaugeFollowDeg = 70,                                   -- arm angle shown after the release
	cache = true,                                          -- cache unchanged parts as images
}

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
-- maps them into it, which keeps the pixels exactly those of the screen:
-- shifting float coordinates in Lua instead moves thick lines and circles
-- by a pixel).
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

-- A boxed text label: white box, black frame, the text inside, with its
-- top-left text pixel at (x, y). Cached as an image per string.
local boxes, nboxes = {}, 0
local function textBox(s, x, y, padL, padT, padR, padB)
	local key = s
	local b = boxes[key]
	if not b then
		if nboxes >= 32 then boxes, nboxes = {}, 0 end
		local w, h = gfx.getTextSize(s)
		local bw, bh = w + padL + padR, h + padT + padB
		local img = gfx.image.new(bw, bh, CLEAR)
		gfx.pushContext(img)
		gfx.setColor(gfx.kColorWhite)
		gfx.fillRect(0, 0, bw, bh)
		gfx.setColor(gfx.kColorBlack)
		gfx.setLineWidth(1)
		gfx.drawRect(0, 0, bw, bh)
		gfx.drawText(s, padL, padT)
		gfx.popContext()
		b = { img = img, w = w, h = h }
		boxes[key] = b
		nboxes = nboxes + 1
	end
	return b
end

-- Text without a box, cached the same way (transparent around the glyphs).
local texts, ntexts = {}, 0
local function textImage(s)
	local t = texts[s]
	if not t then
		if ntexts >= 32 then texts, ntexts = {}, 0 end
		local w, h = gfx.getTextSize(s)
		local img = gfx.image.new(w, h, CLEAR)
		gfx.pushContext(img)
		gfx.drawText(s, 0, 0)
		gfx.popContext()
		t = img
		texts[s] = t
		ntexts = ntexts + 1
	end
	return t
end

local function dot(x, y, size, ox, oy)
	local sx, sy = camera.toMinimap(x, y)
	gfx.fillRect(floor(sx - size / 2 + 0.5) + ox, floor(sy - size / 2 + 0.5) + oy, size, size)
end

local mm = camera.minimap
local mapLayer = newLayer(mm.ox - 3, mm.oy - 3, mm.ox + mm.w + 3, mm.oy + mm.h + 3)
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
		gfx.setColor(gfx.kColorWhite)
		gfx.fillRect(ox - 3 + dx, oy - 3 + dy, w + 7, h + 7)
		gfx.setColor(gfx.kColorBlack)
		gfx.setLineWidth(1)
		gfx.drawRect(ox - 3 + dx, oy - 3 + dy, w + 7, h + 7)
		gfx.drawRect(ox + dx, oy + dy, w + 1, h + 1)
		for x = 0, w, 3 do gfx.drawPixel(ox + x + dx, oy + h / 2 + dy) end
		-- the advantage line: every other pixel, a row of its own
		if adv then
			local _, ay = camera.toMinimap(0, adv)
			ay = floor(ay + 0.5)
			for x = 0, w, 2 do gfx.drawPixel(ox + x + dx, ay + dy) end
		end
		-- base kubbs sit on the baselines; their dots are drawn just inside so
		-- they do not merge with the minimap's edge
		-- toppled pieces are a single pixel
		for i = 1, np do
			local p = pieces[i]
			local y = p.y
			if y >= 8 then y = 7.8 elseif y <= 0 then y = 0.2 end
			dot(p.x, y, p.toppled and 1 or (p.king and 3 or 2), dx, dy)
		end
		finish(mapLayer)
	end
	gfx.setColor(gfx.kColorBlack)
	gfx.setLineWidth(1)
	-- aim line from the player to the full-power landing point
	local px, py = camera.toMinimap(state.playerX, state.lineY)
	if state.aimX then
		-- clipped to the minimap's frame (a full-power preview can land past
		-- the far baseline or the sidelines)
		local x0, y0, x1, y1 = state.playerX, state.lineY, state.aimX, state.aimY
		local t = 1
		local ymax, xmax = 8 + 2 / m.scale, 2.5 + 2 / m.scale
		if y1 > ymax then t = min(t, (ymax - y0) / (y1 - y0)) end
		if x1 > xmax then t = min(t, (xmax - x0) / (x1 - x0)) end
		if x1 < -xmax then t = min(t, (-xmax - x0) / (x1 - x0)) end
		local ax, ay = camera.toMinimap(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)
		gfx.drawLine(px, py, ax, ay)
	end
	-- the player: a 3 px block just behind the line
	gfx.fillRect(floor(px - 1 + 0.5), floor(py + 1), 3, 3)
	if state.landX then
		local lx, ly = camera.toMinimap(state.landX, state.landY)
		gfx.drawLine(lx - 2, ly - 2, lx + 2, ly + 2)
		gfx.drawLine(lx - 2, ly + 2, lx + 2, ly - 2)
	end
	if state.baton then
		dot(state.baton.x, state.baton.y, 2, 0, 0)
	end
end

local pt = hud.tune
local panelLayer = newLayer(pt.panelX - 2, pt.panelY - 2, pt.panelX + pt.panelW + 2, pt.panelY + pt.panelH + 2)
local panelKey = {}

-- Loft gauge and wind-up/power meter in one small panel.
--   loftDeg, loftMin, loftMax
--   cap: power cap from the current backswing (0..1) while winding, or nil
--   power: the last throw's power (0..1), or nil
function hud.panel(loftDeg, loftMin, loftMax, cap, power)
	local K = panelKey
	local same = K[1] == loftDeg and K[2] == loftMin and K[3] == loftMax and K[4] == cap and K[5] == power
	K[1], K[2], K[3], K[4], K[5] = loftDeg, loftMin, loftMax, cap, power
	local ox, oy = begin(panelLayer, same)
	if not ox then return end
	local t = hud.tune
	local x, y, w, h = t.panelX + ox, t.panelY + oy, t.panelW, t.panelH
	gfx.setColor(gfx.kColorWhite)
	gfx.fillRoundRect(x, y, w, h, 3)
	gfx.setColor(gfx.kColorBlack)
	gfx.setLineWidth(1)
	gfx.drawRoundRect(x, y, w, h, 3)
	-- loft: a dial from the ground line, the loft range as an arc and a needle
	-- at the loft angle; the angle in degrees beside it
	local cx, cy, r = x + 5, y + h - 6, 30
	gfx.drawLine(cx, cy, cx + r, cy)
	gfx.drawArc(cx, cy, r, 90 - loftMax, 90 - loftMin) -- arc angles: 0 = up, clockwise
	local a = rad(loftDeg)
	gfx.setLineWidth(2)
	gfx.drawLine(cx, cy, cx + (r + 2) * cos(a), cy - (r + 2) * sin(a))
	gfx.setLineWidth(1)
	textImage(tostring(floor(loftDeg + 0.5))):draw(x + 38, y + 4)
	-- meter: a vertical bar on the right; the cap (backswing) as a pattern,
	-- the thrown power solid
	local mx, my, mw, mh = x + w - 13, y + 5, 8, h - 10
	gfx.drawRect(mx, my, mw, mh)
	if cap and cap > 0 then
		local ch = floor((mh - 2) * min(1, cap) + 0.5)
		gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer2x2)
		gfx.fillRect(mx + 1, my + mh - 1 - ch, mw - 2, ch)
		gfx.setColor(gfx.kColorBlack)
	end
	if power and power > 0 then
		local ph = floor((mh - 2) * min(1, power) + 0.5)
		gfx.fillRect(mx + 1, my + mh - 1 - ph, mw - 2, ph)
	end
	finish(panelLayer)
end

-- The debug readout text for a throw: power, smoothness, tilt,
-- LEGAL/HELICOPTER, distance. Built once per throw, not per frame.
-- r.down (kubbs toppled by the throw) is added when the physics gave it.
function hud.readoutText(r)
	local s = string.format("P %.2f  S %.2f  tilt %d  %s  %.2f m",
		r.power, r.smoothness, floor(r.tilt + 0.5), r.legal and "LEGAL" or "HELICOPTER", r.distance or 0)
	if r.down then s = s .. string.format("  down %d", r.down) end
	return s
end

-- `y` (optional) moves it down (the match puts its status lines above it).
function hud.readout(s, y)
	local t = hud.tune
	-- box: (x - 2, y - 2), text width + 4 by text height + 3
	local b = textBox(s, 0, 0, 2, 2, 2, 1)
	b.img:draw(t.readoutX - 2, (y or t.readoutY) - 2)
end

-- The match status, top left: whose turn and what is thrown (`label`), and
-- under it what the last throw did (`result`, or nil). Each line is a text
-- box cached by its string, so a frame costs two image draws.
function hud.status(label, result)
	local t = hud.tune
	local b = textBox(label, 0, 0, 2, 2, 2, 1)
	b.img:draw(t.readoutX - 2, t.readoutY - 2)
	if result then
		local r = textBox(result, 0, 0, 2, 2, 2, 1)
		r.img:draw(t.readoutX - 2, t.readoutY - 2 + b.h + t.statusGap)
	end
end

-- The y of a line under the status lines (for the readout).
function hud.belowStatus(lines)
	local t = hud.tune
	local _, h = gfx.getTextSize("A")
	return t.readoutY + lines * (h + 3 + t.statusGap)
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

-- A label centered over x in a box: (lx - 3, ly - 2), text width + 6 by
-- text height + 3, the text at (lx, ly).
local function label(s, cx, top)
	local b = textBox(s, 0, 0, 3, 2, 3, 1)
	local lx, ly = cx - floor(b.w / 2), top(b.h)
	b.img:draw(lx - 3, ly - 2)
end

local gt = hud.tune
local gaugeLayer = newLayer(gt.gaugeX - 40, gt.gaugeY - 40, gt.gaugeX + 40, 239)
local gaugeKey = {}
local thrownTop = function(h) return camera.SCREEN_H - h - 4 end
local gaugeTop = function(h) return gt.gaugeY - gt.gaugeR - 12 - h end

-- The throw gauge: the throwing arm seen from the side, turning with the
-- crank, so the player sees which way is the wind-up, how far back counts as
-- full power and the moment the baton leaves.
--   phase: the swing phase ("idle" | "winding" | "swinging")
--   angle: forward degrees from the start of the wind-up (negative = wound back)
--   backswing: degrees wound back; fullDeg: the backswing that allows full power
--   thrown: the baton is in the air or just landed; legal, power: that throw
--   crank: where the crank really is, forward degrees from the bottom. While
--   idle it is drawn as a dimmed ghost on the rim: the wind-up only starts
--   when the crank crosses the bottom going back, and an arrow shows the way.
-- The arm hangs straight down at rest, winds back to the left and swings
-- forward to the right. A thick arc grows with the backswing up to the
-- full-power tick. The label under it says what to do next.
function hud.swingGauge(phase, angle, backswing, fullDeg, thrown, legal, power, crank)
	local t = hud.tune
	local cx, cy, r = t.gaugeX, t.gaugeY, t.gaugeR
	if thrown then
		-- the baton is away: only a small result label at the bottom, so the
		-- gauge does not cover the flight and the impact
		label((legal and "*THROWN* " or "*HELICOPTER* ") .. floor((power or 0) * 100 + 0.5) .. "%", cx, thrownTop)
		return
	end
	local idle = (phase == "idle") and not thrown
	local behind = idle and crank < -3   -- the crank sits on the wind-up side: bring it down first
	-- the dial: a layer keyed on what it shows
	local K = gaugeKey
	local ang = idle and 0 or angle
	local cr = idle and crank or false
	local same = K[1] == phase and K[2] == ang and K[3] == backswing and K[4] == fullDeg and K[5] == cr
	K[1], K[2], K[3], K[4], K[5] = phase, ang, backswing, fullDeg, cr
	local ox, oy = begin(gaugeLayer, same)
	if ox then
		local cx, cy = cx + ox, cy + oy
		gfx.setColor(gfx.kColorWhite)
		gfx.fillCircleAtPoint(cx, cy, r + 7)
		gfx.setColor(gfx.kColorBlack)
		gfx.setLineWidth(1)
		gfx.drawCircleAtPoint(cx, cy, r + 7)
		-- ticks: the start (straight down) and the full-power backswing
		gfx.drawLine(cx, cy + r + 1, cx, cy + r + 6)
		local fa = rad(-fullDeg)
		gfx.setLineWidth(3)
		gfx.drawLine(cx + (r - 1) * sin(fa), cy + (r - 1) * cos(fa), cx + (r + 6) * sin(fa), cy + (r + 6) * cos(fa))
		-- the backswing so far (drawArc: 0 = up, clockwise; straight down = 180)
		if backswing > 1 then
			gfx.setLineWidth(5)
			gfx.drawArc(cx, cy, r + 3, 180, 180 + min(backswing, 180))
		end
		if idle then
			-- the crank's real position: a dimmed dot on the rim and a dotted spoke
			local ca = rad(crank)
			local gx, gy = cx + (r + 1) * sin(ca), cy + (r + 1) * cos(ca)
			for i = 6, r - 4, 4 do gfx.drawPixel(cx + i * sin(ca), cy + i * cos(ca)) end
			gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer2x2)
			gfx.fillCircleAtPoint(gx, gy, 5)
			gfx.setColor(gfx.kColorBlack)
			gfx.drawCircleAtPoint(gx, gy, 5)
			if not behind then
				-- the arrow: turn back (to the left of the bottom) to wind up
				local a0, a1 = 14, 52
				gfx.setLineWidth(2)
				gfx.drawArc(cx, cy, r - 6, 180 + a0, 180 + a1)
				local ea = rad(-a1)
				local ex, ey = cx + (r - 6) * sin(ea), cy + (r - 6) * cos(ea)
				local ta = rad(-a1 + 16)
				gfx.drawLine(ex, ey, cx + (r - 11) * sin(ta), cy + (r - 11) * cos(ta))
				gfx.drawLine(ex, ey, cx + (r - 1) * sin(ta), cy + (r - 1) * cos(ta))
				gfx.setLineWidth(1)
			end
		end
		-- the arm, and the baton in the hand
		local a = rad(ang)
		local sx, sy = sin(a), cos(a)
		gfx.setLineWidth(2)
		gfx.drawLine(cx, cy, cx + (r - 8) * sx, cy + (r - 8) * sy)
		gfx.fillCircleAtPoint(cx, cy, 3)
		gfx.setLineWidth(5)
		gfx.drawLine(cx + (r - 12) * sx, cy + (r - 12) * sy, cx + (r + 1) * sx, cy + (r + 1) * sy)
		gfx.setLineWidth(1)
		finish(gaugeLayer)
	end
	gfx.setColor(gfx.kColorBlack)
	gfx.setLineWidth(1)
	local s
	if phase == "swinging" then
		s = nil
	elseif phase == "winding" then
		s = (backswing >= fullDeg) and "*FULL: flick forward!*" or "*flick forward to throw*"
	else
		s = behind and "*bring the crank to the bottom*" or "*crank back past the bottom*"
	end
	if s then label(s, cx, gaugeTop) end
end

function hud.crankPrompt()
	playdate.ui.crankIndicator:draw()
end

tw.render.hud = hud
