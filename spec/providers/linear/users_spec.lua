local dependencies = { "atlas.providers.linear.users", "atlas.providers.linear.client" }

describe("Linear users", function()
	local saved, users, response, request_error, calls, cached, handle

	before_each(function()
		saved = {}
		for _, name in ipairs(dependencies) do
			saved[name] = { loaded = package.loaded[name], preload = package.preload[name] }
			package.loaded[name] = nil
			package.preload[name] = nil
		end
		response = { viewer = { id = "user-1", name = "Jane Doe", displayName = "jane" } }
		request_error, cached, calls = nil, nil, 0
		handle = { cancel = function() end }
		package.loaded["atlas.providers.linear.client"] = {
			get_cache = function()
				return cached, cached ~= nil
			end,
			set_cache = function(key, value)
				assert.equal("linear:current_user", key)
				cached = value
			end,
			graphql = function(query, variables, callback)
				assert.matches("viewer { id name displayName }", query, 1, true)
				assert.is_nil(variables)
				calls = calls + 1
				callback(response, request_error)
				return handle
			end,
		}
		users = require("atlas.providers.linear.users")
	end)

	after_each(function()
		for _, name in ipairs(dependencies) do
			package.loaded[name] = saved[name].loaded
			package.preload[name] = saved[name].preload
		end
	end)

	it("normalizes and caches the current user while forwarding cancellation", function()
		local callback = function(user, err)
			assert.same({ id = "user-1", name = "Jane Doe", username = "jane" }, user)
			assert.is_nil(err)
		end
		assert.equal(handle, users.fetch_user(callback))
		assert.is_nil(users.fetch_user(callback))
		assert.equal(1, calls)
	end)

	it("handles nullable names and absent users", function()
		assert.same(
			{ id = "user-1", name = "Jane Doe", username = "Jane Doe" },
			users.to_user({ id = "user-1", name = "Jane Doe", displayName = vim.NIL })
		)
		assert.same(
			{ id = "user-1", name = "jane", username = "jane" },
			users.to_user({ id = "user-1", name = vim.NIL, displayName = "jane" })
		)
		assert.is_nil(users.to_user(vim.NIL))
		assert.is_nil(users.to_user({ id = vim.NIL }))
	end)

	it("reports a missing viewer without caching it", function()
		response = { viewer = vim.NIL }
		users.fetch_user(function(user, err)
			assert.is_nil(user)
			assert.equal("Linear response is missing the current user", err)
		end)
		assert.is_nil(cached)
	end)

	it("forwards GraphQL errors without caching them", function()
		request_error = "Unauthorized"
		users.fetch_user(function(user, err)
			assert.is_nil(user)
			assert.equal("Unauthorized", err)
		end)
		assert.is_nil(cached)
	end)
end)
