local icons = require("atlas.ui.shared.icons")
local keymaps = require("atlas.core.keymaps")

local M = {}

local cached_version = nil

local function get_version()
	if cached_version then
		return cached_version
	end

	cached_version = "dev"
	local cwd = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h")
	pcall(
		require("atlas.core.git").run,
		{ "describe", "--tags", "--abbrev=0" },
		{ cwd = cwd, text = true },
		function(result)
			if result.code == 0 and vim.trim(result.stdout or "") ~= "" then
				cached_version = vim.trim(result.stdout)
				vim.cmd("redrawstatus")
			end
		end
	)
	return cached_version
end

---@param ctx AtlasStatuslineContext
---@return string|nil
function M.user(ctx)
	local user = ctx.user
	local name = user and (user.username ~= "" and user.username or user.name)
	if name and name ~= "" then
		return string.format("%s @%s", icons.get("user"), name)
	end
end

---@return string
function M.version()
	return string.format("atlas (%s)", get_version())
end

---@return AtlasStatuslineSegment[]|nil
function M.help()
	local keymap = keymaps.resolve("ui.help")
	if keymap then
		return {
			{ text = keymap.key[1], hl_group = "AtlasFooterBackground" },
			{ text = keymap.label },
		}
	end
end

return M
