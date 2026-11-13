-- HUD, in the Woodcut look (docs/design/README.md "HUD", boards/HUD.png):
-- a black rail on top, plaques along the bottom, nothing in the middle.
--
--   rail      0 0 400 14, always: pennant, team name, baton or kubb pips
--             (hollow = thrown, underlined = this one), the targets on the right
--   prompt    316 158 70 15, aiming: what to do next; white on black for FLICK
--   gauge     disc at 346 205, r 27, aiming: the arm turning with the crank, the
--             wind-up arc, the full-power mark, a drill's band as a grey wedge
--   plaque    250 199 62 34, aiming: the loft and the wind-up's power bar
--   cut flag  250 182 62 15, drilling while A or B is held
--   minimap   frame 4 162 49 76, always
--   chip      318 203 76 32 and the result flag 318 185 76 15, after a release
--   callout   59 185 234 48, after a drilled kubb stops: SHORT / ON / LONG
-- Everything else stays out of the clear area (the full width down to y 156,
-- then x 58 to 246 down to y 222).
--
-- Speed (AGENTS.md, "Drawing speed"): a graphics call costs 20 to 50 us on the
-- device and a line of text about 0.6 ms. The rail and every plaque is an
-- image drawn again only when a value it shows changes, so a normal frame
-- makes no text call. The gauge and the minimap are layers: drawn straight to
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
local floor, cos, sin, rad, max, min, abs = math.floor, math.cos, math.sin, math.rad, math.max, math.min, math.abs
local CLEAR <const>, BLACK <const>, WHITE <const> = gfx.kColorClear, gfx.kColorBlack, gfx.kColorWhite

tw.render = tw.render or {}
local hud = {}

