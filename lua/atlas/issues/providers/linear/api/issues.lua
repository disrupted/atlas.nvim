local M = {}

local service = require("atlas.providers.linear.client")
local mapper = require("atlas.issues.providers.linear.api.mapper")
local json = require("atlas.core.json")
local request_scope = require("atlas.core.requests")
local memory_cache = require("atlas.core.memory_cache")

local ISSUE_FIELDS = [[
  id identifier title url
  createdAt updatedAt completedAt canceledAt dueDate estimate priority priorityLabel
  state { id name type color }
  assignee { id name displayName }
  creator { id name displayName }
  parent { identifier title }
  team { id key name }
  project { id name }
  cycle { id name number }
]]

local LIST_QUERY = [[
query AtlasLinearIssues($filter: IssueFilter, $first: Int!, $after: String, $orderBy: PaginationOrderBy, $includeArchived: Boolean) {
  issues(filter: $filter, first: $first, after: $after, orderBy: $orderBy, includeArchived: $includeArchived) {
    nodes { %s }
    pageInfo { hasNextPage endCursor }
  }
}
]]

local SEARCH_QUERY = [[
query AtlasLinearSearchIssues($term: String!, $filter: IssueFilter, $first: Int!, $after: String, $orderBy: PaginationOrderBy, $includeArchived: Boolean) {
  searchIssues(term: $term, filter: $filter, first: $first, after: $after, orderBy: $orderBy, includeArchived: $includeArchived) {
    nodes { %s }
    pageInfo { hasNextPage endCursor }
  }
}
]]

local ISSUE_QUERY = [[
query AtlasLinearIssue($id: String!) {
  issue(id: $id) {
    %s
    description
    labels(first: 100) { nodes { id name color } }
  }
}
]]

---@param ref IssueRef
---@param opts IssuesFetchOpts|nil
---@param on_done fun(raw: table|nil, err: string|nil)
---@return { cancel: fun() }|nil
local function fetch_raw_issue(ref, opts, on_done)
	local key = json.safe_str(ref.key) or ""
	if key == "" then
		on_done(nil, "Missing issue key")
		return nil
	end
	local cache_key = "linear:issue:" .. key
	if not (opts and opts.force_refresh) then
		local cached, hit = service.get_cache(cache_key)
		if hit then
			on_done(cached, nil)
			return nil
		end
	end
	return service.graphql(string.format(ISSUE_QUERY, ISSUE_FIELDS), { id = key }, function(data, err)
		if err then
			on_done(nil, err)
			return
		end
		local raw = json.safe_table(data).issue
		if not mapper.to_issue(raw) then
			on_done(nil, "Invalid Linear issue response")
			return
		end
		service.set_cache(cache_key, raw)
		on_done(raw, nil)
	end, { action = "Fetch issue", issue_key = key })
end

---@param view AtlasLinearIssuesViewConfig
---@param opts { force_refresh?: boolean, pagelen: integer, cursor?: string }
---@param on_done fun(page: IssuesPage, err: string|nil)
---@return { cancel: fun() }|nil
function M.list_issues(view, opts, on_done)
	local term = vim.trim(view.search or "")
	local searching = term ~= ""
	local filter = view.filter
	if type(filter) == "table" and next(filter) == nil then
		filter = nil
	end
	local variables = {
		term = searching and term or nil,
		filter = filter,
		first = opts.pagelen or 50,
		after = opts.cursor,
		orderBy = view.order_by,
		includeArchived = view.include_archived == true,
	}
	local encoded, value = pcall(vim.json.encode, variables)
	if not encoded then
		on_done({ items = {} }, "Invalid Linear issue filter: " .. tostring(value))
		return nil
	end
	local cache_key = "linear:issues:" .. value
	if not opts.force_refresh then
		local cached, hit = service.get_cache(cache_key)
		if hit then
			on_done(cached, nil)
			return nil
		end
	end
	local query = string.format(searching and SEARCH_QUERY or LIST_QUERY, ISSUE_FIELDS)
	return service.graphql(query, variables, function(data, err)
		if err then
			on_done({ items = {} }, err)
			return
		end
		local connection = json.nilify(json.safe_table(data)[searching and "searchIssues" or "issues"])
		if type(connection) ~= "table" or type(json.nilify(connection.nodes)) ~= "table" then
			on_done({ items = {} }, "Invalid Linear issues response")
			return
		end
		local page_info = json.safe_table(connection.pageInfo)
		local page = {
			items = mapper.to_issues_list(connection.nodes),
			next_cursor = page_info.hasNextPage == true and json.safe_str(page_info.endCursor) or nil,
		}
		service.set_cache(cache_key, page)
		on_done(page, nil)
	end, { action = "List issues" })
