local M = {}
local actions = require("atlas.issues.actions")

---@type AtlasIssueAction[]
M.items = {
	actions.browse_issue,
	actions.copy_issue_key,
	actions.copy_issue_url,
}

---@param id string
---@return AtlasIssueAction|nil
function M.find(id)
	for _, action in ipairs(M.items) do
		if action.id == id then
			return action
		end
	end
	return nil
end

return M
