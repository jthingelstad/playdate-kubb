-- Input providers. Scenes never call playdate.buttonIsPressed or
-- getCrankChange themselves: they read a provider, so a self-test can feed
-- scripted input instead of the device.
--
-- A provider has:
--   p:advance()        once at the start of every frame
--   p:held(name)       is the button down this frame
--   p:pressed(name)    did it go down this frame
--   p:crank()          crank change this frame in degrees, raw sign
--                      (getCrankChange: negative = anti-clockwise)
--   p:crankPos()       crank position in degrees (getCrankPosition: 0 = straight
--                      up, growing clockwise; 180 = the bottom of the turn)
--   p:docked()         is the crank folded away
--   p:dt()             seconds this frame
--   p.raw              (device only) seconds this frame, not capped: the
--                      frame-time log's measure
-- Button names: "left", "right", "up", "down", "a", "b".
import "core/tw"
import "core/swing"

local input = {}

local BUTTONS = {
	left = playdate.kButtonLeft, right = playdate.kButtonRight,
	up = playdate.kButtonUp, down = playdate.kButtonDown,
	a = playdate.kButtonA, b = playdate.kButtonB,
}

local MAX_DT = 0.1 -- a long stall (menu, loading) counts as one slow frame

-- The real device (or the Simulator's controls).
function input.device()
	local p = { cur = 0, down = 0, delta = 0, step = 1 / 30 }
	playdate.resetElapsedTime()
	function p:advance()
		local cur, pressed = playdate.getButtonState()
		self.cur, self.down = cur, pressed
		self.delta = playdate.getCrankChange()
		local e = playdate.getElapsedTime()
		playdate.resetElapsedTime()
		if e <= 0 then e = 1 / playdate.display.getRefreshRate() end
		self.raw = e
		self.step = math.min(e, MAX_DT)
	end
	function p:held(name) return (self.cur & BUTTONS[name]) ~= 0 end
	function p:pressed(name) return (self.down & BUTTONS[name]) ~= 0 end
	function p:crank() return self.delta end
	function p:crankPos() return playdate.getCrankPosition() end
	function p:docked() return playdate.isCrankDocked() end
	function p:dt() return self.step end
	return p
end

-- Scripted input for self-tests. `steps` is an array; each step lasts n
-- frames (default 1) and may give:
--   hold = {"left", ...}    buttons held for the whole step
--   press = {"up", ...}     buttons that go down on the step's first frame
--                           (and are held for that frame)
--   crank = d               raw crank degrees every frame of the step
--   cranks = {d1, d2, ...}  raw crank degrees frame by frame (sets n)
--   docked = true           the crank is folded away
--   home = true             on the step's first frame the crank turns straight
--                           to the bottom of the turn (180) by the short way
-- dt is fixed (1/50 s by default). After the last step: nothing held, no crank.
-- The crank starts at startPos (default 180, the bottom) and its position
-- follows the scripted changes.
function input.scripted(steps, dt, startPos)
	local p = { steps = steps, i = 1, k = 0, fixed = dt or (1 / 50), frame = 0, pos = startPos or 180 }
	local none = {}
	local function stepLength(s)
		if s.cranks then return #s.cranks end
		return s.n or 1
	end
	function p:advance()
		self.frame = self.frame + 1
		self.k = self.k + 1
		local s = self.steps[self.i]
		while s and self.k > stepLength(s) do
			self.i, self.k = self.i + 1, 1
			s = self.steps[self.i]
		end
		self.cur = s or none
		-- this frame's crank change, worked out once
		local d
		s = self.cur
		if s.home then
			d = 0
			if self.k == 1 then
				d = (180 - self.pos) % 360
				if d > 180 then d = d - 360 end
			end
		elseif s.cranks then
			d = s.cranks[self.k] or 0
		else
			d = s.crank or 0
		end
		self.d = d
		self.pos = (self.pos + d) % 360
	end
	local function has(list, name)
		if not list then return false end
		for _, v in ipairs(list) do if v == name then return true end end
		return false
	end
	function p:held(name)
		return has(self.cur.hold, name) or (self.k == 1 and has(self.cur.press, name))
	end
	function p:pressed(name) return self.k == 1 and has(self.cur.press, name) end
	function p:crank() return self.d or 0 end
	function p:crankPos() return self.pos end
	function p:docked() return self.cur.docked == true end
	function p:dt() return self.fixed end
	function p:finished() return self.steps[self.i] == nil end
	return p
end

-- Steps for a scripted swing (self-tests, the autobench), in input.scripted's
-- form: the crank home to the bottom of the turn, `lead` idle frames, the crank wound `back` degrees behind the bottom
-- of the turn over `frames` frames, `pause` frames still, then a flick that
-- stops `release` degrees past the bottom (forward degrees: 90 = 3 o'clock).
-- The flick ramps up a third of `peak` a frame to `peak` degrees a frame (24
-- at 50 fps is 1200 deg/s: a full flick) and ends on the remainder, so the
-- arm stops exactly there and core/swing measures back and releaseAngle as
-- given. `shaky` alternates fast and slow frames (a stuttered flick). The
-- crank sign (swing.tune.forwardSign) is applied here. Returns a new list.
function input.swingSteps(back, release, opts)
	opts = opts or {}
	local sign = tw.swing.tune.forwardSign
	local frames, peak = opts.frames or 30, opts.peak or 24
	local steps = {}
	-- the crank to the bottom first (wherever the last throw left it), then
	-- the lead's still frames
	steps[#steps + 1] = { home = true }
	if (opts.lead or 5) > 0 then steps[#steps + 1] = { n = opts.lead or 5 } end
	steps[#steps + 1] = { crank = -sign * back / frames, n = frames }
	if (opts.pause or 5) > 0 then steps[#steps + 1] = { n = opts.pause or 5 } end
	local c, left, k = {}, back + release, 0
	while left > 1e-9 do
		k = k + 1
		local d = peak
		if opts.shaky then
			d = (k % 2 == 1) and peak * 1.6 or peak * 0.2
		elseif k <= 3 then
			d = peak * k / 3
		end
		if d > left then d = left end
		c[k] = sign * d
		left = left - d
	end
	steps[#steps + 1] = { cranks = c }
	return steps
end

tw.input = input
