local resolver = require("atlas.providers.linear.resolve")
local users = require("atlas.providers.linear.users")

---@type AtlasProvider
return {
	id = "linear",
	name = "Linear",
	hostname = function()
		return "linear.app"
	end,
	resolver = resolver,
	domains = {
		issues = {
			module = "atlas.issues.providers.linear",
			--- TODO: Find better icon maybe ?
			icon = { icon = "◩", hl_group = "AtlasLinearTheme" },
			bookmark_key = "S",
			bookmark_label = "Search",
		},
	},
	capabilities = {
		-- repository = nil,
		-- notifications = nil,
		users = users,
		-- completion = nil,
	},
}
