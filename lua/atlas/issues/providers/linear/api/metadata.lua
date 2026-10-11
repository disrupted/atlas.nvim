local M = {}

local service = require("atlas.providers.linear.client")
local json = require("atlas.core.json")
local requests = require("atlas.core.requests")
local users = require("atlas.providers.linear.users")

---@param query string
---@param variables table
---@param on_done fun(items: table[]|nil, err: string|nil)
---@return AtlasRequestScope
local function fetch_all(query, variables, on_done)
	local scope = requests.new()
	local items = {}
	local function fetch_page()
		scope.run(function(done)
			return service.graphql(query, variables, done, { action = "Fetch issue metadata" })
		end, function(data, err)
			if err then
				on_done(nil, err)
				return
			end
			local connection = json.safe_table(json.safe_table(data.team or data).items)
			if type(json.nilify(connection.nodes)) ~= "table" then
				on_done(nil, "Invalid Linear metadata response")
				return
			end
			vim.list_extend(items, connection.nodes)
			local page_info = json.safe_table(connection.pageInfo)
			if page_info.hasNextPage then
				variables.after = json.safe_str(page_info.endCursor)
				if not variables.after then
					on_done(nil, "Missing Linear metadata cursor")
					return
				end
				fetch_page()
			else
				on_done(items, nil)
			end
		end)
	end
	fetch_page()
	return scope
end

---@param team_id string
---@param field string
---@param selection string
---@param on_done fun(items: table[]|nil, err: string|nil)
---@return AtlasRequestScope
local function team_items(team_id, field, selection, on_done)
	local query = string.format(
		[[query AtlasLinearTeamMetadata($id: String!, $after: String) {
  team(id: $id) {
    items: %s(first: 100, after: $after, includeArchived: false) {
      nodes { %s }
      pageInfo { hasNextPage endCursor }
    }
  }
}]],
		field,
		selection
	)
	return fetch_all(query, { id = team_id }, on_done)
end

---@param on_done fun(teams: LinearTeam[]|nil, err: string|nil)
---@return AtlasRequestScope
function M.list_teams(on_done)
	return fetch_all(
		[[query AtlasLinearTeams($after: String) {
  items: teams(first: 100, after: $after, includeArchived: false) {
    nodes { id key name }
    pageInfo { hasNextPage endCursor }
  }
}]],
		{},
		on_done
	)
end

---@param team_id string
---@param on_done fun(states: LinearState[]|nil, err: string|nil)
---@return AtlasRequestScope
function M.list_states(team_id, on_done)
	return team_items(team_id, "states", "id name type color position", function(items, err)
		if not items then
			on_done(nil, err)
			return
		end
		local order =
			{ triage = 1, backlog = 2, unstarted = 3, started = 4, completed = 5, canceled = 6, duplicate = 7 }
		table.sort(items, function(a, b)
			if a.type == b.type then
				return a.position < b.position
			end
			return order[a.type] < order[b.type]
		end)
		on_done(items, nil)
	end)
end

---@param team_id string
---@param on_done fun(members: AtlasUser[]|nil, err: string|nil)
---@return AtlasRequestScope
function M.list_members(team_id, on_done)
	return team_items(team_id, "members", "id name displayName", function(items, err)
		if not items then
			on_done(nil, err)
			return
		end
		local members = {}
		for _, item in ipairs(items) do
			table.insert(members, users.to_user(item))
		end
		on_done(members, nil)
	end)
end

---@param team_id string
---@param on_done fun(labels: LinearLabel[]|nil, err: string|nil)
---@return AtlasRequestScope
function M.list_labels(team_id, on_done)
	return fetch_all(
		[[query AtlasLinearLabels($filter: IssueLabelFilter!, $after: String) {
  items: issueLabels(filter: $filter, first: 100, after: $after, includeArchived: false) {
    nodes { id name color }
    pageInfo { hasNextPage endCursor }
  }
}]],
		{
			filter = {
				isGroup = { eq = false },
				["or"] = { { team = { id = { eq = team_id } } }, { team = { null = true } } },
			},
		},
		on_done
	)
end

---@param team_id string
---@param on_done fun(projects: LinearProject[]|nil, err: string|nil)
---@return AtlasRequestScope
function M.list_projects(team_id, on_done)
	return team_items(team_id, "projects", "id name", on_done)
end

---@param team_id string
---@param on_done fun(cycles: LinearCycle[]|nil, err: string|nil)
---@return AtlasRequestScope
function M.list_cycles(team_id, on_done)
	return team_items(team_id, "cycles", "id name number", function(items, err)
		if not items then
			on_done(nil, err)
			return
		end
		for _, item in ipairs(items) do
			item.name = json.safe_str(item.name)
		end
		on_done(items, nil)
	end)
end

---@param on_done fun(priorities: LinearPriority[]|nil, err: string|nil)
---@return { cancel: fun() }|nil
function M.list_priorities(on_done)
	return service.graphql(
		"query AtlasLinearPriorities { issuePriorityValues { priority label } }",
		nil,
		function(data, err)
			on_done(data and data.issuePriorityValues or nil, err)
		end,
		{ action = "List issue priorities" }
	)
end

return M
