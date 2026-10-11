local M = {}

local json = require("atlas.core.json")
local users = require("atlas.providers.linear.users")
local icons = require("atlas.ui.shared.icons")
local highlights = require("atlas.ui.highlights")

---@param raw any
---@return IssueRef|nil
local function parent_ref(raw)
	raw = json.safe_table(raw)
	local key = json.safe_str(raw.identifier)
	if key and key ~= "" then
		return { key = key, title = json.safe_str(raw.title) }
	end
end

---@param raw any
---@return LinearIssue|nil
function M.to_issue(raw)
	raw = json.safe_table(raw)
	local key = json.safe_str(raw.identifier)
	if not key or key == "" then
		return nil
	end
	local state = json.safe_table(raw.state)
	local team = json.safe_table(raw.team)
	local team_key = json.safe_str(team.key) or ""
	local team_name = json.safe_str(team.name) or ""
	local project = json.safe_table(raw.project)
	local project_name = json.safe_str(project.name)
	local cycle = json.safe_table(raw.cycle)
	local cycle_name = json.safe_str(cycle.name)
	local cycle_number = tonumber(json.nilify(cycle.number))
	---@type LinearIssue
	local issue = {
		id = json.safe_str(raw.id),
		key = key,
		title = json.safe_str(raw.title) or "",
		icon = {
			icon = icons.get(json.safe_str(state.type) or "", "linear_status"),
			hl_group = highlights.foreground(json.safe_str(state.color)),
		},
		status = json.safe_str(state.name),
		status_id = json.safe_str(state.id),
		status_type = json.safe_str(state.type),
		status_color = json.safe_str(state.color),
		priority = json.safe_str(raw.priorityLabel),
		priority_value = tonumber(json.nilify(raw.priority)),
		team = (team_key ~= "" or team_name ~= "")
				and { id = json.safe_str(team.id), key = team_key, name = team_name }
			or nil,
		project = project_name and project_name ~= "" and { id = json.safe_str(project.id), name = project_name }
			or nil,
		cycle = cycle_number and {
			id = json.safe_str(cycle.id),
			name = cycle_name ~= "" and cycle_name or nil,
			number = cycle_number,
		} or nil,
		assignee = users.to_user(raw.assignee),
		reporter = users.to_user(raw.creator),
		story_points = tonumber(json.nilify(raw.estimate)),
		duedate = json.safe_str(raw.dueDate),
		parent = parent_ref(raw.parent),
		url = json.safe_str(raw.url),
		created_at = json.safe_str(raw.createdAt),
		updated_at = json.safe_str(raw.updatedAt),
		closed_at = json.safe_str(raw.completedAt) or json.safe_str(raw.canceledAt),
	}
	return issue
end

---@param raw any
---@return LinearIssueDetails|nil
function M.to_issue_details(raw)
	if type(json.nilify(raw)) ~= "table" then
		return nil
	end
	local assignee = users.to_user(raw.assignee)
	local issue = M.to_issue(raw) or {}
	local labels = {}
	for _, label in ipairs(json.safe_table(json.safe_table(raw.labels).nodes)) do
		label = json.safe_table(label)
		local name = json.safe_str(label.name)
		if name and name ~= "" then
			table.insert(labels, { id = json.safe_str(label.id), name = name, color = json.safe_str(label.color) })
		end
	end
	---@type LinearIssueDetails
	local details = {
		id = issue.id,
		key = issue.key,
		title = json.safe_str(raw.title),
		description = json.safe_str(raw.description) or "",
		team = issue.team,
		state = issue.status_id
				and { id = issue.status_id, name = issue.status, type = issue.status_type, color = issue.status_color }
			or nil,
		priority_value = issue.priority_value,
		priority = issue.priority,
		project = issue.project,
		cycle = issue.cycle,
		assignees = assignee and { assignee } or {},
		labels = labels,
	}
	return details
end

---@param raw_list any
---@return LinearIssue[]
function M.to_issues_list(raw_list)
	---@type LinearIssue[]
	local issues = {}
	for _, raw in ipairs(json.safe_table(raw_list)) do
		local issue = M.to_issue(raw)
		if issue then
			table.insert(issues, issue)
		end
	end
	return issues
end

return M
