-- Checks on the harness and the pure-core rule themselves.

test("import runs a file once and returns its value only the first time", function()
	-- Test bodies run after every test file has loaded, and test_vec.lua
	-- imports core/vec (which imports core/tw), so this import returns nil,
	-- as a repeated import does on the Playdate.
	import "core/tw"
	expect.eq(import "core/tw", nil)
	expect.truthy(type(tw) == "table", "tw namespace exists")
end)

test("core/ cannot import CoreLibs", function()
	local ok = pcall(import, "CoreLibs/graphics")
	expect.eq(ok, false)
end)

test("no playdate.* under source/core", function()
	local here = arg[0]:match("^(.*)/[^/]*$") or "."
	local dir = here .. "/../../source/core"
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
					error("source/core/" .. f .. ":" .. lineNo .. " uses playdate")
				end
			end
			h:close()
		end
	end
	p:close()
	expect.truthy(n > 0, "found core files")
end)
