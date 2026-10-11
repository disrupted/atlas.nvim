local M = {}

local url = require("atlas.providers.url")

---@param value string
---@param parsed AtlasParsedUrl|nil
---@return AtlasTarget|nil, string|nil
function M.resolve(value, parsed)
	if parsed == nil or parsed.host ~= "linear.app" or parsed.remote then
		return nil, nil
	end

	local issue_key, tail = parsed.path:match("^/[^/]+/issue/([A-Za-z][A-Za-z0-9_]*%-%d+)(.*)$")
	if issue_key == nil or not url.valid_tail(tail) then
		return nil, "Unsupported Linear URL. Expected a /workspace/issue/KEY issue URL"
	end

	return {
		provider = "linear",
		domain = "issues",
		entity = "issue",
		url = value,
		host = parsed.host,
		issue_key = issue_key:upper(),
	}
end

return M
