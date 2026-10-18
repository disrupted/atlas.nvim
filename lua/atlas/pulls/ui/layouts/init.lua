local layouts = {
	compact = require("atlas.pulls.ui.layouts.compact"),
	plain = require("atlas.pulls.ui.layouts.plain"),
	grouped = require("atlas.pulls.ui.layouts.grouped"),
}

local M = {}

---@param layout AtlasPullsViewLayout|nil
---@return AtlasPullsViewLayout
function M.next(layout)
	return ({ compact = "plain", plain = "grouped", grouped = "compact" })[layout] or "plain"
end

---@param opts table
---@param pulls PullRequest[]
---@return string[], table<integer, table>, table[]
function M.render(opts, pulls)
	local layout = layouts[opts.layout] or layouts.compact
	return layout.render(opts, pulls, layout[opts.provider_id] or layout.default)
end

return M
