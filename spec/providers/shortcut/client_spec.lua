local MODULE = "atlas.providers.shortcut.client"
local DEPENDENCIES = {
	"atlas.config",
	"atlas.core.cache",
	"atlas.core.http",
	"atlas.core.logger",
	"atlas.core.memory_cache",
}

local token
local request

local function load_service()
	package.loaded[MODULE] = nil
	return require(MODULE)
end

describe("Shortcut client", function()
	before_each(function()
		token = "shortcut-test-token"
		request = nil

		rawset(package.preload, "atlas.config", function()
			return {
				provider_options = function()
					return { token = token }
				end,
			}
		end)
		rawset(package.preload, "atlas.core.http", function()
			return {
				curl_request = function(method, url, headers, body, callback)
					request = { method = method, url = url, headers = headers, body = body, callback = callback }
					return { cancel = function() end }
				end,
			}
		end)
		rawset(package.preload, "atlas.core.cache", function()
			return {}
		end)
		rawset(package.preload, "atlas.core.memory_cache", function()
			return {}
		end)
		rawset(package.preload, "atlas.core.logger", function()
			return { loginfo = function() end, logerror = function() end }
		end)

		for _, dependency in ipairs(DEPENDENCIES) do
			package.loaded[dependency] = nil
		end
	end)

	after_each(function()
		package.loaded[MODULE] = nil
		for _, dependency in ipairs(DEPENDENCIES) do
			package.loaded[dependency] = nil
			rawset(package.preload, dependency, nil)
		end
	end)

	it("sends authenticated requests to Shortcut", function()
		local service = load_service()
		service.request("POST", "/stories", { name = "Story" }, function() end)

		assert.equal("POST", request.method)
		assert.equal("https://api.app.shortcut.com/api/v3/stories", request.url)
		assert.equal(token, request.headers["Shortcut-Token"])
		assert.equal('{"name":"Story"}', request.body)
	end)

	it("requires a token", function()
		token = nil
		local service = load_service()
		local error
		local handle = service.request("GET", "/member", nil, function(_, value)
			error = value
		end)

		assert.is_nil(handle)
		assert.is_nil(request)
		assert.equal("Missing Shortcut token in config (providers.shortcut.token)", error)
	end)

	it("accepts no-content success from the shared HTTP transport", function()
		local result, err
		load_service().request("DELETE", "/stories/123", nil, function(value, error)
			result, err = value, error
		end)
		request.callback({}, nil, 204)
		assert.same({}, result)
		assert.is_nil(err)
	end)

	it("reports invalid JSON response shapes instead of crashing", function()
		local result, err
		load_service().request("GET", "/member", nil, function(value, error)
			result, err = value, error
		end)
		request.callback("unexpected", nil, 200)
		assert.is_nil(result)
		assert.equal("Shortcut response is not a JSON object or array", err)
	end)

	it("propagates HTTP errors", function()
		local result, err
		load_service().request("GET", "/member", nil, function(value, error)
			result, err = value, error
		end)
		request.callback(nil, "HTTP 429", 429)
		assert.is_nil(result)
		assert.equal("HTTP 429", err)
	end)
end)
