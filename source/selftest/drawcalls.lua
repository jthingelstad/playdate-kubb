-- Scenario "drawcalls": the hit throw (as "hit") with every graphics call
-- counted (selftest/_drawcount.lua wraps them when launched with this
-- scenario). The note gives, per kind of frame, the mean and largest number
-- of graphics calls and the text calls: aim (aiming and winding), flight
-- (the baton in the air), impact (from its first touch to rest) and rest.
-- On the device each call costs 20 to 50 us, a text call about 0.6 ms.
-- Frames: 1 in flight, 2 just after the hit.
import "selftest/_throw"

local st = tw.selftest
local throw = tw.scenes.throw

local KINDS = { "aim", "flight", "impact", "rest" }

st.scenarios.drawcalls = {
	step = function(ctx)
		local C = tw.drawcount
		if not ctx.scene then
			if not C.on then error("draw calls are not counted (launch with selftest=drawcalls)") end
			ctx.scene = throw.new(tw.input.scripted {
				{ n = 5 },
				st.windup(120, 30),
				{ n = 5 },
				st.flick { 6, 12, 18, 22, 24, 24, 24 },
				{ n = 300 },
			})
			ctx.scene.loftDeg = 30
			throw.enter()
			ctx.sum, ctx.max, ctx.cnt, ctx.txt = {}, {}, {}, {}
			for _, k in ipairs(KINDS) do ctx.sum[k], ctx.max[k], ctx.cnt[k], ctx.txt[k] = 0, 0, 0, 0 end
			ctx.shot = 1
		end
		local s = ctx.scene
		throw.update(s)
		local kind = s.mode
		if kind == "flight" then
			local d = st.sinceContact(s)
			kind = (d and d >= 0) and "impact" or "flight"
		end
		C.n, C.text = 0, 0
		throw.draw(s)
		if ctx.sum[kind] then
			ctx.sum[kind] = ctx.sum[kind] + C.n
			ctx.cnt[kind] = ctx.cnt[kind] + 1
			ctx.txt[kind] = ctx.txt[kind] + C.text
			if C.n > ctx.max[kind] then ctx.max[kind] = C.n end
		end
		if ctx.shot == 1 and kind == "flight" and s.showTime > 0.3 then ctx:capture(); ctx.shot = 2 end
		if ctx.shot == 2 and kind == "impact" then
			local d = st.sinceHit(s)
			if d and d >= 0.05 then ctx:capture(); ctx.shot = 3 end
		end
		local parts = {}
		for _, k in ipairs(KINDS) do
			local n = ctx.cnt[k]
			parts[#parts + 1] = string.format("%s=%.1f/%d/t%.2f", k, n > 0 and ctx.sum[k] / n or 0, ctx.max[k],
				n > 0 and ctx.txt[k] / n or 0)
		end
		ctx.note = "calls(mean/max/text-per-frame) " .. table.concat(parts, " ")
		if s.mode == "aim" and s.throws == 1 and ctx.shot == 3 then return true end
		if ctx.frame > 500 then error("no throw back to aim by frame 500") end
		return false
	end,
}
