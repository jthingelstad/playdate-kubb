-- Pinned physics cases: every tests/lua/physcases/*.lua, run through
-- tools/physcheck.lua (the checks physfuzz makes). A case is plain data:
--
--   return {
--     name = "...", surface = "grass", stakes = true, texture = nil,
--     pieces = { { id, kind, x, y, z?, qw..qz? | yaw?, toppled? }, ... },
--     throws = { { groundSeed = n, state = { ... } }          -- a captured launch
--              | { groundSeed = n, plan = { px, py, tx, ty, release, aimZ }, tumble? } },
--     expect = { toppled = { ids }   -- exactly these toppled, every throw
--              | hits = id,          -- at least this one toppled, every throw
--              clean = true },       -- and no check found anything
--   }
--
-- How to make one from a fuzz failure or a replayed report: docs/notes/physics-fuzz.md,
-- "Physics fuzz".
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local physcheck = assert(loadfile(here .. "/../../tools/physcheck.lua"))()

local function caseFiles()
	local files = {}
	local p = io.popen('ls "' .. here .. '/physcases"')
	for f in p:lines() do
		if f:match("%.lua$") then files[#files + 1] = f end
	end
	p:close()
	table.sort(files)
	return files
end

local function describe(f)
	return string.format("%s / %s: %s", f.check, f.sub, f.detail)
end

for _, file in ipairs(caseFiles()) do
	local case = assert(loadfile(here .. "/physcases/" .. file))()
	test("physcase " .. file:gsub("%.lua$", "") .. ": " .. case.name, function()
		local ex = case.expect or {}
		for i, out in ipairs(physcheck.runCase(case)) do
			local toppled = {}
			for _, id in ipairs(out.result.toppled) do toppled[#toppled + 1] = id end
			table.sort(toppled)
			local got = table.concat(toppled, ",")
			local what = "throw " .. i
			if ex.toppled then
				local want = {}
				for _, id in ipairs(ex.toppled) do want[#want + 1] = id end
				table.sort(want)
				expect.eq(got, table.concat(want, ","), what .. " toppled")
			end
			if ex.hits then
				local hit = false
				for _, id in ipairs(toppled) do if id == ex.hits then hit = true end end
				expect.truthy(hit, what .. " toppled " .. ex.hits .. " (toppled: " .. (got == "" and "none" or got) .. ")")
			end
			if ex.clean then
				local lines = {}
				for _, f in ipairs(out.findings) do lines[#lines + 1] = describe(f) end
				expect.truthy(#lines == 0, what .. " is clean: " .. table.concat(lines, "; "))
			end
		end
	end)
end
