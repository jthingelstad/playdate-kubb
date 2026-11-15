-- Draw-call counting for the "drawcalls" self-test. On the device a
-- graphics call costs 20 to 50 us (AGENTS.md "Drawing speed"), so the number
-- of calls a frame makes is the figure to watch. Modules keep graphics
-- functions in locals when they are imported, so the wrapping must happen
-- before them: main.lua imports this file first, and it wraps only when the
-- Simulator was launched with selftest=drawcalls (or clock-gauge, which
-- counts the clock dial's calls).
import "CoreLibs/graphics"
import "core/tw"

tw.drawcount = { n = 0, text = 0, on = false }

local wanted = false
for _, a in ipairs(playdate.argv or {}) do
	if a == "selftest=drawcalls" or a == "selftest=clock-gauge" then wanted = true end
end

if wanted then
	local C = tw.drawcount
	C.on = true
	local gfx = playdate.graphics
	local names = {
		"drawLine", "fillPolygon", "drawPolygon", "fillRect", "drawRect", "fillRoundRect", "drawRoundRect",
		"drawArc", "fillCircleAtPoint", "drawCircleAtPoint", "drawPixel", "fillTriangle", "drawTriangle",
		"setColor", "setPattern", "setDitherPattern", "setLineWidth", "setLineCapStyle", "setImageDrawMode",
		"clear", "setFont", "setDrawOffset", "pushContext", "popContext",
	}
	for _, name in ipairs(names) do
		local f = gfx[name]
		if f then
			gfx[name] = function(...)
				C.n = C.n + 1
				return f(...)
			end
		end
	end
	local drawText = gfx.drawText
	gfx.drawText = function(...)
		C.n, C.text = C.n + 1, C.text + 1
		return drawText(...)
	end
	local img = gfx.image
	for _, name in ipairs { "draw", "drawIgnoringOffset" } do
		local f = img[name]
		if f then
			img[name] = function(...)
				C.n = C.n + 1
				return f(...)
			end
		end
	end
	local font = gfx.font
	if font and font.drawText then
		local f = font.drawText
		font.drawText = function(...)
			C.n, C.text = C.n + 1, C.text + 1
			return f(...)
		end
	end
end
