-- core/howto: the HOW TO THROW walkthrough, run by a stand-in crank.
import "core/howto"

local howto, swing, flight = tw.howto, tw.swing, tw.flight
local DT = 0.02

-- An input provider with a crank at an arm angle (forward degrees past the
-- bottom of the turn); `turn(deg)` moves it forward (negative: back).
local function crank()
	local sign = swing.tune.forwardSign
	local p = { arm = 0, delta = 0, hold = {}, press = {} }
	function p:crank() return self.delta end
	function p:crankPos() return 180 + self.arm * sign end
	function p:held(k) return self.hold[k] or false end
	function p:pressed(k) return self.press[k] or false end
	function p:docked() return false end
	function p:dt() return DT end
	function p:turn(deg)
		self.arm = self.arm + deg
		self.delta = deg * sign
	end
	return p
end

local function frames(h, p, steps)
	local ev
	for _, d in ipairs(steps) do
		p:turn(d)
		ev = howto.update(h, p, DT) or ev
	end
	return ev
end

local function rep(d, n)
	local t = {}
	for i = 1, n do t[i] = d end
	return t
end

-- wound 130 back, then forward `fwd` degrees in a flick, then still
local function throwOnce(h, p, flick)
	frames(h, p, { 0 })
	frames(h, p, rep(-10, 13))
	frames(h, p, flick)
	frames(h, p, rep(0, 4))
end

test("howto: a full wind-up moves on to the flick", function()
	local h, p = howto.new(30), crank()
	expect.eq(h.step, "wind")
	frames(h, p, { 0 })
	frames(h, p, rep(-10, 11))
	expect.eq(h.step, "wind")
	frames(h, p, rep(-10, 2))
	expect.eq(h.step, "throw")
	expect.eq(h.sw.phase, "winding")
end)

test("howto: a stop on the notch is the throw, and step 3 moves the notch", function()
	local h, p = howto.new(30), crank()
	throwOnce(h, p, { 6, 12, 18, 22, 24, 24, 24, 20, 10 })   -- 160 forward: stopped 30 past the bottom
	expect.truthy(h.last, "a throw")
	expect.near(h.last.angle, 30, 1e-6)
	expect.eq(h.last.miss, 0)
	expect.near(h.last.launch, 30, 1e-6)
	expect.truthy(h.last.carry > 6, "carried " .. h.last.carry)
	expect.eq(h.step, "notch")
	local _, _, _, say = howto.lines(h)
	expect.truthy(say:find("ON THE NOTCH"), say)
	-- hold A and turn the crank: the notch moves, and 10 degrees of it is done
	p.hold.a = true
	frames(h, p, rep(10, 7))
	expect.truthy(h.loft > 39, "loft " .. h.loft)
	expect.eq(h.step, "done")
	p.hold.a = false
	p.press.a = true
	expect.eq(howto.update(h, p, DT), "close")
end)

test("howto: an early stop stays on the flick and says which way", function()
	local h, p = howto.new(30), crank()
	throwOnce(h, p, { 6, 12, 18, 22, 24, 18 })   -- 100 forward: 20 short of the bottom
	expect.eq(h.last.miss, -1)
	expect.truthy(h.last.launch < 30, "launch " .. h.last.launch)
	expect.eq(h.step, "throw")
	local _, _, _, say = howto.lines(h)
	expect.truthy(say:find("EARLY"), say)
	-- the crank stopped 30 behind the bottom: as in the game, a new throw
	-- arms only once it crosses the bottom going back, so bring it forward
	frames(h, p, rep(5, 7))
	-- and the next, on the notch, moves on
	throwOnce(h, p, { 6, 12, 18, 22, 24, 24, 24, 20, 10 })
	expect.eq(h.step, "notch")
	expect.eq(h.throws, 2)
end)

test("howto: a slow forward turn lets the wind-up down, and says so", function()
	local h, p = howto.new(30), crank()
	frames(h, p, { 0 })
	frames(h, p, rep(-10, 9))
	frames(h, p, rep(2, 50))
	expect.eq(h.last, nil)
	local _, _, _, say = howto.lines(h)
	expect.truthy(say and say:find("TOO SLOW"), tostring(say))
end)

test("howto: B leaves at any step", function()
	local h, p = howto.new(30), crank()
	p.press.b = true
	expect.eq(howto.update(h, p, DT), "close")
end)

test("howto: the side view's carry is the flight from the hand", function()
	-- a full-power throw at 35 carries about 8.9 m (flight.loftBoost's mark)
	local c = howto.flight(35, howto.aimSpeed(35))
	expect.truthy(c > 8 and c < 9.6, "carry " .. c)
	-- thrown into the ground it carries little
	expect.truthy(howto.flight(-20, 9) < 2)
	expect.eq(flight.tune.handHeight > 0, true)
end)
