-- Loads the game's core (source/core) for the tools/mjref Lua scripts, with
-- the same import shim as tools/batonprobe.lua, and returns the helpers they
-- share: json, cases and the mode's surface.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local sourceDir = here .. "/../../source"
local imported = {}
function import(name)
	if imported[name] then return nil end
	imported[name] = true
	return assert(loadfile(sourceDir .. "/" .. name .. ".lua"))()
end
import "core/tw"
import "core/world"
import "core/collide"
import "core/flight"
import "core/drill"
import "core/throwplan"

local M = {}
M.json = dofile(here .. "/json.lua")
M.cases = dofile(here .. "/cases.lua")

-- The surface table for a mode. "mech": the flat plane (no texture) without
-- the turf's dig and bite, the mechanics MuJoCo can also model; rolling
-- resistance (roll) stays, MuJoCo has it too. "game": the surface as played.
function M.surface(name, mode)
	local s = tw.world.surfaces[name]
	if mode == "game" then return s end
	local flat = {}
	for k, v in pairs(s) do flat[k] = v end
	flat.texture, flat.dig, flat.bite = nil, 0, 0
	return flat
end

return M
