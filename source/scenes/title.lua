-- Title screen (docs/design/boards/Title.png): the KUBB wordmark, THROWING
-- WOOD and the menu on black: VS PLAYDATE and PASS + PLAY (a match,
-- scenes/match), PRACTICE (the drills menu) and PLAYERS (the saved players,
-- scenes/players), in two rows of two (four do not fit across at 16 px).
-- Left/right go through them in reading order, up/down change row; A starts.
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

title.choices = { { id = "vs", text = "VS PLAYDATE" }, { id = "match", text = "PASS + PLAY" },
	{ id = "practice", text = "PRACTICE" }, { id = "players", text = "PLAYERS" } }
title.perRow = 2

title.tune = {
	menuY = 166,      -- top of the first row of boxes (the board's band starts at 117, the rule at 162)
	rowGap = 3,       -- between the two rows (the second ends where A START begins)
	boxPadX = 6,      -- the chosen item's white box around its text
	boxH = 24,
	gap = 8,          -- between items in a row
	startRight = 388, -- the A START button's right edge and top (board: disc centre 346, 225)
	startY = 218,
}

-- saved: a line about the match in progress ("ASH V BIRCH, TURN 7"), or
-- nil; with it, B resumes that match.
function title.new(provider, saved)
	return { input = provider, choice = 1, exit = nil, images = {}, saved = saved }
end

function title.update(s)
	local p = s.input
	p:advance()
	local n = #title.choices
	if p:pressed("left") then s.choice = (s.choice - 2) % n + 1 end
	if p:pressed("right") then s.choice = s.choice % n + 1 end
	if p:pressed("up") or p:pressed("down") then s.choice = (s.choice - 1 + title.perRow) % n + 1 end
	if p:pressed("a") then s.exit = title.choices[s.choice].id end
	if s.saved and p:pressed("b") then s.exit = "resume" end
end

local background = nil

local function render(choice, saved)
	local t = title.tune
	background = background or gfx.image.new("images/title")
	local img = gfx.image.new(400, 240, gfx.kColorBlack)
	local font = ui.display(16)
	gfx.pushContext(img)
	background:draw(0, 0)
	local n, per = #title.choices, title.perRow
	for row = 0, (n - 1) // per do
		local first, last = row * per + 1, math.min(n, row * per + per)
		local widths, total = {}, 0
		for i = first, last do
			widths[i] = font:getTextWidth(title.choices[i].text)
			total = total + widths[i] + 2 * t.boxPadX + (i > first and t.gap or 0)
		end
		local x = (400 - total) // 2
		local y = t.menuY + row * (t.boxH + t.rowGap)
		-- the cap top sits one row into the font's cell; centre the caps in the box
		local ty = y + (t.boxH - 16) // 2 - 1
		for i = first, last do
			local bw = widths[i] + 2 * t.boxPadX
			if i == choice then
				gfx.setColor(gfx.kColorWhite)
				gfx.fillRect(x, y, bw, t.boxH)
			end
			ui.text(font, title.choices[i].text, x + t.boxPadX, ty, i ~= choice)
			x = x + bw + t.gap
		end
	end
	ui.button("A", "START", t.startRight - ui.buttonWidth("START"), t.startY, true)
	if saved then ui.button("B", "RESUME " .. saved, 12, t.startY, true) end
	gfx.popContext()
	return img
end

function title.draw(s)
	local img = s.images[s.choice]
	if not img then
		img = render(s.choice, s.saved)
		s.images[s.choice] = img
	end
	img:draw(0, 0)
end

function title.enter()
	playdate.display.setRefreshRate(30)
end

tw.scenes.title = title
