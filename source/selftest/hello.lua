-- Scenario "hello": the title screen plus a few black-outlined shapes, one frame.
import "core/tw"
import "scenes/title"

local gfx <const> = playdate.graphics

tw.selftest.scenarios.hello = {
	step = function(ctx)
		tw.scenes.title.draw()
		gfx.setColor(gfx.kColorBlack)
		gfx.setLineWidth(2)
		gfx.drawRect(40, 40, 60, 40)          -- box, top left
		gfx.drawCircleAtPoint(340, 60, 24)    -- circle, top right
		gfx.drawLine(40, 200, 360, 200)       -- a baseline across the bottom
		gfx.drawTriangle(180, 190, 200, 150, 220, 190) -- triangle on the line
		ctx:capture()
		return true
	end,
}
