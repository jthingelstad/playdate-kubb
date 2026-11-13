-- Crank traces: one recorded swing per line of traces.jsonl. Pure Lua: no
-- playdate.*, so the game writes lines with trace.encode and desktop tools
-- read them back with trace.decode and replay them with core/swing.
--
-- A line is one JSON object:
--   {"v":1,"time":"2026-11-20 19:42:07","sign":1,"event":"release",
--    "samples":[[0.02,-4.5],[0.02,-6.1],...],
--    "result":{"power":0.91,"smoothness":0.88,"tilt":10.8,"legal":true,
--              "launchSpeed":8.7,"tumbleRate":6.8,"backswing":118,
--              "releaseSpeed":1003,"peakSpeed":1010,"frames":7,"how":"passed",
--              "loft":35,"distance":8.41}}
-- samples are [dt seconds, raw getCrankChange degrees] per frame, from the
-- first frame of the wind-up to the frame of the release or let-down. "sign"
-- is swing.tune.forwardSign at the time. "result" is absent for a let-down;
-- "loft" and "distance" are added by the game once the baton lands.
import "core/tw"
import "core/swing"

local concat, fmt = table.concat, string.format

local trace = {}

local RESULT_KEYS = {
	"power", "powerCap", "smoothness", "tilt", "legal", "launchSpeed", "tumbleRate", "backswing",
	"releaseSpeed", "peakSpeed", "frames", "how", "loft", "distance",
}

local function num(v)
	if v ~= v or v == math.huge or v == -math.huge then return "0" end
	if math.type and math.type(v) == "integer" then return tostring(v) end
	return fmt("%.6g", v)
end

local function value(v)
	local ty = type(v)
	if ty == "number" then return num(v)
	elseif ty == "boolean" then return v and "true" or "false"
	elseif ty == "string" then return '"' .. v:gsub('[%c"\\]', "") .. '"'
	end
	return "null"
end

-- samples: flat {dt1, d1, dt2, d2, ...} with n pairs. result may be nil.
function trace.encode(samples, n, event, result, sign, time)
	local parts = {}
	for i = 1, n do
		parts[i] = "[" .. num(samples[2 * i - 1]) .. "," .. num(samples[2 * i]) .. "]"
	end
	local out = '{"v":1,"time":' .. value(time or "") .. ',"sign":' .. num(sign or 1)
		.. ',"event":' .. value(event or "") .. ',"samples":[' .. concat(parts, ",") .. "]"
	if result then
		local r = {}
		for _, k in ipairs(RESULT_KEYS) do
			if result[k] ~= nil then r[#r + 1] = '"' .. k .. '":' .. value(result[k]) end
		end
		out = out .. ',"result":{' .. concat(r, ",") .. "}"
	end
	return out .. "}"
end

-- A small JSON reader: objects, arrays, numbers, strings without escapes
-- beyond \" and \\, true, false, null. Enough for trace lines.
local function decoder(s)
	local i = 1
	local function ws() i = s:find("[^ \t\r\n]", i) or (#s + 1) end
	local parseValue
	local function parseString()
		local j = i + 1
		local buf = {}
		while true do
			local c = s:sub(j, j)
			if c == "" then error("unterminated string") end
			if c == '"' then break end
			if c == "\\" then j = j + 1; c = s:sub(j, j) end
			buf[#buf + 1] = c
			j = j + 1
		end
		i = j + 1
		return concat(buf)
	end
	function parseValue()
		ws()
		local c = s:sub(i, i)
		if c == "{" then
			i = i + 1
			local o = {}
			ws()
			if s:sub(i, i) == "}" then i = i + 1; return o end
			while true do
				ws()
				local k = parseString()
				ws()
				assert(s:sub(i, i) == ":", "expected :")
				i = i + 1
				o[k] = parseValue()
				ws()
				c = s:sub(i, i)
				i = i + 1
				if c == "}" then return o end
				assert(c == ",", "expected , or }")
			end
		elseif c == "[" then
			i = i + 1
			local a = {}
			ws()
			if s:sub(i, i) == "]" then i = i + 1; return a end
			while true do
				a[#a + 1] = parseValue()
				ws()
				c = s:sub(i, i)
				i = i + 1
				if c == "]" then return a end
				assert(c == ",", "expected , or ]")
			end
		elseif c == '"' then
			return parseString()
		elseif s:sub(i, i + 3) == "true" then i = i + 4; return true
		elseif s:sub(i, i + 4) == "false" then i = i + 5; return false
		elseif s:sub(i, i + 3) == "null" then i = i + 4; return nil
		else
			local a, b = s:find("^-?[%d.]+[eE]?[-+]?%d*", i)
			assert(a, "bad JSON at " .. i)
			i = b + 1
			return tonumber(s:sub(a, b))
		end
	end
	return parseValue
end

function trace.decode(line)
	return decoder(line)()
end

-- Replay a decoded trace through the current swing model. Returns the event
-- and result as swing.replay does. By default the trace's own sign is kept,
-- so a trace recorded before forwardSign was flipped replays as it was
-- thrown; with useCurrentSign the raw deltas meet today's forwardSign.
function trace.replay(t, useCurrentSign)
	local swing = tw.swing
	local flat = {}
	local flip = useCurrentSign and 1 or (t.sign or 1) * swing.tune.forwardSign
	for _, p in ipairs(t.samples or {}) do
		flat[#flat + 1] = p[1]
		flat[#flat + 1] = p[2] * flip
	end
	return swing.replay(flat)
end

tw.trace = trace
