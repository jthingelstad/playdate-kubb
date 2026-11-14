import "selftest/_throw"

local st = tw.selftest

-- Scenario "bursts": every burst image on a white screen, for review: frame 1
-- clean (flash, burst, break-up), 2 the double's two stars, 3 the king. A
-- cross marks each image's anchor (the spike's tip).
st.scenarios.bursts = {
	step = function(ctx)
		local gfx = playdate.graphics
		ctx.n = (ctx.n or 0) + 1
		local sets = {
			{ "clean", "clean", "clean" },
			{ "double_a", "double_b", "double_b" },
			{ "king", "king", "king" },
		}
		local set = sets[ctx.n]
		gfx.clear(gfx.kColorWhite)
		for i = 1, 3 do
			local img = gfx.image.new("images/burst/" .. set[i] .. "-" .. (ctx.n == 2 and (i == 1 and 2 or i) or i))
			img:draw((i - 1) * 133 + 2, 40)
		end
		ctx:capture()
		return ctx.n == 3
	end,
}
