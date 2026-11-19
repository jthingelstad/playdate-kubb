-- HOW TO THROW's panel (core/howto) over the practice pitch while aiming: a
-- black band under the rail with the step's title in the display font, its
-- lines and the footer (A: NEXT, TAP B: SKIP) in the label font, white on
-- black; while B holds the camera out over the shoulder only a strip: the
-- step's held line (core/howto.heldLine), else its title. One image, drawn again only when what the walkthrough says
-- changes (h.rev), so a frame makes no text call (docs/notes/performance.md "Drawing speed").
import "CoreLibs/graphics"
import "core/tw"
import "core/howto"
import "render/ui"

local gfx <const> = playdate.graphics
local ui = tw.render.ui
local howto = tw.howto

tw.render = tw.render or {}
local rhowto = {}

rhowto.tune = {
	y = 14,        -- px: the panel's top (under the rail)
	h = 64,        -- px: its height (title and three lines): it ends above the far
	               -- base kubbs of the first-person aim (about y 88 and down)
	titleH = 21,   -- px: the title strip alone, while the camera is out over the
	               -- shoulder (B held): the plan view's target half starts at y 24
	pad = 6,       -- px: text inset from the panel's left and right
	titleY = 3,    -- px: the title's top inside the panel
	lineY = 22,    -- px: the first line's top inside the panel
	lineH = 13,    -- px: line pitch
	shadow = 2,    -- px: the drop shadow under the band (the HUD's)
	cache = true,  -- false: draw it from scratch every frame (same pixels)
}

-- The crank's direction can be flipped (device/crank; Jamie, 2026-11-19): the
-- Playdate's own line under the first step's two (core/howto is the engine's
-- and has no crank menu), while that step is to be done.
rhowto.flipLine = "CRANK FEELS BACKWARD? MENU, PITCH: FLIP CRANK."

local img, imgH, imgRev = nil, nil, nil

local function render(h)
	local t = rhowto.tune
	local title, a, b, c, foot = howto.lines(h)
	if not c and h.phase == "do" and howto.STEPS[h.step].id == "clock" then c = rhowto.flipLine end
	local big, label = ui.display(16), ui.label()
	gfx.setColor(gfx.kColorBlack)
	gfx.fillRect(0, 0, 400, t.h + t.shadow)
	gfx.setColor(gfx.kColorWhite)
	gfx.fillRect(0, t.h, 400, 1)
	ui.text(big, title, t.pad, t.titleY, true)
	ui.text(label, foot, 400 - t.pad, t.titleY + 3, true, "right")
	local y = t.lineY
	for _, line in ipairs({ a, b, c }) do
		if line then ui.text(label, line, t.pad, y, true) end
		y = y + t.lineH
	end
end

-- The folded panel for a step with a held line (core/howto.heldLine): one
-- strip with that line, cached by its text.
local strip, stripText = nil, nil
local function drawStrip(text)
	local t = rhowto.tune
	if not strip or stripText ~= text or not t.cache then
		strip = strip or gfx.image.new(400, t.titleH + t.shadow, gfx.kColorClear)
		gfx.pushContext(strip)
		gfx.clear(gfx.kColorClear)
		gfx.setColor(gfx.kColorBlack)
		gfx.fillRect(0, 0, 400, t.titleH + t.shadow)
		gfx.setColor(gfx.kColorWhite)
		gfx.fillRect(0, t.titleH, 400, 1)
		ui.text(ui.label(), text, t.pad, t.titleY + 3, true)
		gfx.popContext()
		stripText = text
	end
	strip:draw(0, t.y)
end

-- compact: the camera is out over the shoulder (B held): the step's held
-- line in a strip when it has one, else the title strip only
function rhowto.draw(h, compact)
	local t = rhowto.tune
	if compact then
		local held = howto.heldLine(h)
		if held then drawStrip(held); return end
	end
	if compact then gfx.setClipRect(0, t.y, 400, t.titleH) end
	if not t.cache then
		gfx.setDrawOffset(0, t.y)
		render(h)
		gfx.setDrawOffset(0, 0)
		if compact then gfx.clearClipRect() end
		return
	end
	if not img or imgH ~= h or imgRev ~= h.rev then
		img = img or gfx.image.new(400, t.h + t.shadow, gfx.kColorClear)
		gfx.pushContext(img)
		gfx.clear(gfx.kColorClear)
		render(h)
		gfx.popContext()
		imgH, imgRev = h, h.rev
	end
	img:draw(0, t.y)
	if compact then gfx.clearClipRect() end
end

-- The widest line any step can show, in the label font (the howto self-test
-- checks it fits the panel).
function rhowto.widest()
	local label, w = ui.label(), 0
	for _, st in ipairs(howto.STEPS) do
		for _, L in ipairs({ st.say or {}, st.after or {}, st.afterOn or {} }) do
			for _, line in ipairs(L) do
				local lw = label:getTextWidth(line)
				if lw > w then w = lw end
			end
		end
	end
	for _, st in ipairs(howto.STEPS) do
		if st.held and label:getTextWidth(st.held) > w then w = label:getTextWidth(st.held) end
	end
	if label:getTextWidth(rhowto.flipLine) > w then w = label:getTextWidth(rhowto.flipLine) end
	local v = label:getTextWidth("THAT ONE: SHORT  HIGH  STEADY")
	if v > w then w = v end
	return w
end

tw.render.howto = rhowto
