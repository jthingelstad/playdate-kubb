-- Title screen: the game's name and two choices, "Match" (pass and play,
-- scenes/match) and "Practice pitch" (scenes/throw). Up and down choose, A
-- starts. Drawn once into an image per choice, so an idle title costs one
-- image draw a frame.
import "CoreLibs/graphics"
import "core/tw"

local gfx <const> = playdate.graphics

tw.scenes = tw.scenes or {}
local title = {}

title.choices = { { id = "match", text = "Match" }, { id = "practice", text = "Practice pitch" } }

function title.new(provider)
	return { input = provider, choice = 1, exit = nil, images = {} }
end

function title.update(s)
	local p = s.input
	p:advance()
	local n = #title.choices
	if p:pressed("up") then s.choice = (s.choice - 2) % n + 1 end
	if p:pressed("down") then s.choice = s.choice % n + 1 end
	if p:pressed("a") then s.exit = title.choices[s.choice].id end
end

local function render(choice)
	local img = gfx.image.new(400, 240, gfx.kColorWhite)
	gfx.pushContext(img)
	gfx.setColor(gfx.kColorBlack)
	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	gfx.drawTextAligned("*Kubb: Throwing Wood*", 200, 70, kTextAlignment.center)
	for i, c in ipairs(title.choices) do
		local y = 120 + (i - 1) * 28
		local w, h = gfx.getTextSize(c.text)
		if i == choice then
			gfx.fillRoundRect(200 - w / 2 - 10, y - 4, w + 20, h + 8, 4)
			gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
		end
		gfx.drawTextAligned(c.text, 200, y, kTextAlignment.center)
		gfx.setImageDrawMode(gfx.kDrawModeCopy)
	end
	gfx.drawTextAligned("up/down to choose, A to start", 200, 210, kTextAlignment.center)
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
