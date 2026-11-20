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
--
-- The game's version and the Kubb Engine's (device/version: "0.9.8 (0.8.2)",
-- the game's the same as pdxinfo, the engine's from source/engine) sit small in the sky's top right corner, black on white, so a player
-- can tell which release they have.
import "CoreLibs/graphics"
import "core/tw"
import "device/version"
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
	versionRight = 394, -- the version's right edge and top, in the white sky above the wordmark
	versionY = 4,
}

-- saved: a line about the match in progress ("ASH V BIRCH, TURN 7"), or
-- nil; with it, B resumes that match. hint: HOW TO THROW has not been seen
-- yet, so the title says where HOW TO PLAY (whose last card leads into it) is (only when there is no match to
-- resume: the line sits where B RESUME would).
function title.new(provider, saved, hint)
	return { input = provider, choice = 1, exit = nil, images = {}, saved = saved, hint = hint }
end

title.HINT = "NEW? PRACTICE > HOW TO PLAY"

-- The resume button's text: the teams and the turn, or only the turn when
-- the teams' names would run into A START.
function title.resumeText(saved)
	local t = title.tune
	local room = t.startRight - ui.buttonWidth("START") - 12 - 12
	local full = "RESUME " .. saved
	if ui.buttonWidth(full) <= room then return full end
	local turn = saved:match("TURN (%d+)$")
	return turn and ("RESUME TURN " .. turn) or "RESUME"
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

local function render(choice, saved, hint)
	local t = title.tune
	background = background or gfx.image.new("images/title")
	local img = gfx.image.new(400, 240, gfx.kColorBlack)
	local font = ui.display(16)
	gfx.pushContext(img)
	background:draw(0, 0)
	ui.text(ui.label(), tw.version.text, t.versionRight, t.versionY, false, "right")
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
	if saved then
		ui.button("B", title.resumeText(saved), 12, t.startY, true)
	elseif hint then
		ui.text(ui.label(), title.HINT, 12, t.startY + 2, true)
	end
	gfx.popContext()
	return img
end

function title.draw(s)
	local img = s.images[s.choice]
	if not img then
		img = render(s.choice, s.saved, s.hint)
		s.images[s.choice] = img
	end
	img:draw(0, 0)
end

function title.enter()
	playdate.display.setRefreshRate(30)
end

tw.scenes.title = title
