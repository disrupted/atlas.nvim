local M = {}

---@param authors table<string, string>
---@param user AtlasUser|nil
function M.add(authors, user)
	if user and user.id and user.name then
		authors[user.id] = user.name
	end
end

---@param text string
---@param authors table<string, string>
---@return string
function M.resolve(text, authors)
	return (
		text:gsub("@<([^>]+)>", function(id)
			return authors[id] and ("@" .. authors[id]) or ("@<" .. id .. ">")
		end)
	)
end

return M
