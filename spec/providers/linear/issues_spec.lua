local api_name = "atlas.issues.providers.linear.api.issues"
local client_name = "atlas.providers.linear.client"
local memory_cache = require("atlas.core.memory_cache")

describe("Linear issues", function()
	local previous_api, previous_client, previous_encode, previous_clear
	local api, calls, cache, cleared

	local function raw_issue(key)
		return { id = key .. "-uuid", identifier = key, title = key .. " title", description = "Details" }
	end

	local function respond(index, key)
		calls[index].done({ issue = raw_issue(key) }, nil)
	end

	before_each(function()
		previous_api = package.loaded[api_name]
		previous_client = package.loaded[client_name]
		previous_encode = vim.json.encode
		previous_clear = memory_cache.clear_prefix
		calls = {}
		cache = {}
		cleared = {}
		memory_cache.clear_prefix = function(prefix)
			table.insert(cleared, prefix)
		end
		package.loaded[client_name] = {
			graphql = function(query, variables, done)
				local call = { query = query, variables = variables, done = done }
				call.handle = {
					cancel = function()
						call.cancelled = true
					end,
				}
				table.insert(calls, call)
				return call.handle
			end,
			get_cache = function(key)
				return cache[key], cache[key] ~= nil
			end,
			set_cache = function(key, value)
				cache[key] = value
			end,
		}
		package.loaded[api_name] = nil
		api = require(api_name)
	end)

	after_each(function()
		package.loaded[api_name] = previous_api
		package.loaded[client_name] = previous_client
		vim.json.encode = previous_encode
		memory_cache.clear_prefix = previous_clear
	end)

	it("passes native filters and pagination as variables and preserves cancellation", function()
		local filter = { team = { key = { eq = "ENG" } }, assignee = { isMe = { eq = true } } }
		local result, failure
		local handle = api.list_issues({ filter = filter, order_by = "updatedAt", include_archived = true }, {
			pagelen = 20,
			cursor = "previous-page",
		}, function(page, err)
			result, failure = page, err
		end)

		assert.same({
			filter = filter,
			first = 20,
			after = "previous-page",
			orderBy = "updatedAt",
			includeArchived = true,
		}, calls[1].variables)
		assert.is_truthy(calls[1].query:find("issues(filter: $filter", 1, true))
		assert.equal(calls[1].handle, handle)
		calls[1].done({
			issues = { nodes = { raw_issue("ENG-42") }, pageInfo = { hasNextPage = true, endCursor = "next-page" } },
		}, nil)
		assert.is_nil(failure)
		assert.equal("ENG-42", result.items[1].key)
		assert.equal("next-page", result.next_cursor)
	end)

	it("uses text search without interpolating search terms into GraphQL", function()
		local term = 'login "quoted" \\ backslash'
		local result
		api.list_issues({ search = term, filter = { priority = { eq = 1 } } }, { pagelen = 10 }, function(page)
			result = page
		end)

		assert.is_truthy(calls[1].query:find("searchIssues(term: $term", 1, true))
		assert.is_nil(calls[1].query:find(term, 1, true))
		assert.equal(term, calls[1].variables.term)
		assert.same({ priority = { eq = 1 } }, calls[1].variables.filter)
		calls[1].done({
			searchIssues = { nodes = { raw_issue("ENG-5") }, pageInfo = { hasNextPage = false, endCursor = "last" } },
		}, nil)
		assert.equal("ENG-5", result.items[1].key)
		assert.is_nil(result.next_cursor)
	end)

	it("omits empty filters so Neovim does not encode them as JSON arrays", function()
		api.list_issues({ filter = {} }, { pagelen = 10 }, function() end)
		assert.is_nil(calls[1].variables.filter)
	end)

	it("reports JSON encoding errors without leaving the dashboard loading", function()
		vim.json.encode = function()
			error("Cannot encode recursive table")
		end
		local result, failure
		local filter = {}
		filter["and"] = { filter }
		assert.is_nil(api.list_issues({ filter = filter }, { pagelen = 10 }, function(page, err)
			result, failure = page, err
		end))
		assert.same({ items = {} }, result)
		assert.is_truthy(failure:find("Invalid Linear issue filter", 1, true))
		assert.equal(0, #calls)
	end)

	it("returns usable empty pages for transport errors and missing response data", function()
		local result, failure
		local function done(page, err)
			result, failure = page, err
		end
		api.list_issues({}, { pagelen = 10 }, done)
		calls[1].done(nil, "API failure")
		assert.same({ items = {} }, result)
		assert.equal("API failure", failure)
		api.list_issues({}, { pagelen = 10 }, done)
		calls[2].done({ issues = vim.NIL }, nil)
		assert.same({ items = {} }, result)
		assert.equal("Invalid Linear issues response", failure)
		assert.same({}, cache)
	end)

	it("distinguishes query inputs in cached pages and bypasses cache on refresh", function()
		local view = { filter = { team = { key = { eq = "ENG" } } } }
		local results = {}
		local function done(page)
			table.insert(results, page)
		end
		api.list_issues(view, { pagelen = 10 }, done)
		calls[1].done({ issues = { nodes = {}, pageInfo = { hasNextPage = true, endCursor = "next" } } }, nil)
		assert.is_nil(api.list_issues(view, { pagelen = 10 }, done))
		assert.equal(1, #calls)
		assert.same(results[1], results[2])
		api.list_issues(view, { pagelen = 10, force_refresh = true }, done)
		api.list_issues(view, { pagelen = 10, cursor = "next" }, done)
		api.list_issues(view, { pagelen = 20 }, done)
		api.list_issues({ filter = { team = { key = { eq = "OPS" } } } }, { pagelen = 10 }, done)
		api.list_issues(vim.tbl_extend("force", view, { search = "login" }), { pagelen = 10 }, done)
		api.list_issues(vim.tbl_extend("force", view, { order_by = "createdAt" }), { pagelen = 10 }, done)
		api.list_issues(vim.tbl_extend("force", view, { include_archived = true }), { pagelen = 10 }, done)
		assert.equal(8, #calls)
	end)

	it("fetches identifier-only references and keeps input order after asynchronous replies", function()
		local result, failure
		api.fetch_by_refs({ { key = "ENG-1" }, { key = "ENG-2" } }, nil, function(issues, err)
			result, failure = issues, err
		end)
		for index = #calls, 1, -1 do
			respond(index, calls[index].variables.id)
		end
		assert.is_nil(failure)
		assert.equal("ENG-1", result[1].key)
		assert.equal("ENG-2", result[2].key)
	end)

	it("cancels grouped reference requests and suppresses their late callbacks", function()
		local completed = false
		local handle = api.fetch_by_refs({ { key = "ENG-1" }, { key = "ENG-2" } }, nil, function()
			completed = true
		end)
		handle.cancel()
		for index, call in ipairs(calls) do
			assert.is_true(call.cancelled)
			respond(index, call.variables.id)
		end
		assert.is_false(completed)
	end)

	it("shares fetched issue data with details but refreshes when requested", function()
		local details
		api.fetch_by_refs({ { key = "ENG-1" } }, nil, function() end)
		respond(1, "ENG-1")
		assert.is_nil(api.fetch_issue({ key = "ENG-1" }, nil, function(value)
			details = value
		end))
		assert.equal("Details", details.description)
		assert.equal(1, #calls)
		api.fetch_issue({ key = "ENG-1" }, { force_refresh = true }, function() end)
		assert.equal(2, #calls)
	end)

	it("returns empty reference lists for invalid keys and transport errors", function()
		local result, failure
		local function done(issues, err)
			result, failure = issues, err
		end
		assert.is_nil(api.fetch_by_refs({}, nil, done))
		assert.same({}, result)
		api.fetch_by_refs({ { key = "" } }, nil, done)
		assert.same({}, result)
		assert.equal("Missing issue key", failure)
		assert.equal(0, #calls)
		api.fetch_by_refs({ { key = "ENG-1" } }, nil, done)
		calls[1].done(nil, "API failure")
		assert.same({}, result)
		assert.equal("API failure", failure)
	end)

	it("creates an issue and invalidates issue caches", function()
		local fields = { teamId = "team-id", title = "Fix login" }
		local result, failure
		api.create_issue(fields, function(value, err)
			result, failure = value, err
		end)
		assert.same({ input = fields }, calls[1].variables)
		calls[1].done({ issueCreate = { success = true, issue = raw_issue("ENG-42") } }, nil)
		assert.same({ id = "ENG-42-uuid", key = "ENG-42" }, result)
		assert.is_nil(failure)
		assert.same({ "linear:issue:", "linear:issues:" }, cleared)
	end)

	it("updates an issue with cleared fields and zero priority", function()
		local fields = { assigneeId = vim.NIL, labelIds = {}, priority = 0 }
		local result
		api.update_issue("ENG-42", fields, function(value)
			result = value
		end)
		assert.same({ id = "ENG-42", input = fields }, calls[1].variables)
		calls[1].done({ issueUpdate = { success = true, issue = raw_issue("ENG-42") } }, nil)
		assert.equal("ENG-42", result.key)
	end)

	it("rejects failed mutations without invalidating caches", function()
		local result, failure
		api.update_issue("ENG-42", { title = "New title" }, function(value, err)
			result, failure = value, err
		end)
		calls[1].done({ issueUpdate = { success = false } }, nil)
		assert.is_nil(result)
		assert.equal("Failed to save Linear issue", failure)
		assert.same({}, cleared)
	end)
end)
