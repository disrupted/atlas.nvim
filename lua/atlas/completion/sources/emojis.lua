local emojis = require("atlas.ui.shared.emojis")

---@type AtlasCompletionSource
return {
	triggers = { ":" },
	complete = function(_, _, done)
		local items = {}
		for _, name in ipairs(emojis.names()) do
			items[#items + 1] = {
				label = emojis.get(name) .. " " .. name,
				insert_text = ":" .. name .. ":",
				filter_text = name,
			}
		end
		done(items, nil)
		return nil
	end,
}
