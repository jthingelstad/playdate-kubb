-- The game's version: the same pair as source/pdxinfo (`version` and
-- `buildNumber`), which is the source of truth. tests/lua/test_version.lua
-- fails when the two disagree, and `make release` runs that test first. Raise
-- both together for every release.
--
-- text is what a player sees: the game's version and, in parentheses, the
-- Kubb Engine's ("0.9.8 (0.8.2)"), read from the engine's own version.lua
-- (source/engine/version.lua, vendored with the core at the same tag). The
-- build number is not in the label; where detail is shown it is printed on
-- its own as "build 9".
import "core/tw"
import "engine/version"

local VERSION <const> = "0.9.8"
local BUILD <const> = 9

local engine = tw.engine and tw.engine.version or "?"
tw.version = { version = VERSION, build = BUILD, engine = engine, text = VERSION .. " (" .. engine .. ")" }
