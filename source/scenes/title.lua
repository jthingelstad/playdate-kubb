-- Title screen (docs/design/boards/Title.png): the KUBB wordmark, THROWING
-- WOOD and the menu on black. Only what works is offered: "PASS + PLAY" (a
-- match, scenes/match) and "PRACTICE" (the practice pitch, scenes/throw).
-- Left/right (or up/down) choose, A starts.
--
-- The wordmark, the band and THROWING WOOD are one pre-drawn 1-bit image
-- (images/title, made by tools/art/build.py; the launch image is the same
-- picture). The menu is drawn over it once per choice into a cached image,
-- so an idle title costs one image draw a frame.
import "CoreLibs/graphics"
import "core/tw"
import "render/ui"

local gfx <const> = playdate.graphics
local ui = tw.render.ui

tw.scenes = tw.scenes or {}
local title = {}

title.choices = { { id = "vs", text = "VS PLAYDATE" }, { id = "match", text = "PASS + PLAY" }, { id = "practice", text = "PRACTICE" } }

title.tune = {
	menuY = 172,      -- top of the menu boxes (the board's band starts at 117, the rule at 162)
	boxPadX = 6,      -- the chosen item's white box around its text
	boxH = 24,
	gap = 8,          -- between items (three fit across with room to spare)
	startRight = 388, -- the A START button's right edge and top (board: disc centre 346, 225)
	startY = 218,
}

function title.new(provider)
	return { input = provider, choice = 1, exit = nil, images = {} }
end

function title.update(s)
	local p = s.input
	p:advance()
	local n = #title.choices
	if p:pressed("up") or p:pressed("left") then s.choice = (s.choice - 2) % n + 1 end
	if p:pressed("down") or p:pressed("right") then s.choice = s.choice % n + 1 end
	if p:pressed("a") then s.exit = title.choices[s.choice].id end
end

local background = nil

local function render(choice)
	local t = title.tune
	background = background or gfx.image.new("images/title")
	local img = gfx.image.new(400, 240, gfx.kColorBlack)
	local font = ui.display(16)
	gfx.pushContext(img)
	background:draw(0, 0)
	local widths, total = {}, 0
	for i, c in ipairs(title.choices) do
		widths[i] = font:getTextWidth(c.text)
		total = total + widths[i] + 2 * t.boxPadX + (i > 1 and t.gap or 0)
	end
	local x = (400 - total) // 2
	-- the cap top sits one row into the font's cell; centre the caps in the box
	local ty = t.menuY + (t.boxH - 16) // 2 - 1
	for i, c in ipairs(title.choices) do
		local bw = widths[i] + 2 * t.boxPadX
		if i == choice then
			gfx.setColor(gfx.kColorWhite)
			gfx.fillRect(x, t.menuY, bw, t.boxH)
		end
		ui.text(font, c.text, x + t.boxPadX, ty, i ~= choice)
		x = x + bw + t.gap
	end
	ui.button("A", "START", t.startRight - ui.buttonWidth("START"), t.startY, true)
	gfx.popContext()
	return img
end

function title.draw(s)
	local img = s.images[s.choice]
	if not img then
		img = render(s.choice)
		s.images[s.choice] = img
	end
	img:draw(0, 0)
end

function title.enter()
	playdate.display.setRefreshRate(30)
end

tw.scenes.title = title
