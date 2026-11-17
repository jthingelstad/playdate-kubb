-- core/version must say what source/pdxinfo says (version and buildNumber).
import "core/version"

local function pdxinfo()
	local here = arg[0]:match("^(.*)/[^/]*$") or "."
	local h = assert(io.open(here .. "/../../source/pdxinfo"))
	local t = {}
	for line in h:lines() do
		local k, v = line:match("^([%w]+)=(.*)$")
		if k then t[k] = v end
	end
	h:close()
	return t
end

test("core/version matches source/pdxinfo", function()
	local info = pdxinfo()
	expect.eq(tw.version.version, info.version, "version")
	expect.eq(tw.version.build, tonumber(info.buildNumber), "buildNumber")
end)

test("core/version's text is version (build)", function()
	expect.eq(tw.version.text, tw.version.version .. " (" .. tw.version.build .. ")")
	expect.truthy(tw.version.text:match("^%d+%.%d+%.%d+ %(%d+%)$"), "shape " .. tw.version.text)
end)
