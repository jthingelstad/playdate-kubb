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
--   p:setAccel(on)     run the accelerometer (true) or put it to sleep; a scene
--                      asks for it only while it reads it (a drill being aimed)
--   p:accel()          x, y, z in g (readAccelerometer: the way gravity pulls,
--                      x right, y to the bottom of the screen, z through it away
--                      from the viewer), read at advance(); nil while it is off
--                      and until the advance() after it was turned on
--   p:dt()             seconds this frame
--   p.raw              (device only) seconds this frame, not capped: the
--                      frame-time log's measure
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
		-- turned on in an earlier frame's update: its values are ready by now
		if self.accelOn then self.ax, self.ay, self.az = playdate.readAccelerometer() end
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
	function p:setAccel(on)
		on = on and true or false
		if on == (self.accelOn or false) then return end
		self.accelOn, self.ax, self.ay, self.az = on, nil, nil, nil
		if on then playdate.startAccelerometer() else playdate.stopAccelerometer() end
	end
	function p:accel()
		if self.ax == nil then return nil end
		return self.ax, self.ay, self.az
	end
	return p
end

-- The accelerometer's x, y, z for a console rolled `roll` degrees (right
-- side down positive) and its screen tipped `pitch` degrees up from lying on
-- its back (90 is upright; the scripted default, 45, is a usual hold).
function input.gravity(roll, pitch)
	local r, e = math.rad(roll), math.rad(pitch or 45)
	return math.sin(r), math.cos(r) * math.sin(e), math.cos(r) * math.cos(e)
end

-- Scripted input for self-tests. `steps` is an array; each step lasts n
-- frames (default 1) and may give:
--   hold = {"left", ...}    buttons held for the whole step
--   press = {"up", ...}     buttons that go down on the step's first frame
--                           (and are held for that frame)
--   crank = d               raw crank degrees every frame of the step
--   cranks = {d1, d2, ...}  raw crank degrees frame by frame (sets n)
--   docked = true           the crank is folded away
--   roll = d, pitch = e     the console's tilt in degrees (input.gravity) from
--                           this step on; it starts level at pitch 45. p:accel()
--                           gives it only while a scene has the accelerometer on.
-- dt is fixed (1/50 s by default). After the last step: nothing held, no crank.
-- The crank starts at startPos (default 180, the bottom) and its position
-- follows the scripted changes.
function input.scripted(steps, dt, startPos)
	local p = { steps = steps, i = 1, k = 0, fixed = dt or (1 / 50), frame = 0, pos = startPos or 180,
		roll = 0, pitch = 45, accelOn = false, accelLive = false, accelFrames = 0 }
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
		if s and self.k == 1 and (s.roll or s.pitch) then
			self.roll, self.pitch = s.roll or self.roll, s.pitch or self.pitch
		end
		-- as on the device: values from the advance() after it was turned on
		if self.accelOn then self.accelLive, self.accelFrames = true, self.accelFrames + 1 end
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
	-- accelFrames counts the frames it was asked to run (self-tests check it
	-- sleeps when no drill is aimed)
	function p:setAccel(on)
		on = on and true or false
		if on ~= self.accelOn then self.accelOn, self.accelLive = on, false end
	end
	function p:accel()
		if not (self.accelOn and self.accelLive) then return nil end
		return input.gravity(self.roll, self.pitch)
	end
	function p:finished() return self.steps[self.i] == nil end
	return p
end

tw.input = input
