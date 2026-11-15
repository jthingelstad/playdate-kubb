-- HOW TO PLAY: the rules on six cards (core/howtoplay, render/howtoplay),
-- from the PRACTICE menu's HOW TO PLAY row. A or right turns the page, B or
-- left goes back; B on the first card goes back to the menu. The last card
-- leads on: A opens HOW TO THROW over the practice pitch (main.lua "howto"),
-- B is done (the menu again).
--
--   scene.new(provider)   s; s.exit becomes "howto" or "practice"
--   scene.update(s), scene.draw(s), scene.enter()
--
-- Each card is one image, made when it is first shown and kept.
import "CoreLibs/graphics"
import "core/tw"
import "core/howtoplay"
import "render/howtoplay"

local hp, rhp = tw.howtoplay, tw.render.howtoplay

tw.scenes = tw.scenes or {}
local scene = {}

function scene.new(provider)
	return { input = provider, st = hp.new(), imgs = {}, exit = nil }
end

function scene.update(s)
	local p = s.input
	p:advance()
	local b = (p:pressed("a") and "a") or (p:pressed("b") and "b")
		or (p:pressed("right") and "right") or (p:pressed("left") and "left") or nil
	if not b then return end
	local r = hp.press(s.st, b)
	if r == "howto" then s.exit = "howto"
	elseif r == "exit" then s.exit = "practice" end
end

function scene.draw(s)
	local i = s.st.page
	if not s.imgs[i] then s.imgs[i] = rhp.card(i) end
	s.imgs[i]:draw(0, 0)
end

function scene.enter()
	playdate.display.setRefreshRate(30)
end

tw.scenes.howtoplay = scene