end

---@param refs IssueRef[]
---@param opts IssuesFetchOpts|nil
---@param on_done fun(issues: LinearIssue[], err: string|nil)
---@return { cancel: fun() }|nil
function M.fetch_by_refs(refs, opts, on_done)
	if #refs == 0 then
		on_done({}, nil)
		return nil
	end
	local starts = {}
	for index, ref in ipairs(refs) do
		starts[tostring(index)] = function(done)
			return fetch_raw_issue(ref, opts, done)
		end
	end
	local requests = request_scope.new()
	requests.all(starts, function(values, errors)
		---@type LinearIssue[]
		local issues = {}
		local err
		for index in ipairs(refs) do
			local key = tostring(index)
			err = err or errors[key]
			local issue = mapper.to_issue(values[key])
			if issue then
				table.insert(issues, issue)
			end
		end
		on_done(issues, err)
	end)
	return requests
end

---@param ref IssueRef
---@param opts IssuesFetchOpts|nil
---@param on_done fun(details: LinearIssueDetails|nil, err: string|nil)
---@return { cancel: fun() }|nil
function M.fetch_issue(ref, opts, on_done)
	return fetch_raw_issue(ref, opts, function(raw, err)
		on_done(mapper.to_issue_details(raw), err)
	end)
end

---@param query string
---@param variables table
---@param field string
---@param on_done fun(result: LinearIssueEditorResult|nil, err: string|nil)
---@return { cancel: fun() }|nil
local function mutate_issue(query, variables, field, on_done)
	return service.graphql(query, variables, function(data, err)
		if err then
			on_done(nil, err)
			return
		end
		local payload = json.safe_table(json.safe_table(data)[field])
		local issue = mapper.to_issue(payload.issue)
		if payload.success ~= true or not issue or not issue.id then
			on_done(nil, "Failed to save Linear issue")
			return
		end
		memory_cache.clear_prefix("linear:issue:")
		memory_cache.clear_prefix("linear:issues:")
		on_done({ id = issue.id, key = issue.key, url = issue.url }, nil)
	end, { action = field == "issueCreate" and "Create issue" or "Update issue", issue_key = variables.id })
end

---@param fields table
---@param on_done fun(result: LinearIssueEditorResult|nil, err: string|nil)
---@return { cancel: fun() }|nil
function M.create_issue(fields, on_done)
	return mutate_issue(
		[[mutation AtlasLinearCreateIssue($input: IssueCreateInput!) {
  issueCreate(input: $input) { success issue { id identifier url } }
}]],
		{ input = fields },
		"issueCreate",
		on_done
	)
end

---@param key string
---@param fields table
---@param on_done fun(result: LinearIssueEditorResult|nil, err: string|nil)
---@return { cancel: fun() }|nil
function M.update_issue(key, fields, on_done)
	return mutate_issue(
		[[mutation AtlasLinearUpdateIssue($id: String!, $input: IssueUpdateInput!) {
  issueUpdate(id: $id, input: $input) { success issue { id identifier url } }
}]],
		{ id = key, input = fields },
		"issueUpdate",
		on_done
	)
end

return M
