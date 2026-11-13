-- Desktop test runner for source/core, on plain Lua 5.4.
--   lua5.4 tests/lua/run.lua [test_file.lua ...]
-- With no arguments it runs every tests/lua/test_*.lua. Exits non-zero if any
-- test fails. No dependencies.

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local root = here .. "/../.."
local sourceDir = root .. "/source"

-- The import shim. Playdate's `import "core/vec"` runs source/core/vec.lua
-- once and returns its value the first time, nil after (Inside Playdate 4.2).
-- This does the same from the source/ folder, so core files run unchanged.
local imported = {}
function import(name)
	name = name:gsub("%.lua$", "")
	if name:match("^CoreLibs/") then
		error("import \"" .. name .. "\": CoreLibs is Playdate-only; core/ must stay pure Lua", 2)
	end
	if imported[name] then return nil end
	imported[name] = true
	local chunk, err = loadfile(sourceDir .. "/" .. name .. ".lua")
	if not chunk then error("import \"" .. name .. "\": " .. err, 2) end
	return chunk()
end

-- A tiny assert-based harness.
local tests = {}
function test(name, fn) tests[#tests + 1] = { name = name, fn = fn, file = CURRENT_FILE } end

expect = {}
function expect.eq(actual, expected, what)
	if actual ~= expected then
		error(string.format("%sexpected %s, got %s", what and (what .. ": ") or "",
			tostring(expected), tostring(actual)), 2)
	end
end
function expect.near(actual, expected, tol, what)
	tol = tol or 1e-9
	if type(actual) ~= "number" or math.abs(actual - expected) > tol then
		error(string.format("%sexpected %s +/- %g, got %s", what and (what .. ": ") or "",
			tostring(expected), tol, tostring(actual)), 2)
	end
end
function expect.truthy(v, what)
	if not v then error((what or "expected a true value") .. ", got " .. tostring(v), 2) end
end

local function listTests()
	local files = {}
	local p = io.popen('ls "' .. here .. '"')
	for f in p:lines() do
		if f:match("^test_.*%.lua$") then files[#files + 1] = here .. "/" .. f end
	end
	p:close()
	table.sort(files)
	return files
end

local files = {}
for i = 1, #arg do files[#files + 1] = arg[i] end
if #files == 0 then files = listTests() end

local loadFailures = 0
for _, f in ipairs(files) do
	CURRENT_FILE = f:match("[^/]*$")
	local chunk, err = loadfile(f)
	local ok = chunk ~= nil
	if ok then ok, err = pcall(chunk) end
	if not ok then
		loadFailures = loadFailures + 1
		print("FAIL " .. CURRENT_FILE .. " (load): " .. tostring(err))
	end
end

local passed, failed = 0, 0
for _, t in ipairs(tests) do
	local ok, err = pcall(t.fn)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL " .. t.file .. ": " .. t.name .. "\n     " .. tostring(err))
	end
end
failed = failed + loadFailures
print(string.format("lua: %d passed, %d failed (%d files)", passed, failed, #files))
os.exit(failed == 0 and 0 or 1)
