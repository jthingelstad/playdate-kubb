-- A small JSON writer for tools/mjref (no reader: Python reads what this
-- writes). Tables with a positive length are arrays, the rest objects with
-- their keys sorted, so the same numbers give the same file. json.EMPTY is
-- an empty array.
local json = {}

json.EMPTY = setmetatable({}, { __json = "[]" })

local function num(v)
	if v ~= v or v == math.huge or v == -math.huge then return "null" end
	if math.type(v) == "integer" then return tostring(v) end
	return string.format("%.10g", v)
end

local function str(s)
	return '"' .. s:gsub('[%c"\\]', function(c)
		if c == '"' then return '\\"' elseif c == "\\" then return "\\\\"
		elseif c == "\n" then return "\\n" else return string.format("\\u%04x", c:byte()) end
	end) .. '"'
end

local function enc(v, out)
	local t = type(v)
	if t == "number" then out[#out + 1] = num(v)
	elseif t == "string" then out[#out + 1] = str(v)
	elseif t == "boolean" then out[#out + 1] = v and "true" or "false"
	elseif t == "nil" then out[#out + 1] = "null"
	elseif t == "table" then
		local mt = getmetatable(v)
		if mt and mt.__json then out[#out + 1] = mt.__json; return end
		if #v > 0 then
			out[#out + 1] = "["
			for i = 1, #v do
				if i > 1 then out[#out + 1] = "," end
				enc(v[i], out)
			end
			out[#out + 1] = "]"
		else
			local keys = {}
			for k in pairs(v) do keys[#keys + 1] = tostring(k) end
			table.sort(keys)
			out[#out + 1] = "{"
			for i, k in ipairs(keys) do
				if i > 1 then out[#out + 1] = "," end
				out[#out + 1] = str(k)
				out[#out + 1] = ":"
				local val = v[k]
				if val == nil then val = v[tonumber(k)] end
				enc(val, out)
			end
			out[#out + 1] = "}"
		end
	else
		error("json: cannot encode a " .. t)
	end
end

function json.encode(v)
	local out = {}
	enc(v, out)
	return table.concat(out)
end

-- A list of numbers at a fixed precision (traces: smaller and faster).
function json.numbers(list, fmt)
	local parts = {}
	for i = 1, #list do
		local v = list[i]
		parts[i] = (v ~= v) and "null" or string.format(fmt or "%.6g", v)
	end
	return "[" .. table.concat(parts, ",") .. "]"
end

return json
