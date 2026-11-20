-- device/version must say what source/pdxinfo says (version and buildNumber),
-- and its label is the game's version with the engine's in parentheses.
import "device/version"

local function read(rel)
	local here = arg[0]:match("^(.*)/[^/]*$") or "."
	local h = assert(io.open(here .. "/../../" .. rel))
	local s = h:read("a")
	h:close()
	return s
end

local function pdxinfo()
	local t = {}
	for line in read("source/pdxinfo"):gmatch("[^\n]+") do
		local k, v = line:match("^([%w]+)=(.*)$")
		if k then t[k] = v end
	end
	return t
end

test("device/version matches source/pdxinfo", function()
	local info = pdxinfo()
	expect.eq(tw.version.version, info.version, "version")
	expect.eq(tw.version.build, tonumber(info.buildNumber), "buildNumber")
end)

test("device/version's engine is the vendored engine's own version", function()
	expect.eq(tw.version.engine, tw.engine.version, "tw.engine (source/engine/version.lua)")
	local manifest = read("engine-core.json")
	expect.eq(tw.version.engine, manifest:match('"version": "([^"]+)"'), "engine-core.json's version")
end)

test("device/version's text is version (engine version), no build", function()
	expect.eq(tw.version.text, tw.version.version .. " (" .. tw.version.engine .. ")")
	expect.truthy(tw.version.text:match("^%d+%.%d+%.%d+ %(%d+%.%d+%.%d+%)$"), "shape " .. tw.version.text)
end)
