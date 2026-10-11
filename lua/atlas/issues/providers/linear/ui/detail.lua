---@type IssuesProviderDetail
local M = {}

local icons = require("atlas.ui.shared.icons")
local highlights = require("atlas.ui.highlights")
local utils = require("atlas.ui.shared.utils")
local helper = require("atlas.issues.ui.presentation")

---@param issue Issue
---@param details IssueDetails|nil
---@param _loading boolean
---@return IssuesDetailHeaderField[]
function M.header_fields(issue, details, _loading)
	---@cast issue LinearIssue
	---@cast details LinearIssueDetails|nil
	local assignee = issue.assignee
	if details then
		assignee = details.assignees[1]
	end
	local fields = {
		{
			label = "Status",
			value = string.format(
				"%s %s",
				issue.icon and issue.icon.icon or icons.get("issue"),
				issue.status or "Unknown"
			),
			hl = issue.icon and issue.icon.hl_group or "AtlasTextMuted",
		},
	}
	local priority = issue.priority
	if priority and priority ~= "" and priority ~= "No priority" then
		local icon, hl = icons.get(priority, "priority")
		table.insert(fields, {
			label = "Priority",
			value = icon ~= "" and string.format("%s %s", icon, priority) or priority,
			hl = hl,
		})
	end
	local reporter = issue.reporter
	table.insert(fields, {
		label = "Reporter",
		value = reporter and reporter.name or "Unknown",
		hl = helper.person_hl(reporter),
	})
	table.insert(fields, {
		label = "Assignee",
		value = assignee and assignee.name or "Unassigned",
		hl = helper.person_hl(assignee),
	})
	table.insert(fields, {
		label = "Created",
		value = utils.relative_time_text(issue.created_at),
		hl = "AtlasTextMuted",
	})
	table.insert(fields, {
		label = "Updated",
		value = utils.relative_time_text(issue.updated_at),
		hl = "AtlasTextMuted",
	})
	return fields
end

---@param issue Issue
---@param details IssueDetails|nil
---@param _loading boolean
---@return IssuesDetailChip[]
function M.chips(issue, details, _loading)
	---@cast details LinearIssueDetails|nil
	local chips = {}
	local parent_key = issue.parent and issue.parent.key
	if parent_key then
		table.insert(chips, {
			label = string.format("%s %s", icons.get("branch"), parent_key),
			hl = "AtlasLinearTheme",
		})
	end
	for _, label in ipairs(details and details.labels or {}) do
		if label.name ~= "" then
			table.insert(chips, { label = label.name, hl = highlights.chip(label.color) })
		end
	end
	return chips
end

---@return IssuesDetailTabDefinition[]
function M.tabs()
	return {
		{
			key = "overview",
			label = "Overview",
			icon = { icon = icons.get("overview") },
			mod = require("atlas.issues.ui.detail.tabs.overview"),
		},
	}
end

return M
