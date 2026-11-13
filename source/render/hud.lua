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
	gaugeX = 200, gaugeY = 198, gaugeR = 30,               -- throw gauge: arm pivot and arm length
	gaugeFollowDeg = 70,                                   -- arm angle shown after the release
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
	if not thrown and backswing > 1 then
		gfx.setLineWidth(5)
		gfx.drawArc(cx, cy, r + 3, 180, 180 + min(backswing, 180))
	end
	local idle = (phase == "idle") and not thrown
	local behind = idle and crank < -3   -- the crank sits on the wind-up side: bring it down first
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
	-- the arm, and the baton in the hand until it is thrown
	local a = rad(thrown and t.gaugeFollowDeg or (idle and 0 or angle))
	local sx, sy = sin(a), cos(a)
	gfx.setLineWidth(2)
	gfx.drawLine(cx, cy, cx + (r - 8) * sx, cy + (r - 8) * sy)
	gfx.fillCircleAtPoint(cx, cy, 3)
	if not thrown then
		gfx.setLineWidth(5)
		gfx.drawLine(cx + (r - 12) * sx, cy + (r - 12) * sy, cx + (r + 1) * sx, cy + (r + 1) * sy)
	end
	gfx.setLineWidth(1)
	local label
	if thrown then
		label = (legal and "*THROWN* " or "*HELICOPTER* ") .. floor((power or 0) * 100 + 0.5) .. "%"
	elseif phase == "swinging" then
		label = nil
	elseif phase == "winding" then
		label = (backswing >= fullDeg) and "*FULL: flick forward!*" or "*flick forward to throw*"
	else
		label = behind and "*bring the crank to the bottom*" or "*crank back past the bottom*"
	end
	if label then
		local w, h = gfx.getTextSize(label)
		local lx, ly = cx - floor(w / 2), cy - r - 12 - h
		gfx.setColor(gfx.kColorWhite)
		gfx.fillRect(lx - 3, ly - 2, w + 6, h + 3)
		gfx.setColor(gfx.kColorBlack)
		gfx.drawRect(lx - 3, ly - 2, w + 6, h + 3)
		gfx.drawText(label, lx, ly)
	end
end

function hud.crankPrompt()
	playdate.ui.crankIndicator:draw()
end

tw.render.hud = hud