hud.tune = {
	-- Labels: Roobert 10 Bold from the system, capitals only (DESIGN "Type").
	labelFont = "/System/Fonts/Roobert-10-Bold.pft",
	-- THE DISPLAY FONT HOOK: big numbers and words (the power chip's percent,
	-- the drill callout's verdict). The cut wood-type face is being made; swap
	-- this one path for it. Until then a system Roobert.
	displayFont = "/System/Fonts/Roobert-20-Medium.pft",
	labelTop = 2,       -- px from a label's box top to its font's cell top (centres the caps)
	displayTop = -2,    -- the same for the display font in the chip and the callout
	shadow = 2,         -- px the plaques' drop shadow sits right and down
	rail = { h = 14, pennantX = 4, nameX = 17, pipsX = 188, rightX = 395, gap = 6, dotGap = 4 },
	prompt = { x = 316, y = 158, w = 70, h = 15 },
	gauge = { x = 346, y = 205, r = 27, halo = 2, track = 22, arcW = 6, arm = 21, knob = 4, hub = 3,
		bandIn = 12, tickOut = 6 },
	plaque = { x = 250, y = 199, w = 62, h = 34 },
	cutFlag = { x = 250, y = 182, w = 62, h = 15 },
	chip = { x = 318, y = 203, w = 76, h = 32 },
	flag = { x = 318, y = 185, w = 76, h = 15 },
	callout = { x = 59, y = 185, w = 234, h = 48, block = 66, rulerW = 144, rulerBands = 3 },
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

-- ---------- layers (gauge, minimap) ----------

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
	cutPlate = cutPlate or newPlate(t.x, t.y, t.w + hud.tune.shadow, t.h + hud.tune.shadow)
	if plateBegin(cutPlate, s) then
		flagIn(0, 0, t.w, t.h, s, false)
		plateEnd(cutPlate)
	end
	cutPlate.img:draw(t.x, t.y)
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

-- ---------- the loft and power plaque ----------

local loftPlate
-- loftDeg; cap: the wind-up's power cap (0..1) or nil; band, half: a drill's
-- band (power units) or nil.
function hud.plaque(loftDeg, cap, band, half)
	local t = hud.tune.plaque
	local sh = hud.tune.shadow
	loftPlate = loftPlate or newPlate(t.x, t.y, t.w + sh, t.h + sh)
	local deg = floor(loftDeg + 0.5)
	local bh = 22
	local fill = cap and floor(bh * min(1, cap) + 0.5) or 0
	band = band or false
	if plateBegin(loftPlate, deg, band, half) then
		plaque(0, 0, t.w, t.h)
		-- the loft: the ground, the throw's angle and an arc between them
		local bx, by = 6, 27
		local a = rad(deg)
		gfx.setLineWidth(2)
		gfx.drawLine(bx, by, bx + 18, by)
		gfx.drawLine(bx, by, bx + floor(19 * cos(a) + 0.5), by - floor(19 * sin(a) + 0.5))
		gfx.setLineWidth(1)
		gfx.drawArc(bx, by, 13, 90 - deg, 90)
		local f = hud.labelFont()
		local s = tostring(deg)
		local tx, ty = 25, 9 + hud.tune.labelTop
		text(f, s, tx, ty)
		-- the degree sign (the font has none): a 3 px ring
		gfx.drawRect(tx + f:getTextWidth(s) + 1, ty + 1, 3, 3)
		-- the power bar (its fill is drawn over the image, below)
		local x, y = 50, 6
		gfx.drawRect(x, y, 6, bh)
		if band then
			local c = y + bh - floor(bh * band + 0.5)
			gfx.setPattern(GREY)
			gfx.fillRect(x - 2, c - 3, 10, 6)
			gfx.setColor(BLACK)
			gfx.drawRect(x - 2, c - 3, 10, 6)
		end
		plateEnd(loftPlate)
	end
	loftPlate.img:draw(t.x, t.y)
	-- the wind-up's cap fills the bar from the bottom: one rectangle a frame,
	-- inside the bar's frame so a drill band's block still shows either side
	if fill > 0 then
		gfx.setColor(BLACK)
		gfx.fillRect(t.x + 51, t.y + 6 + bh - fill, 4, fill)
	end
end

-- ---------- after the release: the power chip and the result flag ----------

local chipPlate, flagPlate
-- power: the throw's power (0..1); band, half: a drill's band or nil.
function hud.chip(power, band, half)
	local t = hud.tune.chip
	local sh = hud.tune.shadow
	chipPlate = chipPlate or newPlate(t.x, t.y, t.w + sh, t.h + sh)
	local pct = floor((power or 0) * 100 + 0.5)
	band = band or false
	if plateBegin(chipPlate, pct, band, half) then
		plaque(0, 0, t.w, t.h)
		local f = hud.displayFont()
		local x, y, bh = t.w - 10, 6, 20
		-- the percent, centred in the room left of the bar
		local s = pct .. "%"
		text(f, s, max(3, floor((x - f:getTextWidth(s)) / 2)), floor((t.h - f:getHeight()) / 2) + hud.tune.displayTop + 2)
		gfx.drawRect(x, y, 6, bh)
		local fill = floor(bh * min(1, pct / 100) + 0.5)
		if fill > 0 then gfx.fillRect(x, y + bh - fill, 6, fill) end
		if band then
			local c = y + bh - floor(bh * band + 0.5)
			gfx.setPattern(GREY)
			gfx.fillRect(x - 2, c - 3, 10, 6)
			gfx.setColor(BLACK)
			gfx.drawRect(x - 2, c - 3, 10, 6)
		end
		plateEnd(chipPlate)
	end
	chipPlate.img:draw(t.x, t.y)
end

-- s: the result in 12 characters or fewer (hud.short), or nil.
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
		P.x = min(t.x, 398 - sh - w)
	end
	if plateBegin(P, s) then
		flagIn(0, 0, P.w - sh, t.h, s, false)
		plateEnd(P)
	end
	P.img:draw(P.x, P.y)
end

-- The match's result line (core/match m.text) as a flag: its first part,
-- 12 characters or fewer. Once per throw, not per frame.
local SHORT = {
	{ "^king down early", "KING EARLY" }, { "^king down", "KING DOWN" }, { "^resigned", "RESIGNED" },
	{ "^missed the king", "KING STANDS" }, { "^missed", "MISS" }, { "^helicopter", "HELICOPTER" },
	{ "^own%-half kubb hit", "PUT BACK" }, { "^own half hit", "OWN HALF" },
	{ "^kubb in for now", "IN FOR NOW" }, { "^kubb out for now", "OUT FOR NOW" },
	{ "^kubb in", "IN" }, { "^all in", "ALL IN" }, { "^kubb out: rethrown", "RETHROW" },
	{ "^(%d+) out: rethrown", "%1 RETHROWS" }, { "^out twice", "PUNISHMENT" },
	{ "^(%d+) punishment", "%1 PUNISHED" }, { "^on a kubb", "LOWERED" }, { "rescue", "RESCUE" },
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

-- ---------- the drill result callout ----------

local calloutPlate
-- verdict "short" | "on" | "long"; err: power - band; half: the band's half
-- width; cm: how far from the marker the kubb came to rest.
function hud.callout(verdict, err, half, cm)
	local t = hud.tune.callout
	local sh = hud.tune.shadow
	calloutPlate = calloutPlate or newPlate(t.x, t.y, t.w + sh, t.h + sh)
	local u = err / (half * t.rulerBands)
	if u < -1 then u = -1 elseif u > 1 then u = 1 end
	local uq = floor(u * 72 + 0.5)
	if plateBegin(calloutPlate, verdict, uq, cm) then
		plaque(0, 0, t.w, t.h)
		local df, lf = hud.displayFont(), hud.labelFont()
		local v = string.upper(verdict or "")
		-- the verdict's black block widens for a wide word; the ruler takes the rest
		local block = max(t.block, df:getTextWidth(v) + 12)
		local rw = min(t.rulerW, t.w - block - 20)
		local px = floor(rw / 2 + uq / 72 * rw / 2 + 0.5)
		gfx.fillRect(0, 0, block, t.h)
		text(df, v, floor((block - df:getTextWidth(v)) / 2), floor((t.h - df:getHeight()) / 2) + hud.tune.displayTop + 2, true)
		local rx, ry = block + 11, 17
		gfx.drawRect(rx, ry, rw, 8)
		local third = floor(rw / t.rulerBands + 0.5)
		gfx.fillRect(rx + floor((rw - third) / 2), ry, third, 8)
		local cx = rx + px
		gfx.fillPolygon(cx, ry - 2, cx - 5, ry - 10, cx + 5, ry - 10)
		local ly = ry + 11 + hud.tune.labelTop - 2
		text(lf, "SHORT", rx, ly)
		-- the distance, centred between the two words (a metre or more in metres)
		local d = (cm < 100) and (cm .. " CM") or string.format("%.1f M", cm / 100)
		local ws, wl = lf:getTextWidth("SHORT"), lf:getTextWidth("LONG")
		text(lf, d, rx + ws + floor((rw - ws - wl - lf:getTextWidth(d)) / 2), ly)
		text(lf, "LONG", rx + rw - wl, ly)
		plateEnd(calloutPlate)
	end
	calloutPlate.img:draw(t.x, t.y)
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

-- The debug readout text for a throw: power, smoothness, tilt,
-- LEGAL/HELICOPTER, distance. Built once per throw, not per frame.
-- r.down (kubbs toppled by the throw) is added when the physics gave it.
-- The readout for a drill: power against the band and the verdict,
-- smoothness, the cut, and how far from the marker it first landed / came
-- to rest.
function hud.drillReadoutText(r)
	local function off(x, y)
		if not x then return 0 end
		return math.sqrt((x - r.markerX) ^ 2 + (y - r.markerY) ^ 2)
	end
	local cut = (r.cut or 0) > 0 and "R" or ((r.cut or 0) < 0 and "L" or "-")
	return string.format("P %.2f/%.2f %s  S %.2f  cut %s  off %.2f/%.2f m",
		r.power, r.band, string.upper(r.verdict or ""), r.smoothness, cut, off(r.landX, r.landY), off(r.restX, r.restY))
end

function hud.readoutText(r)
	local s = string.format("P %.2f  S %.2f  tilt %d  %s  %.2f m",
		r.power, r.smoothness, floor(r.tilt + 0.5), r.legal and "LEGAL" or "HELICOPTER", r.distance or 0)
	if r.down then s = s .. string.format("  down %d", r.down) end
	return s
end

-- The readout, just under the rail at the left (only with "Readout" on).
function hud.readout(s)
	local t = hud.tune
	local b = textBox(s, 2, 2, 2, 1)
	b.img:draw(t.readoutX - 2, t.readoutY - 2)
end

-- ---------- the throw gauge ----------

local gt = hud.tune.gauge
local gaugeLayer = newLayer(gt.x - gt.r - gt.tickOut - 2, gt.y - gt.r - gt.tickOut - 2,
	gt.x + gt.r + gt.tickOut + 2, 239)
local gaugeKey = {}
local discImg, discKey1, discKey2, discKey3 = nil, nil, nil, nil
local dx0, dy0 = gaugeLayer.x, gaugeLayer.y

-- the point at radius r for a backswing of `deg` degrees (0 = straight down,
-- winding back turns it to the left and up)
local function onDial(cx, cy, r, deg)
	local a = rad(deg)
	return cx - r * sin(a), cy + r * cos(a)
end

-- The disc: what changes only with the full-power backswing or a drill's band.
local function drawDisc(cx, cy, fullDeg, band, half)
	local t = hud.tune.gauge
	local r = t.r
	gfx.setColor(WHITE)
	gfx.fillCircleAtPoint(cx, cy, r + t.halo)
	gfx.setColor(BLACK)
	gfx.fillCircleAtPoint(cx, cy, r)
	-- the track the wind-up arc runs on: a dotted white ring
	gfx.setColor(WHITE)
	local tr = t.track
	local nd = floor(2 * math.pi * tr / 4)
	for i = 0, nd - 1 do
		local a = 2 * math.pi * i / nd
		gfx.drawPixel(floor(cx + tr * sin(a) + 0.5), floor(cy + tr * cos(a) + 0.5))
	end
	if band then
		-- the band: a grey wedge from radius bandIn to the rim, a white edge,
		-- and a black tick outside the rim at each end
		local lo, hi = max(0, band - half) * fullDeg, min(1, band + half) * fullDeg
		local ax, ay = onDial(cx, cy, t.bandIn, lo)
		local bx, by = onDial(cx, cy, r, lo)
		local mx, my = onDial(cx, cy, r, (lo + hi) / 2)
		local ex, ey = onDial(cx, cy, r, hi)
		local fx, fy = onDial(cx, cy, t.bandIn, hi)
		gfx.setPattern(GREY)
		gfx.fillPolygon(ax, ay, bx, by, mx, my, ex, ey, fx, fy)
		gfx.setColor(WHITE)
		gfx.drawPolygon(ax, ay, bx, by, mx, my, ex, ey, fx, fy)
		gfx.setColor(BLACK)
		gfx.setLineWidth(2)
		for k = 1, 2 do
			local d = (k == 1) and lo or hi
			local x0, y0 = onDial(cx, cy, r + 1, d)
			local x1, y1 = onDial(cx, cy, r + t.tickOut, d)
			gfx.drawLine(x0, y0, x1, y1)
		end
		gfx.setColor(WHITE)
	end
	-- the full-power mark, near the rim at the full backswing (10 o'clock)
	gfx.setLineWidth(3)
	local x0, y0 = onDial(cx, cy, r - 7, fullDeg)
	local x1, y1 = onDial(cx, cy, r - 1, fullDeg)
	gfx.drawLine(x0, y0, x1, y1)
	gfx.setLineWidth(1)
	-- the start: a white triangle at the bottom, pointing up
	gfx.fillPolygon(cx, cy + r - 1, cx - 3, cy + r - 7, cx + 3, cy + r - 7)
	gfx.setColor(BLACK)
end

-- The throw gauge (aiming only): the throwing arm seen from the side,
-- turning with the crank, so the player sees which way is the wind-up, how
-- far back counts as full power and the moment the baton leaves.
--   phase: the swing phase ("idle" | "winding" | "swinging")
--   angle: forward degrees from the start of the wind-up (negative = wound back)
--   backswing: degrees wound back; fullDeg: the backswing that allows full power
--   crank: where the crank really is, forward degrees from the bottom. While
--   idle the arm shows it, and an arrow shows the way back to wind up (the
--   wind-up only starts when the crank crosses the bottom going back).
--   band, half: a drill's target band (power units: the backswing that caps
--   power there), drawn as a grey wedge; nil for a baton.
-- Returns the prompt for the flag over it and whether it is inverted.
function hud.gauge(phase, angle, backswing, fullDeg, crank, band, half)
	local t = hud.tune.gauge
	local cx, cy, r = t.x, t.y, t.r
	local idle = (phase == "idle")
	local behind = idle and crank < -3   -- the crank sits on the wind-up side: bring it down first
	local K = gaugeKey
	local ang = idle and crank or angle
	band = band or false
	local same = K[1] == phase and K[2] == ang and K[3] == backswing and K[4] == fullDeg and K[6] == band
		and K[7] == half
	K[1], K[2], K[3], K[4], K[6], K[7] = phase, ang, backswing, fullDeg, band, half
	local ox, oy = begin(gaugeLayer, same)
	if ox then
		-- the disc, from its own image
		if not discImg or discKey1 ~= fullDeg or discKey2 ~= band or discKey3 ~= half or not hud.tune.cache then
			discImg = discImg or gfx.image.new(gaugeLayer.w, gaugeLayer.h, CLEAR)
			discImg:clear(CLEAR)
			gfx.pushContext(discImg)
			drawDisc(cx - dx0, cy - dy0, fullDeg, band, half)
			gfx.popContext()
			discKey1, discKey2, discKey3 = fullDeg, band, half
		end
		discImg:draw(dx0, dy0)
		local x, y = cx + ox, cy + oy
		gfx.setColor(WHITE)
		-- the wind-up so far: a thick white arc on the track (drawArc: 0 = up,
		-- clockwise; straight down = 180)
		if backswing > 1 then
			gfx.setLineWidth(t.arcW)
			gfx.drawArc(x, y, t.track, 180, 180 + min(backswing, 180))
			-- the start mark turns black on the arc
			gfx.setColor(BLACK)
			gfx.fillPolygon(x, y + r - 1, x - 3, y + r - 7, x + 3, y + r - 7)
			gfx.setColor(WHITE)
		end
		if idle and not behind then
			-- the arrow: turn back (to the left of the bottom) to wind up
			gfx.setLineWidth(2)
			gfx.drawArc(x, y, 16, 202, 245)
			gfx.fillPolygon(x - 19, y + 7, x - 11, y + 6, x - 16, y - 1)
		end
		-- the arm, the hand (a knob) and the hub
		local ka = -ang
		local kx, ky = onDial(x, y, t.arm, ka)
		gfx.setLineWidth(3)
		gfx.drawLine(x, y, kx, ky)
		gfx.setLineWidth(1)
		gfx.fillCircleAtPoint(kx, ky, t.knob)
		if not idle then
			gfx.setColor(BLACK)
			gfx.drawCircleAtPoint(kx, ky, t.knob)
			gfx.setColor(WHITE)
		end
		gfx.fillCircleAtPoint(x, y, t.hub)
		gfx.setColor(BLACK)
		finish(gaugeLayer)
	end
	gfx.setColor(BLACK)
	gfx.setLineWidth(1)
	-- what to do next (12 characters at most)
	if phase == "swinging" then return nil end
	if phase == "winding" and band then
		local p = backswing / fullDeg
		if p < band - half then return "WIND TO BAND", false end
		if p <= band + half then return "FLICK!", true end
		return "EASE OFF", false
	elseif phase == "winding" then
		if backswing >= fullDeg then return "FLICK!", true end
		return "WIND BACK", false
	end
	if behind then return "CRANK DOWN", false end
	return band and "WIND TO BAND" or "WIND BACK", false
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
