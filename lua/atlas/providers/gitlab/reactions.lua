local M = {}

local json = require("atlas.core.json")
local service = require("atlas.providers.gitlab.client")

---@param mutation string
---@param comment IssueComment|PullsComment
---@param name string
---@param on_done fun(ok: boolean, err: string|nil)
---@return { cancel: fun() }|nil
local function mutate(mutation, comment, name, on_done)
	local query = string.format(
		"mutation($id:AwardableID!,$name:String!){%s(input:{awardableId:$id,name:$name}){errors}}",
		mutation
	)
	return service.graphql(query, { id = tostring(comment.id), name = name }, function(data, err)
		local errors = json.safe_table(json.safe_table(json.safe_table(data)[mutation]).errors)
		if err or #errors > 0 then
			on_done(false, err or tostring(errors[1]))
			return
		end
		on_done(true, nil)
	end, {
		action = mutation,
		note_id = tostring(comment.id),
		name = name,
	})
end

---@param comment IssueComment|PullsComment
---@param name string
---@param on_done fun(ok: boolean, err: string|nil)
---@return { cancel: fun() }|nil
function M.add(comment, name, on_done)
	return mutate("awardEmojiAdd", comment, name, on_done)
end

---@param comment IssueComment|PullsComment
---@param name string
---@param on_done fun(ok: boolean, err: string|nil)
---@return { cancel: fun() }|nil
function M.remove(comment, name, on_done)
	return mutate("awardEmojiRemove", comment, name, on_done)
end

return M
