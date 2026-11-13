-- Title screen: white background, the system font, the game's name.
import "core/tw"

local gfx <const> = playdate.graphics

tw.scenes = tw.scenes or {}
local title = {}

function title.draw()
	gfx.clear(gfx.kColorWhite)
	gfx.setColor(gfx.kColorBlack)
	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	gfx.drawTextAligned("Kubb: Throwing Wood", 200, 110, kTextAlignment.center)
end

tw.scenes.title = title
