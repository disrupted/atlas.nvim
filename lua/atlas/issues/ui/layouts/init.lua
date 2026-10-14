local layouts = {
	plain = require("atlas.issues.ui.layouts.plain"),
	compact = require("atlas.issues.ui.layouts.compact"),
	board = require("atlas.issues.ui.layouts.board"),
}

local M = {}

---@param layout AtlasIssuesViewLayout|nil
---@param provider_id string|nil
---@return AtlasIssuesViewLayout
function M.resolve(layout, provider_id)
	layout = layout or "plain"
	local module = layouts[layout]
	if module and (module[provider_id] or module.default) then
		return layout
	end
	return "plain"
end

---@param layout AtlasIssuesViewLayout|nil
---@param provider_id string|nil
---@return AtlasIssuesViewLayout
function M.next(layout, provider_id)
	local next_layout = { plain = "compact", compact = "board", board = "plain" }
	return M.resolve(next_layout[M.resolve(layout, provider_id)], provider_id)
end

---@param opts table
---@param issues Issue[]
---@return string[], table<integer, table>, table[]
function M.render(opts, issues)
	local layout = layouts[M.resolve(opts.layout, opts.provider_id)]
	return layout.render(opts, issues, layout[opts.provider_id] or layout.default)
end

return M
