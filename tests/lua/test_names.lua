-- core/names: team names as typed.
import "core/names"
import "core/notation"
local names, notation = tw.names, tw.notation

test("names: clean keeps letters, spaces, hyphens and apostrophes, ten at most", function()
	expect.eq(names.clean("Ash"), "Ash")
	expect.eq(names.clean("  Birch  Tree"), "Birch Tree")
	expect.eq(names.clean("O'Neil-Smith"), "O'Neil-Smi")
	expect.eq(names.clean("R2D2!"), "RD")
	expect.eq(names.clean("abcdefghijklmn"), "abcdefghij")
end)

test("names: finish needs a letter and drops a trailing space", function()
	expect.eq(names.finish("Ash "), "Ash")
	expect.eq(names.finish("   "), nil)
	expect.eq(names.finish("--'"), nil)
	expect.eq(names.finish("Oak"), "Oak")
end)

test("names: the game file id and the engine's teams", function()
	expect.eq(names.id("Birch Tree"), "birch_tree")
	expect.eq(names.id("O'Neil"), "oneil")
	local t = names.teams { A = "Ash", B = "Birch" }
	expect.eq(t.A.name, "Ash")
	expect.eq(t.B.players[1].name, "Birch")
	notation.assignIds(t)
	expect.eq(t.A.players[1].id, "ash")
	local same = names.teams { A = "Oak", B = "Oak" }
	notation.assignIds(same)
	expect.eq(same.B.players[1].id, "oak_b")
end)
