local M = {}
local actions = require("atlas.issues.actions")
local icons = require("atlas.ui.shared.icons")
local metadata = require("atlas.issues.providers.linear.api.metadata")
local notify = require("atlas.core.notify")
local picker = require("atlas.ui.picker")

---@param ctx AtlasIssueActionContext
---@param done fun(result: IssuesActionResult|nil, err: string|nil)
local function create_issue(ctx, done)
	local function open_editor(team)
		require("atlas.issues.providers.linear.ui.editor").open(team, function(result, err)
			done(result and { issue_key = result.key } or nil, err)
		end)
	end

	local issue = ctx.issue
	---@cast issue LinearIssue|nil
	if issue and issue.team and issue.team.id then
		open_editor(issue.team)
		return
	end

	notify.loading("Loading teams...")
	return metadata.list_teams(function(teams, err)
		if not teams then
			err = err or "Unable to load teams"
			notify.error(err)
			done(nil, err)
			return
		end

		notify.clear()
		if #teams == 0 then
			notify.info("No Linear teams found")
			done(nil, nil)
		elseif #teams == 1 then
			open_editor(teams[1])
		else
			picker.select({
				title = "Create Issue - Team",
				items = teams,
				format_item = function(team)
					return team.key .. " - " .. team.name
				end,
				on_select = function(team)
					if team then
						open_editor(team)
					else
						done(nil, nil)
					end
				end,
			})
		end
	end)
end

---@param ctx AtlasIssueActionContext
---@param done fun(result: IssuesActionResult|nil, err: string|nil)
local function edit_issue(ctx, done)
	local issue = ctx.issue
	if not issue then
		done(nil, "No issue selected")
		return
	end

	---@cast issue LinearIssue
	return require("atlas.issues.providers.linear.ui.editor").edit(issue, function(result, err)
		done(result and { issue_key = result.key } or nil, err)
	end)
end

---@type AtlasIssueAction[]
M.items = {
	{ id = "create_issue", label = "Create Issue", icon = icons.get("create", "actions"), run = create_issue },
	{
		id = "edit_issue",
		label = "Edit Issue",
		icon = icons.get("edit", "actions"),
		is_available = function(ctx)
			return ctx.issue ~= nil
		end,
		run = edit_issue,
	},
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
