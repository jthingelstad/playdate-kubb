-- core/howto: HOW TO THROW's steps for the clock throw.
import "core/howto"
local howto = tw.howto

local function obs(over)
	local o = { arm = 60, docked = false, thrown = false, markerX = 0, markerY = 8, playerX = 0, playerY = 0,
		release = 90, tilt = 0, spin = 0, pressA = false, tapB = false }
	for k, v in pairs(over or {}) do o[k] = v end
	return o
end

local function stepId(h) return howto.STEPS[h.step].id end

test("howto: eight steps in DESIGN 4's order", function()
	local ids = {}
	for i, st in ipairs(howto.STEPS) do ids[i] = st.id end
	expect.eq(table.concat(ids, " "), "clock throw power arc circle walk plan done")
end)

test("howto: every line fits the panel and a throw step leaves its third line for the verdicts", function()
	for _, st in ipairs(howto.STEPS) do
		for _, L in ipairs({ st.say or {}, st.after or {}, st.afterOn or {} }) do
			expect.truthy(#L <= 3, st.id .. ": three lines at most")
			for _, line in ipairs(L) do
				expect.truthy(#line <= 52, st.id .. ": " .. line)
				expect.eq(line, line:upper(), "capitals")
			end
		end
		if st.id == "throw" or st.id == "power" or st.id == "arc" then
			expect.truthy(#st.say <= 2 and #(st.after or {}) <= 2 and #(st.afterOn or {}) <= 2, st.id)
		end
	end
end)

test("howto: the crank step passes at 6 o'clock, not docked, then A goes on", function()
	local h = howto.new()
	expect.eq(howto.update(h, obs({ arm = 60 })), nil)
	expect.eq(h.phase, "do")
	howto.update(h, obs({ arm = 0, docked = true }))
	expect.eq(h.phase, "do", "docked")
	howto.update(h, obs({ arm = -12 }))
	expect.eq(h.phase, "after")
	local rev = h.rev
	howto.update(h, obs({ arm = 0, pressA = true }))
	expect.eq(stepId(h), "throw")
	expect.truthy(h.rev > rev, "rev bumped")
end)

test("howto: point and throw passes on any throw and shows its verdicts", function()
	local h = howto.new()
	h.step = 2
	howto.update(h, obs({ thrown = true, powerV = 1, releaseV = -1, steady = false }))
	expect.eq(h.phase, "after")
	local title, a, b = howto.lines(h)
	expect.eq(title, "2  POINT AND THROW")
	expect.eq(a, "THAT ONE: LONG  LOW  SHAKY")
	expect.truthy(b:find("^POWER"), b)
end)

test("howto: power waits for an ON, or goes on after the tries", function()
	local h = howto.new()
	h.step = 3
	for i = 1, howto.tune.tries - 1 do
		howto.update(h, obs({ thrown = true, powerV = -1, releaseV = 0, steady = true }))
		expect.eq(h.phase, "do", "try " .. i)
		local _, _, _, c = howto.lines(h)
		expect.eq(c, "THAT ONE: SHORT  ON  STEADY")
	end
	howto.update(h, obs({ thrown = true, powerV = -1, releaseV = 0, steady = true }))
	expect.eq(h.phase, "after")
	expect.eq(h.on, false)
	local h2 = howto.new()
	h2.step = 3
	howto.update(h2, obs({ thrown = true, powerV = 0, releaseV = 1, steady = true }))
	expect.eq(h2.phase, "after")
	expect.eq(h2.on, true)
	local _, a, b = howto.lines(h2)
	expect.eq(a, "THAT ONE: ON  HIGH  STEADY")
	expect.truthy(b:find("^POWER ON"), b)
end)

test("howto: the arc waits for the release ON", function()
	local h = howto.new()
	h.step = 4
	howto.update(h, obs({ thrown = true, powerV = 0, releaseV = 1, steady = true }))
	expect.eq(h.phase, "do")
	howto.update(h, obs({ thrown = true, powerV = 1, releaseV = 0, steady = true }))
	expect.eq(h.phase, "after")
	expect.eq(h.on, true)
end)

test("howto: circle, walk and plan measure from where the step began", function()
	local h = howto.new()
	h.step = 4
	howto.update(h, obs())
	h.phase = "after"
	howto.update(h, obs({ markerX = 1, markerY = 6, pressA = true }))   -- on to the circle step, aimed at (1, 6)
	expect.eq(stepId(h), "circle")
	howto.update(h, obs({ markerX = 1.2, markerY = 6 }))
	expect.eq(h.phase, "do", "0.2 m")
	howto.update(h, obs({ markerX = 1.31, markerY = 6 }))
	expect.eq(h.phase, "after")
	howto.update(h, obs({ playerX = 0, pressA = true }))
	expect.eq(stepId(h), "walk")
	howto.update(h, obs({ playerX = 0.4 }))
	expect.eq(h.phase, "do")
	howto.update(h, obs({ playerX = 0.4, playerY = -0.4 }))
	expect.eq(h.phase, "after")
	howto.update(h, obs({ release = 90, pressA = true }))
	expect.eq(stepId(h), "plan")
	howto.update(h, obs({ release = 105 }))
	expect.eq(h.phase, "do", "the arc alone")
	howto.update(h, obs({ release = 90, tilt = 5 }))
	expect.eq(h.phase, "do", "the tilt alone")
	howto.update(h, obs({ release = 105, spin = -1 }))
	expect.eq(h.phase, "after", "the arc and a spin")
end)

test("howto: a tap of B skips a step; the last step ends on A or a tap", function()
	local h = howto.new()
	for i = 1, #howto.STEPS - 1 do
		expect.eq(howto.update(h, obs({ tapB = true })), nil)
		expect.eq(h.step, i + 1)
		expect.eq(h.phase, "do")
	end
	expect.eq(stepId(h), "done")
	local _, _, _, _, foot = howto.lines(h)
	expect.eq(foot, "A: PLAY")
	expect.eq(howto.update(h, obs()), nil)
	expect.eq(howto.update(h, obs({ pressA = true })), "close")
	local h2 = howto.new()
	h2.step = #howto.STEPS
	expect.eq(howto.update(h2, obs({ tapB = true })), "close")
end)

test("howto: A does nothing until a step is done", function()
	local h = howto.new()
	howto.update(h, obs({ pressA = true }))
	expect.eq(h.step, 1)
	expect.eq(h.phase, "do")
	local _, _, _, _, foot = howto.lines(h)
	expect.eq(foot, "TAP B: SKIP")
end)
