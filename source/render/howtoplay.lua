-- HOW TO PLAY's cards (core/howtoplay) in the Woodcut look of the match's
-- hand-off card (render/cards): white on black, the card's title in the
-- display font, its words in the label font wrapped to the column, and a
-- little pitch from above on the right. Each card is drawn once into a
-- 400 x 240 image; scenes/howtoplay copies it every frame.
--
--   rhp.card(i)       the image of card i; raises an error when its words do
--                     not fit (the howto-play self-test draws every card)
import "CoreLibs/graphics"
import "core/tw"
import "core/howtoplay"
import "render/ui"

local gfx <const> = playdate.graphics
local ui = tw.render.ui
local hp = tw.howtoplay

tw.render = tw.render or {}
local rhp = {}

-- screen pixels; the map is where the hand-off card has its pitch
rhp.tune = {
	left = 16,
	topY = 12,                 -- HOW TO PLAY and the page count
	titleTop = 32,             -- the title's cap top (display 32; display 16 when too wide)
	ruleY = 74, ruleW = 240,
	textTop = 86,              -- the first line of words
	lineH = 14, paraGap = 5,   -- line pitch and the extra space between paragraphs
	textBottom = 204,          -- the words end above this
	colRight = 278,            -- the column's right edge beside the map (full width: 384)
	buttonY = 215,
	map = { x = 290, y = 36, w = 94, h = 148, cx = 337, base = 175, far = 45, mPerX = 18 },
}

local function white() gfx.setColor(gfx.kColorWhite) end
local function black() gfx.setColor(gfx.kColorBlack) end

-- Words to lines no wider than w in font f (spaces only; text in capitals).
local function wrap(f, text, w)
	local lines, line = {}, nil
	for word in string.gmatch(string.upper(text), "%S+") do
		local try = line and (line .. " " .. word) or word
		if line and f:getTextWidth(try) > w then
			lines[#lines + 1] = line
			line = word
		else
			line = try
		end
	end
	if line then lines[#lines + 1] = line end
	return lines
end

local function mapXY(x, y)
	local m = rhp.tune.map
	local sy = (m.base - m.far) / 8
	return math.floor(m.cx + x * m.mPerX + 0.5), math.floor(m.base - y * sy + 0.5)
end

-- The little pitch: you at the bottom, them at the top.
local function drawMap(spec)
	local m = rhp.tune.map
	local label = ui.label()
	ui.text(label, "THEM", m.cx, m.y - 16, true, "center")
	ui.text(label, "YOU", m.cx, m.y + m.h + 4, true, "center")
	white()
	gfx.fillRect(m.x, m.y, m.w, m.h)
	black()
	gfx.setLineWidth(2)
	gfx.drawRect(m.x + 3, m.y + 3, m.w - 6, m.h - 6)
	gfx.setLineWidth(1)
	-- the centerline, dashed 4 on 3
	local _, cy = mapXY(0, 4)
	for x = m.x + 3, m.x + m.w - 4, 7 do gfx.fillRect(x, cy - 1, 4, 2) end
	-- an advantage line: dotted across, through the field kubb nearest the middle
	if spec.line then
		local _, ly = mapXY(0, spec.line)
		for x = m.x + 3, m.x + m.w - 4, 4 do gfx.fillRect(x, ly, 2, 1) end
	end
	for _, p in ipairs(spec.pieces) do
		local x, y = mapXY(p.x, p.y)
		if p.kind == "king" then
			gfx.fillRect(x - 3, y - 3, 6, 6)
			gfx.fillPolygon(x - 3, y - 3, x - 3, y - 6, x - 1, y - 4, x, y - 7, x + 1, y - 4, x + 3, y - 6, x + 3, y - 3)
		elseif p.kind == "down" then
			gfx.drawRect(x - 3, y - 2, 6, 4)
		elseif p.kind == "field" then
			gfx.fillRect(x - 2, y - 3, 5, 6)
		else
			gfx.fillRect(x - 2, y - 2, 4, 4)
		end
	end
	-- the throw: a dotted line with a head
	local a = spec.arrow
	if a then
		local x1, y1 = mapXY(a[1], a[2])
		local x2, y2 = mapXY(a[3], a[4])
		local dx, dy = x2 - x1, y2 - y1
		local len = math.sqrt(dx * dx + dy * dy)
		local ux, uy = dx / len, dy / len
		for d = 0, len - 6, 5 do
			local px, py = x1 + ux * d, y1 + uy * d
			gfx.fillRect(math.floor(px), math.floor(py), 2, 2)
		end
		local bx, by = x2 - ux * 7, y2 - uy * 7
		gfx.fillTriangle(x2, y2, bx - uy * 4, by + ux * 4, bx + uy * 4, by - ux * 4)
	end
end

function rhp.card(i)
	local t = rhp.tune
	local card = hp.CARDS[i]
	local n = #hp.CARDS
	local img = gfx.image.new(400, 240, gfx.kColorBlack)
	local label, d16, d32 = ui.label(), ui.display(16), ui.display(32)
	gfx.pushContext(img)
	ui.text(label, "HOW TO PLAY", t.left, t.topY, true)
	-- the page count, bottom right like the hand-off card's turn line
	ui.text(label, i .. " / " .. n, 392, t.buttonY + 1, true, "right")
	local right = card.map and t.colRight or 384
	local title = card.title
	if d32:getTextWidth(title) <= right - t.left then
		ui.text(d32, title, t.left - 1, t.titleTop - 1, true)
	else
		ui.text(d16, title, t.left, t.titleTop + 16, true)
	end
	white()
	gfx.fillRect(t.left, t.ruleY, t.ruleW, 3)
	local y = t.textTop
	for pi, para in ipairs(card.text) do
		if pi > 1 then y = y + t.paraGap end
		for _, line in ipairs(wrap(label, para, right - t.left)) do
			ui.text(label, line, t.left, y, true)
			y = y + t.lineH
		end
	end
	if y - t.lineH + label:getHeight() > t.textBottom then
		gfx.popContext()
		error("HOW TO PLAY card " .. i .. " (" .. card.id .. "): the words run past the bottom (" .. y .. ")")
	end
	if card.map then drawMap(card.map) end
	if i == n then
		local w = ui.button("A", "HOW TO THROW", t.left, t.buttonY, true)
		ui.button("B", "DONE", t.left + w + 18, t.buttonY, true)
	else
		local w = ui.button("A", "NEXT", t.left, t.buttonY, true)
		ui.button("B", i == 1 and "BACK" or "PREVIOUS", t.left + w + 18, t.buttonY, true)
	end
	gfx.popContext()
	return img
end

tw.render.howtoplay = rhp
