-- Checks on the harness, and that the Playdate's own desktop-tested modules
-- (source/device) stay pure like the core (the engine checks its core/).

test("import runs a file once and returns its value only the first time", function()
	-- Test bodies run after every test file has loaded, and the other tests
	-- import core modules (which import core/tw), so this import returns nil,
	-- as a repeated import does on the Playdate.
	import "core/tw"
	expect.eq(import "core/tw", nil)
	expect.truthy(type(tw) == "table", "tw namespace exists")
end)

test("core/ cannot import CoreLibs", function()
	local ok = pcall(import, "CoreLibs/graphics")
	expect.eq(ok, false)
end)

for _, folder in ipairs({ "core", "device" }) do
	test("no playdate.* under source/" .. folder, function()
		local here = arg[0]:match("^(.*)/[^/]*$") or "."
		local dir = here .. "/../../source/" .. folder
		local p = io.popen('ls "' .. dir .. '"')
		local n = 0
		for f in p:lines() do
			if f:match("%.lua$") then
				n = n + 1
				local h = assert(io.open(dir .. "/" .. f))
				local lineNo = 0
				for line in h:lines() do
					lineNo = lineNo + 1
					local code = line:gsub("%-%-.*$", "")
					if code:match("playdate") then
						h:close()
						error("source/" .. folder .. "/" .. f .. ":" .. lineNo .. " uses playdate")
					end
				end
				h:close()
			end
		end
		p:close()
		expect.truthy(n > 0, "found " .. folder .. " files")
	end)
end
