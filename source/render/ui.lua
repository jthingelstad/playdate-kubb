-- Shared pieces of the Woodcut look (docs/design/README.md "Type and voice")
-- for the title and the cards: the fonts and the ringed button glyph.
--
--   ui.display(16 | 32)   Throwing Wood Display, the cut wood-type face, at
--                         cap height 16 or 32 px (source/fonts; a bitmap of
--                         Londrina Solid Black under the SIL OFL, OFL.txt).
--                         Capitals, digits and ! . · % ° + - : , / ' ? only.
--   ui.label()            Roobert 10 Bold from the system, for labels; the
--                         system font when it cannot be loaded.
--   ui.text(font, text, x, y, white, align)
--                         draw in capitals; white = white ink (on black);
--                         align "left" (default) | "center" | "right" (x is
--                         that edge or the centre). Returns the width.
--   ui.button(letter, word, x, y, white)
--                         a ringed A or B and one word, the disc's left edge
--                         at x, its top at y (15 px tall). white = on black.
--                         Returns the width.
--   ui.buttonWidth(word)  the width ui.button will take.
--   ui.textDots(font, parts, x, y, white, align)
--                         parts of one line with a middle dot between them.
--   ui.capBox(y, pad)     the top and height of a highlight box round a line
--                         of display 16 drawn at y: the caps fill rows 1 to 16
--                         of the font's cell, so the box is centred on them with
--                         pad px above and below (2 at the least, so the
--                         box never cuts the caps).
--
-- A text call costs about 0.6 ms on the device: draw these into a cached
-- image (the title's and the cards' do) and copy that.
import "CoreLibs/graphics"
import "core/tw"

local gfx <const> = playdate.graphics

tw.render = tw.render or {}
local ui = {}

ui.tune = {
	buttonR = 7,          -- the ring's radius (a 15 px disc)
	buttonGap = 5,        -- disc to word
	labelPaths = { "/System/Fonts/Roobert-10-Bold.pft", "/System/Fonts/Roobert-10-Bold" },
}

local fonts = {}

function ui.display(cap)
	local key = "display" .. cap
	if not fonts[key] then
		fonts[key] = gfx.font.new("fonts/ThrowingWoodDisplay-" .. cap)
		assert(fonts[key], "no display font at cap " .. tostring(cap))
	end
	return fonts[key]
end

function ui.capBox(y, pad)
	if pad < 2 then pad = 2 end
	return y + 1 - pad, 16 + 2 * pad
end

function ui.label()
	if not fonts.label then
		for _, p in ipairs(ui.tune.labelPaths) do
			fonts.label = gfx.font.new(p)
			if fonts.label then break end
		end
		fonts.label = fonts.label or gfx.getSystemFont()
	end
	return fonts.label
end

function ui.text(font, text, x, y, white, align)
	text = string.upper(text)
	local w = font:getTextWidth(text)
	if align == "center" then x = x - w // 2 elseif align == "right" then x = x - w end
	gfx.setImageDrawMode(white and gfx.kDrawModeFillWhite or gfx.kDrawModeFillBlack)
	font:drawText(text, x, y)
	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	return w
end

function ui.button(letter, word, x, y, white)
	local r = ui.tune.buttonR
	local f = ui.label()
	gfx.setColor(white and gfx.kColorWhite or gfx.kColorBlack)
	gfx.fillCircleAtPoint(x + r, y + r, r)
	local th = f:getHeight()
	local ty = y + r - th // 2
	ui.text(f, letter, x + r + 1, ty, not white, "center")
	local w = ui.text(f, word, x + 2 * r + ui.tune.buttonGap, ty, white)
	return 2 * r + ui.tune.buttonGap + w
end

-- Parts of one line with a middle dot between them ("TURN 4 · BASE 5 V 4"),
-- the dot drawn as a 2 x 2 square (Roobert 10 Bold has no ·). Same
-- arguments as ui.text, parts a list; returns the width.
function ui.textDots(font, parts, x, y, white, align)
	local gap = 4
	local w = 0
	for i, p in ipairs(parts) do
		w = w + font:getTextWidth(string.upper(p)) + (i > 1 and (2 * gap + 2) or 0)
	end
	if align == "center" then x = x - w // 2 elseif align == "right" then x = x - w end
	local dotY = y + font:getHeight() // 2 - 1
	gfx.setColor(white and gfx.kColorWhite or gfx.kColorBlack)
	for i, p in ipairs(parts) do
		if i > 1 then
			gfx.fillRect(x + gap, dotY, 2, 2)
			x = x + 2 * gap + 2
		end
		x = x + ui.text(font, p, x, y, white)
	end
	return w
end

function ui.buttonWidth(word)
	return 2 * ui.tune.buttonR + ui.tune.buttonGap + ui.label():getTextWidth(string.upper(word))
end

tw.render.ui = ui
