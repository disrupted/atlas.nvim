local M = {}

local json = require("atlas.core.json")
local users = require("atlas.providers.gitlab.users")

---@type AtlasReactionOption[]
M.reactions = {
	{ name = "thumbsup" },
	{ name = "thumbsdown" },
	{ name = "laughing" },
	{ name = "tada" },
	{ name = "confused" },
	{ name = "heart" },
	{ name = "rocket" },
	{ name = "eyes" },
}

---@param awards any GraphQL `awardEmoji.nodes`, one per user
---@param viewer string|nil Username of the current user
---@return AtlasReaction[]
function M.award_reactions(awards, viewer)
	local reactions, by_name = {}, {}
	for _, award in ipairs(json.safe_table(awards)) do
		local name = type(award) == "table" and json.safe_str(award.name) or nil
		if name and name ~= "" then
			local reaction = by_name[name]
			if not reaction then
				reaction = { name = name, count = 0, users = {}, reacted = false }
				by_name[name] = reaction
				table.insert(reactions, reaction)
			end
			reaction.count = reaction.count + 1
			local user = users.to_user(award.user)
			if user then
				table.insert(reaction.users, user)
				reaction.reacted = reaction.reacted or user.username == viewer
			end
		end
	end
	return reactions
end

---@param id any A notes GraphQL gid or REST id
---@return string|nil
function M.note_id(id)
	-- Note gids carry the notes class (Note, DiscussionNote, DiffNote), which changes when a note gets a reply.
	local number = tostring(json.nilify(id) or ""):match("(%d+)$")
	return number and "gid://gitlab/Note/" .. number or nil
end

return M
