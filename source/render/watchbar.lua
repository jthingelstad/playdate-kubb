-- The Playdate's turn against the Playdate (1.1.0): one plaque at the foot of the
-- screen, between the minimap and the result flag, that says what the buttons do while it throws or stands its kubbs up:
--   B SPEED 1X    B steps the speed 1X -> 2X -> 4X -> 1X (scenes/match, kept)
--   A SKIP        A plays the rest of its turn at once (scenes/match "Skip")
-- One image per speed, drawn once; per frame it is one image draw.
import "CoreLibs/graphics"
import "core/tw"
import "render/ui"

local gfx <const> = playdate.graphics
local ui = tw.render.ui
local BLACK <const>, WHITE <const> = gfx.kColorBlack, gfx.kColorWhite

tw.render = tw.render or {}
local bar = {}

bar.tune = { x = 62, y = 217, h = 20, pad = 6, gap = 10, shadow = 2 }

-- the speed's words: 1, 2 or 4 (the house type is capitals: 1X, 2X, 4X)
bar.speedText = { [1] = "SPEED 1X", [2] = "SPEED 2X", [4] = "SPEED 4X" }

local imgs = {}

local function make(speed)
	local t = bar.tune
	local a, b = "SKIP", bar.speedText[speed] or bar.speedText[1]
	local w = t.pad + ui.buttonWidth(b) + t.gap + ui.buttonWidth(a) + t.pad
	local img = gfx.image.new(w + t.shadow, t.h + t.shadow, gfx.kColorClear)
	gfx.pushContext(img)
	gfx.setColor(BLACK)
	gfx.fillRect(t.shadow, t.shadow, w, t.h)
	gfx.setColor(WHITE)
	gfx.fillRect(0, 0, w, t.h)
	gfx.setColor(BLACK)
	gfx.setLineWidth(2)
	gfx.drawRect(0, 0, w, t.h)
	gfx.setLineWidth(1)
	local x = t.pad
	x = x + ui.button("B", b, x, 3) + t.gap
	ui.button("A", a, x, 3)
	gfx.popContext()
	return img
end

-- Draw the bar for `speed` (1, 2 or 4).
function bar.draw(speed)
	local img = imgs[speed]
	if not img then
		img = make(speed)
		imgs[speed] = img
	end
	img:draw(bar.tune.x, bar.tune.y)
end

-- The next speed after `speed`: 1 -> 2 -> 4 -> 1.
function bar.nextSpeed(speed)
	if speed == 1 then return 2 elseif speed == 2 then return 4 end
	return 1
end

tw.render.watchbar = bar
