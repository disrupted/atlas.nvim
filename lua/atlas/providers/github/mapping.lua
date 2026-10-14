local M = {}

local json = require("atlas.core.json")

---@type AtlasReactionOption[]
M.reactions = {
	{ name = "thumbsup", key = "THUMBS_UP" },
	{ name = "thumbsdown", key = "THUMBS_DOWN" },
	{ name = "laughing", key = "LAUGH" },
	{ name = "tada", key = "HOORAY" },
	{ name = "confused", key = "CONFUSED" },
	{ name = "heart", key = "HEART" },
	{ name = "rocket", key = "ROCKET" },
	{ name = "eyes", key = "EYES" },
}

---@param raw any
---@return { id: string, login: string, name: string }|nil
function M.identity(raw)
	raw = json.nilify(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local login = json.safe_str(raw.login) or ""
	local name = json.safe_str(raw.name) or ""
	return {
		id = json.safe_str(raw.id) or json.safe_str(raw.databaseId) or "",
		login = login,
		name = name ~= "" and name or login,
	}
end

---@param groups any GraphQL `reactionGroups`
---@return AtlasReaction[]
function M.graphql_reactions(groups)
	local reactions = {}
	for _, group in ipairs(json.safe_table(groups)) do
		group = json.safe_table(group)
		local reactors = json.safe_table(group.reactors)
		local count = tonumber(reactors.totalCount) or 0
		for _, option in ipairs(M.reactions) do
			if option.key == group.content and count > 0 then
				local users = {}
				for _, node in ipairs(json.safe_table(reactors.nodes)) do
					local identity = M.identity(node)
					if identity then
						table.insert(users, { name = identity.name, username = identity.login })
					end
				end
				table.insert(
					reactions,
					{ name = option.name, count = count, users = users, reacted = group.viewerHasReacted == true }
				)
			end
		end
	end
	return reactions
end

---@param raw any
---@param fallback string|nil
---@return string owner, string repo, string full_name
function M.repository(raw, fallback)
	raw = json.safe_table(raw)
	local full_name = json.safe_str(raw.nameWithOwner) or json.safe_str(raw.full_name) or ""
	local name = json.safe_str(raw.name) or ""
	if full_name == "" then
		local owner = json.safe_str(json.safe_table(raw.owner).login) or ""
		if owner ~= "" and name ~= "" then
			full_name = owner .. "/" .. name
		end
	end
	if full_name == "" then
		full_name = tostring(fallback or "")
	end
	local owner, repo = full_name:match("^(.*)/([^/]+)$")
	return owner or "", name ~= "" and name or repo or full_name, full_name
end

---@param value any
---@return table
function M.connection_nodes(value)
	value = json.safe_table(value)
	if json.nilify(value.nodes) ~= nil then
		return json.safe_table(value.nodes)
	end
	return value
end

return M
