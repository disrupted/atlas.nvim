local emojis = require("atlas.ui.shared.emojis")
local source = require("atlas.completion.sources.emojis")

describe("emoji completion", function()
	local function complete(query)
		local result
		source.complete({ provider = "github" }, query, function(items)
			result = items
		end)
		return result
	end

	it("triggers on a colon", function()
		assert.same({ ":" }, source.triggers)
	end)

	it("lists every emoji name as a shortcode", function()
		local items = complete("thu")
		assert.equals(#emojis.names(), #items)

		local thumbsup
		for _, item in ipairs(items) do
			if item.filter_text == "thumbsup" then
				thumbsup = item
			end
		end
		assert.same({
			label = emojis.get("thumbsup") .. " thumbsup",
			insert_text = ":thumbsup:",
			filter_text = "thumbsup",
		}, thumbsup)
	end)

	it("lists every emoji right after the colon", function()
		assert.equals(#emojis.names(), #complete(""))
	end)
end)
