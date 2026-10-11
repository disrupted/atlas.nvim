local M = {}

local config = require("atlas.config")
local http = require("atlas.core.http")
local json = require("atlas.core.json")
local logger = require("atlas.core.logger")
local memory_cache = require("atlas.core.memory_cache")

---@return AtlasLinearConfig
local function provider_options()
	return config.provider_options("linear") or {}
end

---@return number
local function cache_ttl()
	return tonumber(provider_options().cache_ttl) or 300
end

---@param key string
---@return any|nil, boolean
function M.get_cache(key)
	if cache_ttl() <= 0 then
		return nil, false
	end
	local entry = memory_cache.get(key)
	if not entry then
		return nil, false
	end
	return entry.value, true
end

---@param key string
---@param value any
function M.set_cache(key, value)
	local ttl = cache_ttl()
	if ttl > 0 then
		memory_cache.set(key, value, ttl)
	end
end

---@param errors any
---@return string|nil
local function graphql_error(errors)
	errors = json.nilify(errors)
	if errors == nil then
		return nil
	end
	if type(errors) ~= "table" then
		return "Linear GraphQL request failed"
	end
	local messages = {}
	for _, err in ipairs(errors) do
		local message = json.safe_str(json.safe_table(err).message)
		table.insert(messages, message or "Linear GraphQL request failed")
	end
	if #messages > 0 then
		return table.concat(messages, "; ")
	end
	if next(errors) ~= nil then
		return "Linear GraphQL request failed"
	end
	return nil
end

---@param query string
---@param variables table|nil
---@param on_done fun(result: table|nil, err: string|nil)
---@param ctx table|nil
---@return { job_id: integer, cancel: fun() }|nil
function M.graphql(query, variables, on_done, ctx)
	local token = provider_options().token
	if type(token) ~= "string" or token == "" or token:find("[%s%c]") then
		on_done(nil, "Missing or invalid Linear API key in config (providers.linear.token)")
		return nil
	end

	local payload = { query = query }
	if variables ~= nil and type(variables) ~= "table" then
		on_done(nil, "Linear request payload is invalid")
		return nil
	end
	if variables ~= nil and next(variables) ~= nil then
		payload.variables = variables
	end
	local ok, encoded = pcall(vim.json.encode, payload)
	if not ok then
		on_done(nil, "Linear request payload is invalid")
		return nil
	end

	local log = vim.tbl_extend("keep", { transport = "graphql" }, ctx or {})
	local message = log.action or "Linear GraphQL"
	log.action = nil
	logger.loginfo(message, log)
	return http.curl_request(
		"POST",
		"https://api.linear.app/graphql",
		{
			Authorization = token,
			["Content-Type"] = "application/json",
			Accept = "application/json",
		},
		encoded,
		function(result, err)
			result = json.nilify(result)
			if not err then
				if type(result) ~= "table" then
					err = "Linear response is not a JSON object"
				else
					err = graphql_error(result.errors)
					if not err and type(json.nilify(result.data)) ~= "table" then
						err = "Linear response is missing GraphQL data"
					end
				end
			end
			if err then
				logger.logerror(message .. " failed", vim.tbl_extend("force", {}, log, { error = tostring(err) }))
				on_done(nil, err)
				return
			end
			on_done(result.data, nil)
		end
	)
end

return M
