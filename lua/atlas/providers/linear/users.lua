local client = require("atlas.providers.linear.client")
local json = require("atlas.core.json")

local M = {
	-- list_members = nil,
	-- get_assignable_users = nil,
}

---@param raw any
---@return AtlasUser|nil
function M.to_user(raw)
	raw = json.nilify(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local id = json.safe_str(raw.id) or ""
	if id == "" then
		return nil
	end
	local name = json.safe_str(raw.name) or ""
	local display_name = json.safe_str(raw.displayName) or ""
	if name == "" then
		name = display_name ~= "" and display_name or id
	end
	return {
		id = id,
		name = name,
		username = display_name ~= "" and display_name or name,
	}
end

---@param on_done fun(user: AtlasUser|nil, err: string|nil)
---@return { job_id: integer, cancel: fun() }|nil
function M.fetch_user(on_done)
	local cache_key = "linear:current_user"
	local cached, hit = client.get_cache(cache_key)
	if hit then
		on_done(M.to_user(cached), nil)
		return nil
	end
	return client.graphql("query AtlasViewer { viewer { id name displayName } }", nil, function(result, err)
		if err then
			on_done(nil, err)
			return
		end
		local raw = json.safe_table(result).viewer
		local user = M.to_user(raw)
		if not user then
			on_done(nil, "Linear response is missing the current user")
			return
		end
		client.set_cache(cache_key, raw)
		on_done(user, nil)
	end, { action = "Fetch current user" })
end

return M
