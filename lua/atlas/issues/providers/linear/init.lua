---@class LinearTeam
---@field id string
---@field key string
---@field name string

---@class LinearState
---@field id string
---@field name string
---@field type string
---@field color string
---@field position number|nil

---@class LinearProject
---@field id string
---@field name string

---@class LinearCycle
---@field id string
---@field name string|nil
---@field number number

---@class LinearLabel : IssueLabel
---@field id string

---@class LinearPriority
---@field priority number
---@field label string

---@class LinearIssue : Issue
---@field id string|nil
---@field status_type string|nil
---@field status_color string|nil
---@field priority string|nil
---@field priority_value number|nil
---@field team LinearTeam|nil
---@field project LinearProject|nil
---@field cycle LinearCycle|nil

---@class LinearIssueDetails : IssueDetails
---@field id string|nil
---@field key string|nil
---@field team LinearTeam|nil
---@field state LinearState|nil
---@field priority string|nil
---@field priority_value number|nil
---@field project LinearProject|nil
---@field cycle LinearCycle|nil
---@field labels LinearLabel[]

---@class LinearIssueEditorResult
---@field id string
---@field key string
---@field url string|nil

local config = require("atlas.config")
local issues_api = require("atlas.issues.providers.linear.api.issues")

---@return AtlasLinearIssuesViewConfig[]
local function views()
	local configured = (config.domain_options("linear", "issues") or {}).views
	if not configured or #configured == 0 then
		configured = {
			{
				name = "Assigned",
				key = "1",
				layout = "compact",
				filter = {
					assignee = { isMe = { eq = true } },
					state = { type = { ["in"] = { "triage", "backlog", "unstarted", "started" } } },
				},
			},
			{ name = "All", key = "2", layout = "compact" },
		}
	end
	return vim.deepcopy(configured)
end

---@param target AtlasTarget
---@return AtlasLinearIssuesViewConfig
local function view_for_target(target)
	local key = target.issue_key or target.id
	return { name = "Issue", layout = "compact", search = key and tostring(key) or nil }
end

---@param target AtlasTarget
---@return IssueRef|nil
local function issue_ref(target)
	local key = target.issue_key or target.id
	if key ~= nil and tostring(key) ~= "" then
		return { key = tostring(key) }
	end
end

---@param view AtlasLinearIssuesViewConfig
---@param opts IssuesFetchOpts
---@param on_done fun(page: IssuesPage, err: string|nil)
---@return { cancel: fun() }|nil
local function fetch_issues(view, opts, on_done)
	return issues_api.list_issues(view, opts, function(page, err)
		local scope = {
			search = view.search,
			filter = view.filter,
			order_by = view.order_by,
			include_archived = view.include_archived,
		}
		local ok, query = pcall(vim.json.encode, scope)
		page.query = next(scope) and (ok and query or "Invalid Linear filters") or "All issues"
		on_done(page, err)
	end)
end

return {
	views = views,
	view_for_target = view_for_target,
	issue_ref = issue_ref,
	capabilities = {
		actions = require("atlas.issues.providers.linear.actions.registry"),
		core = {
			fetch_issues = fetch_issues,
			fetch_by_refs = issues_api.fetch_by_refs,
			fetch_issue = issues_api.fetch_issue,
			-- fetch_links = nil,
		},
		-- comments = {
		-- 	fetch_activity = nil,
		-- 	fetch_conversation = nil,
		-- 	add_comment = nil,
		-- 	edit_comment = nil,
		-- 	delete_comment = nil,
		-- 	reactions = nil,
		-- },
		ui = {
			detail = require("atlas.issues.providers.linear.ui.detail"),
			-- repository = nil,
		},
	},
}
