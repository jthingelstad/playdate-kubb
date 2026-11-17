-- Simulator self-test runner. main.lua starts it when launched with
--   selftest=<scenario> out=<absolute dir>
-- A scenario is a table with step(ctx), called once per frame from
-- playdate.update until it returns true. ctx.frame counts from 1, and
-- ctx:capture() saves the working frame as <out>/<name>-NN.png (1x) and
-- <name>-NN@2x.png (2x). A scenario may set ctx.note (one line, e.g. timings)
-- to have it appended to the DONE marker. When the scenario ends the runner prints
-- writes "DONE <name> frames=<n>" (or "FAIL <name>: <why>") to the marker
-- Data/com.throwingwood.playdate/selftest/<name>.done and quits the
-- Simulator. The Makefile checks the marker and copies it into out.
-- With film=1 (selftest.start's film) every frame is also saved, 1x, as
-- <out>/<name>-f00001.png and so on, for cutting a video (tools/film.sh).
import "core/tw"

local gfx <const> = playdate.graphics

local selftest = { scenarios = {} }
tw.selftest = selftest

local ctx = nil

local function finish(ok, why)
	local status = ok and ("DONE " .. ctx.name .. " frames=" .. ctx.shots .. (ctx.note and (" " .. ctx.note) or ""))
		or ("FAIL " .. ctx.name .. ": " .. tostring(why))
	print("SELFTEST " .. status)
	-- The marker. playdate.file only writes inside the game's Data folder
	-- (an absolute path writes nothing), writeToFile only writes images, and
	-- print() does not reach the Simulator's stdout. So the marker goes to
	-- Data/<bundleID>/selftest/<name>.done and the Makefile copies it to out.
	playdate.file.mkdir("selftest")
	local f = playdate.file.open("selftest/" .. ctx.name .. ".done", playdate.file.kFileWrite)
	if f then
		f:write(status .. "\n")
		f:close()
	end
	ctx.finished = true
	playdate.simulator.exit()
end

local function capture(self)
	self.shots = self.shots + 1
	local img = gfx.getWorkingImage()
	local base = string.format("%s/%s-%02d", self.out, self.name, self.shots)
	playdate.simulator.writeToFile(img, base .. ".png")
	playdate.simulator.writeToFile(img:scaledImage(2), base .. "@2x.png")
end

function selftest.start(name, out, film)
	ctx = { name = name, out = out, frame = 0, shots = 0, capture = capture, film = film }
	if not playdate.isSimulator then
		print("SELFTEST FAIL " .. name .. ": self-tests run only in the Simulator")
		ctx.finished = true
		return
	end
	if not out or out:sub(1, 1) ~= "/" then
		return finish(false, "out=<absolute dir> is required")
	end
	ctx.scenario = selftest.scenarios[name]
	if not ctx.scenario then return finish(false, "no scenario named " .. name) end
	-- The nerves (core/throwplan) move a player's throw off its plan by a
	-- seeded draw; a scripted clean swing should be the plan's clean throw,
	-- so they are off unless the scenario asks for them (nerves = true).
	local throwScene = tw.scenes and tw.scenes.throw
	if throwScene then throwScene.nerves = ctx.scenario.nerves == true end
end

function selftest.update()
	if ctx.finished then return end
	ctx.frame = ctx.frame + 1
	local ok, done = pcall(ctx.scenario.step, ctx)
	if not ok then return finish(false, done) end
	if ctx.film then
		playdate.simulator.writeToFile(gfx.getWorkingImage(),
			string.format("%s/%s-f%05d.png", ctx.out, ctx.name, ctx.frame))
	end
	if done then finish(true) end
end
