-- core/howtoplay: HOW TO PLAY's cards and their paging.
import "core/howtoplay"
local hp = tw.howtoplay

test("howtoplay: six cards in order, the king and the score sheet last", function()
	local ids = {}
	for i, c in ipairs(hp.CARDS) do ids[i] = c.id end
	expect.eq(table.concat(ids, " "), "pitch batons back field king sheet")
end)

test("howtoplay: words in capitals, plain, short enough for a card", function()
	for _, c in ipairs(hp.CARDS) do
		expect.eq(c.title, c.title:upper(), c.id .. " title")
		expect.truthy(#c.title <= 18, c.id .. ": title fits the display font")
		-- about 36 capitals a line beside the map, 52 without (Roobert 10 Bold,
		-- about 7 px each): a rough bound; render/howtoplay checks the real fit
		local per = c.map and 36 or 52
		local lines = 0
		for i, para in ipairs(c.text) do
			expect.eq(para, para:upper(), c.id .. ": capitals")
			expect.truthy(not para:find("—") and not para:find("!"), c.id .. ": no dashes or shouting")
			lines = lines + math.ceil(#para / per) + (i > 1 and 0.4 or 0)
		end
		expect.truthy(lines <= 9, c.id .. ": " .. lines .. " lines")
	end
end)

test("howtoplay: A and right page on, B and left back; B on the first leaves; A on the last goes to HOW TO THROW", function()
	local st = hp.new()
	expect.eq(hp.press(st, "left"), nil)
	expect.eq(st.page, 1)
	expect.eq(hp.press(st, "a"), nil)
	expect.eq(hp.press(st, "right"), nil)
	expect.eq(st.page, 3)
	expect.eq(hp.press(st, "b"), nil)
	expect.eq(hp.press(st, "left"), nil)
	expect.eq(st.page, 1)
	expect.eq(hp.press(st, "b"), "exit")
	local n = #hp.CARDS
	st.page = n
	expect.eq(hp.press(st, "right"), nil)
	expect.eq(st.page, n)
	expect.eq(hp.press(st, "a"), "howto")
	expect.eq(hp.press(st, "b"), "exit", "B on the last card is done")
end)
