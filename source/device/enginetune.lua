-- The Playdate's own settings of the Kubb Engine's tune tables: every play the
-- engine offers that this game switches off on the device because it stalls a
-- frame, each with the measurement that justified it (docs/notes/performance.md
-- "Engine 0.13 on the device"). The one place they are set; source/core is never
-- edited (it is the engine's tag, byte for byte). Imported once by main.lua, so
-- the game, its self-tests and the device checks all run with them. Pure: no
-- playdate.*; tests/lua/test_enginetune.lua holds them.
--
-- Measured on the device with the performance check (perfbench), engine 0.9.0
-- against 0.13.1, 2026-11-21, eight kubbs lying in a tight group:
--   one raise decision: apart 0.9 ms, par 33 ms (cpu.raise at pro the same);
--   the settle of the eight in one call (match.settle, the frame the match
--   scene makes it in at the end of a turn): 292 ms on 0.9 at every level,
--   on 0.13.1 290 / 297 ms with the Playdate at beginner / club, 490 ms at pro
--   and 482 ms for a person's kubbs (the engine's advice, par);
--   that transition frame through the match scene: 356 ms on 0.9, 550 ms with
--   the Playdate pro raising, 535 ms for a person's kubbs raised by RAISING:
--   AUTOMATIC.
-- The frame budget is 20 ms while aiming (50 fps) and 40 ms in flight
-- (throw.tune), and the soak counts frames over 100 and 200 ms as slow; the
-- transition was already over both on 0.9, and par adds about 200 ms to it, a
-- half-second freeze. The match scene has no way to spread it (match.setup
-- makes every raise in one call, with the screen still), so:
import "core/tw"
import "core/cpu"

local enginetune = {}

-- 1. The Playdate at pro raises `apart`, as on engine 0.11, not `par` (cpu.raising,
-- 0.12). Nothing is lost in strength: against 0.12's attacker `par` and `apart` are
-- level at pro (kubb-engine docs/VERSIONING.md 0.12.0: 50.3% and 51.8%).
enginetune.proRaising = "apart"
tw.cpu.raising.pro = enginetune.proRaising

-- 2. A person's kubbs raised by the match option RAISING: AUTOMATIC (match.setup, in
-- one call) go up `apart`, not by the engine's advice (cpu.advice, par): scenes/match
-- names this for a person's sides in core/match's `raising` when the match raises
-- automatically. The advice stays everywhere it is spread over frames: the end the
-- raise view offers first and REST OF GAME (one kubb a view, 33 ms each).
enginetune.autoRaising = "apart"

-- Kept on (measured, no stall): field.line and inkast.depth at pro (cpu.tune.line,
-- cpu.tune.depth). autothrow.choose with eight field kubbs standing in a tight group:
-- 15 ms on 0.9, 50 ms at pro on 0.13.1 (17 at club); the Playdate's choose frame 55
-- to 89 ms, once, while its aim is shown still for cpuThink (0.9 s): under the 100 ms
-- the soak counts.

tw.enginetune = enginetune
