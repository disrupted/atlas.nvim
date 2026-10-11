local dependencies = {
	"atlas.providers.linear.client",
	"atlas.config",
	"atlas.core.http",
	"atlas.core.memory_cache",
	"atlas.core.logger",
}

describe("Linear client", function()
	local saved, options, calls, logs, client, response, handle

	before_each(function()
		saved = {}
		for _, name in ipairs(dependencies) do
			saved[name] = { loaded = package.loaded[name], preload = package.preload[name] }
			package.loaded[name] = nil
			package.preload[name] = nil
		end
		options, calls, logs = { token = "lin_api_secret" }, {}, {}
		response = { data = { viewer = { id = "user-1" } } }
		handle = { job_id = 42, cancel = function() end }
		package.loaded["atlas.config"] = {
			provider_options = function(id)
				assert.equal("linear", id)
				return options
			end,
		}
		package.loaded["atlas.core.http"] = {
			curl_request = function(method, url, headers, body, on_done)
				table.insert(calls, { method = method, url = url, headers = headers, body = body })
				on_done(response, nil)
				return handle
			end,
		}
		local function log(message, fields)
			table.insert(logs, { message = message, fields = fields })
		end
		package.loaded["atlas.core.logger"] = { loginfo = log, logerror = log }
		client = require("atlas.providers.linear.client")
	end)

	after_each(function()
		for _, name in ipairs(dependencies) do
			package.loaded[name] = saved[name].loaded
			package.preload[name] = saved[name].preload
		end
	end)

	it("posts structured variables with a personal API key and unwraps data", function()
		local query = "query Issues($filter: IssueFilter) { issues(filter: $filter) { nodes { id } } }"
		local variables = { filter = { team = { key = { eq = "ENG" } } } }
		local result, err
		local request = client.graphql(query, variables, function(value, error_message)
			result, err = value, error_message
		end, { action = "Fetch issues" })

		assert.equal(handle, request)
		assert.equal(response.data, result)
		assert.is_nil(err)
		assert.equal("POST", calls[1].method)
		assert.equal("https://api.linear.app/graphql", calls[1].url)
		assert.equal("lin_api_secret", calls[1].headers.Authorization)
		assert.equal(vim.json.encode({ query = query, variables = variables }), calls[1].body)
		assert.is_nil(vim.json.encode(logs):find("lin_api_secret", 1, true))
	end)

	it("rejects missing, invalid, and multiline API keys before starting HTTP", function()
		for _, token in ipairs({ false, vim.NIL, "", " \t", "secret\nheader", 123 }) do
			options.token = token
			local err
			assert.is_nil(client.graphql("query { viewer { id } }", nil, function(_, value)
				err = value
			end))
			assert.matches("providers.linear.token", err, 1, true)
		end
		options.token = nil
		client.graphql("query { viewer { id } }", nil, function(_, err)
			assert.matches("providers.linear.token", err, 1, true)
		end)
		assert.equal(0, #calls)
	end)

	it("rejects partial GraphQL successes and includes each error", function()
		response.errors = { { message = "Access denied" }, { message = "Invalid filter" } }
		client.graphql("query { viewer { id } }", nil, function(result, err)
			assert.is_nil(result)
			assert.equal("Access denied; Invalid filter", err)
		end)
	end)

	it("treats JSON null data as an error and JSON null errors as success", function()
		for _, value in ipairs({ vim.NIL, { data = vim.NIL } }) do
			response = value
			client.graphql("query { viewer { id } }", nil, function(result, err)
				assert.is_nil(result)
				assert.is_string(err)
			end)
		end
		response = { data = { viewer = { id = "user-1" } }, errors = vim.NIL }
		client.graphql("query { viewer { id } }", nil, function(result, err)
			assert.equal(response.data, result)
			assert.is_nil(err)
		end)
	end)

	it("does not cache when cache_ttl is 0", function()
		options.cache_ttl = 0
		client.set_cache("linear:disabled", {})
		local value, hit = client.get_cache("linear:disabled")
		assert.is_nil(value)
		assert.is_false(hit)

		options.cache_ttl = 300
		value, hit = client.get_cache("linear:disabled")
		assert.is_nil(value)
		assert.is_false(hit)
	end)
end)
