-- HUD: the minimap (DESIGN 3), loft gauge, wind-up/power meter, the debug
-- readout line and the crank prompt.
import "CoreLibs/graphics"
import "CoreLibs/ui"
import "core/tw"
import "core/camera"
import "render/world"

local gfx <const> = playdate.graphics
local camera = tw.camera
local floor, cos, sin, rad, max, min = math.floor, math.cos, math.sin, math.rad, math.max, math.min

tw.render = tw.render or {}
local hud = {}

hud.tune = {
	panelX = 4, panelY = 194, panelW = 76, panelH = 42,  -- loft + power panel, bottom left
	readoutX = 4, readoutY = 3,                            -- debug readout, top left
}

local function dot(x, y, size)
	local sx, sy = camera.toMinimap(x, y)
	gfx.fillRect(floor(sx - size / 2 + 0.5), floor(sy - size / 2 + 0.5), size, size)
end

-- state: playerX, lineY, aimX, aimY (aim preview landing), baton (or nil),
-- landX, landY (or nil)
function hud.minimap(state)
	local m = camera.minimap
	local ox, oy, w, h = m.ox, m.oy, m.w, m.h
	gfx.setColor(gfx.kColorWhite)
	gfx.fillRect(ox - 3, oy - 3, w + 7, h + 7)
	gfx.setColor(gfx.kColorBlack)
	gfx.setLineWidth(1)
	gfx.drawRect(ox - 3, oy - 3, w + 7, h + 7)
	gfx.drawRect(ox, oy, w + 1, h + 1)
	for x = 0, w, 3 do gfx.drawPixel(ox + x, oy + h / 2) end
	-- base kubbs sit on the baselines; their dots are drawn just inside so
	-- they do not merge with the minimap's edge
	local pieces = tw.render.world.pieces
	for i = 1, #pieces do
		local p = pieces[i]
		local y = p.y
		if y >= 8 then y = 7.8 elseif y <= 0 then y = 0.2 end
		dot(p.x, y, p.king and 3 or 2)
	end
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
		dot(state.baton.x, state.baton.y, 2)
	end
end

-- Loft gauge and wind-up/power meter in one small panel.
--   loftDeg, loftMin, loftMax
--   cap: power cap from the current backswing (0..1) while winding, or nil
--   power: the last throw's power (0..1), or nil
function hud.panel(loftDeg, loftMin, loftMax, cap, power)
	local t = hud.tune
	local x, y, w, h = t.panelX, t.panelY, t.panelW, t.panelH
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
	gfx.drawText(tostring(floor(loftDeg + 0.5)), x + 38, y + 4)
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
end

-- The debug readout text for a throw: power, smoothness, tilt,
-- LEGAL/HELICOPTER, distance. Built once per throw, not per frame.
function hud.readoutText(r)
	return string.format("P %.2f  S %.2f  tilt %d  %s  %.2f m",
		r.power, r.smoothness, floor(r.tilt + 0.5), r.legal and "LEGAL" or "HELICOPTER", r.distance or 0)
end

function hud.readout(s)
	local t = hud.tune
	local w, h = gfx.getTextSize(s)
	gfx.setColor(gfx.kColorWhite)
	gfx.fillRect(t.readoutX - 2, t.readoutY - 2, w + 4, h + 3)
	gfx.setColor(gfx.kColorBlack)
	gfx.drawRect(t.readoutX - 2, t.readoutY - 2, w + 4, h + 3)
	gfx.drawText(s, t.readoutX, t.readoutY)
end

function hud.crankPrompt()
	playdate.ui.crankIndicator:draw()
end

tw.render.hud = hud
