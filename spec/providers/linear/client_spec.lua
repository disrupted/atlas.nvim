local dependencies = {
	"atlas.providers.linear.client",
	"atlas.config",
	"atlas.core.http",
	"atlas.core.memory_cache",
	"atlas.core.logger",
}

describe("Linear client", function()
	local saved, options, calls, logs, client, response, request_error, handle, encode, now

	before_each(function()
		saved = {}
		for _, name in ipairs(dependencies) do
			saved[name] = { loaded = package.loaded[name], preload = package.preload[name] }
			package.loaded[name] = nil
			package.preload[name] = nil
		end
		encode, now = vim.json.encode, os.time
		options, calls, logs = { token = "lin_api_secret" }, {}, {}
		response, request_error = { data = { viewer = { id = "user-1" } } }, nil
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
				on_done(response, request_error)
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
		vim.json.encode = encode
		rawset(os, "time", now)
		for _, name in ipairs(dependencies) do
			package.loaded[name] = saved[name].loaded
			package.preload[name] = saved[name].preload
		end
	end)

	it("posts structured variables with a personal API key and unwraps data", function()
		local query = "query Issues($filter: IssueFilter) { issues(filter: $filter) { nodes { id } } }"
		local variables = { filter = { team = { key = { eq = "ENG" } } } }
		local payload, result, err
		vim.json.encode = function(value)
			payload = value
			return "encoded payload"
		end
		local request = client.graphql(query, variables, function(value, error_message)
			result, err = value, error_message
		end, { action = "Fetch issues" })

		assert.equal(handle, request)
		assert.equal(response.data, result)
		assert.is_nil(err)
		assert.same({ query = query, variables = variables }, payload)
		assert.equal("POST", calls[1].method)
		assert.equal("https://api.linear.app/graphql", calls[1].url)
		assert.equal("lin_api_secret", calls[1].headers.Authorization)
		assert.equal("application/json", calls[1].headers["Content-Type"])
		assert.equal("encoded payload", calls[1].body)
		assert.is_nil(encode(logs):find("lin_api_secret", 1, true))
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

	it("returns transport errors without exposing data as a success", function()
		request_error = "HTTP 401: Unauthorized"
		client.graphql("query { viewer { id } }", nil, function(result, err)
			assert.is_nil(result)
			assert.equal(request_error, err)
		end)
	end)

	it("rejects partial GraphQL successes and includes each error", function()
		response.errors = { { message = "Access denied" }, { message = "Invalid filter" } }
		client.graphql("query { viewer { id } }", nil, function(result, err)
			assert.is_nil(result)
			assert.equal("Access denied; Invalid filter", err)
		end)
	end)

	it("handles JSON null and missing data without throwing", function()
		for _, value in ipairs({ vim.NIL, false, {}, { data = vim.NIL }, { data = "invalid" } }) do
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

	it("reports payload encoding failures before starting HTTP", function()
		vim.json.encode = function()
			error("unsupported variable type")
		end
		client.graphql("query { viewer { id } }", nil, function(result, err)
			assert.is_nil(result)
			assert.equal("Linear request payload is invalid", err)
		end)
		assert.equal(0, #calls)
	end)

	it("expires cache entries after the configured TTL and supports disabling the cache", function()
		local time = 1000
		rawset(os, "time", function()
			return time
		end)
		client.set_cache("linear:issues", { "issue-1" })
		local value, hit = client.get_cache("linear:issues")
		assert.is_true(hit)
		assert.same({ "issue-1" }, value)
		time = 1301
		value, hit = client.get_cache("linear:issues")
		assert.is_nil(value)
		assert.is_false(hit)

		options.cache_ttl = 5
		client.set_cache("linear:issues", {})
		time = 1307
		value, hit = client.get_cache("linear:issues")
		assert.is_nil(value)
		assert.is_false(hit)

		options.cache_ttl = 0
		client.set_cache("linear:disabled", {})
		value, hit = client.get_cache("linear:disabled")
		assert.is_nil(value)
		assert.is_false(hit)
		options.cache_ttl = 300
		value, hit = client.get_cache("linear:disabled")
		assert.is_nil(value)
		assert.is_false(hit)
	end)
end)
