-- The game's version: the same pair as source/pdxinfo (`version` and
-- `buildNumber`), which is the source of truth. tests/lua/test_version.lua
-- fails when the two disagree, and `make release` runs that test first. Raise
-- both together for every release.
--
-- text is what a player sees: the game's version and, in parentheses, the
-- Kubb Engine's ("0.12.0 (0.15.1)"), read from the engine's own version.lua
-- (source/engine/version.lua, vendored with the core at the same tag). The
-- build number is not in the label; where detail is shown it is printed on
-- its own as "build 12".
import "core/tw"
import "engine/version"

local VERSION <const> = "0.12.0"
local BUILD <const> = 12

local engine = tw.engine and tw.engine.version or "?"
tw.version = { version = VERSION, build = BUILD, engine = engine, text = VERSION .. " (" .. engine .. ")" }
