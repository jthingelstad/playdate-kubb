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
-- Button names: "left", "right", "up", "down", "a", "b".
import "core/tw"

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
		self.pos = (self.pos + self:crank()) % 360
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
	function p:crank()
		local s = self.cur
		if s.cranks then return s.cranks[self.k] or 0 end
		return s.crank or 0
	end
	function p:crankPos() return self.pos end
	function p:docked() return self.cur.docked == true end
	function p:dt() return self.fixed end
	function p:finished() return self.steps[self.i] == nil end
	return p
end

tw.input = input
