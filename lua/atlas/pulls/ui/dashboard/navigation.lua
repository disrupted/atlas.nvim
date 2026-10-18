local M = {}

local window = require("atlas.pulls.ui.dashboard.window")

local DEBOUNCE_MS = 150
local select_timer = nil
local autocmd_groups = {}

local function stop_select_timer()
	if select_timer then
		select_timer:stop()
		select_timer:close()
		select_timer = nil
	end
end

local function is_selectable(node)
	return type(node) == "table" and (node.kind == "pr" or node.kind == "bookmark" or node.kind == "starred")
end

function M.current_item()
	local win = window.win()
	if win == nil then
		return nil
	end
	return window.line_map[vim.api.nvim_win_get_cursor(win)[1]]
end

local function on_cursor_moved()
	stop_select_timer()
	select_timer = vim.defer_fn(function()
		select_timer = nil
		if window.is_active() then
			require("atlas.pulls.ui.dashboard").select(M.current_item())
		end
	end, DEBOUNCE_MS)
end

---@param buf integer
function M.detach(buf)
	local group = autocmd_groups[buf]
	if group then
		autocmd_groups[buf] = nil
		pcall(vim.api.nvim_del_augroup_by_id, group)
	end
	stop_select_timer()
end

---@param buf integer
function M.attach(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	M.detach(buf)
	local group = vim.api.nvim_create_augroup("AtlasPullsNavigation" .. tostring(buf), { clear = true })
	autocmd_groups[buf] = group

	vim.api.nvim_create_autocmd("CursorMoved", {
		group = group,
		buffer = buf,
		callback = on_cursor_moved,
	})
	vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
		group = group,
		buffer = buf,
		once = true,
		callback = function()
			if autocmd_groups[buf] == group then
				M.detach(buf)
			end
		end,
	})
end

---@param direction "up"|"down"
function M.move_cursor(direction)
	local win, buf = window.win(), window.buf()
	if win == nil or buf == nil then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(win)
	local line, col = cursor[1], cursor[2]
	local step = direction == "up" and -1 or 1
	local max_line = vim.api.nvim_buf_line_count(buf)
	for lnum = line + step, (direction == "up" and 1 or max_line), step do
		if is_selectable(window.line_map[lnum]) then
			vim.api.nvim_win_set_cursor(win, { lnum, col })
			on_cursor_moved()
			return
		end
	end

	vim.api.nvim_win_set_cursor(win, { math.max(1, math.min(max_line, line + step)), col })
	on_cursor_moved()
end

---@param predicate fun(item: table): boolean
---@return boolean
function M.focus_item(predicate)
	local win, buf = window.win(), window.buf()
	if win == nil or buf == nil then
		return false
	end
	for lnum = 1, vim.api.nvim_buf_line_count(buf) do
		local item = window.line_map[lnum]
		if is_selectable(item) and predicate(item) then
			vim.api.nvim_win_set_cursor(win, { lnum, 0 })
			on_cursor_moved()
			return true
		end
	end
	return false
end

function M.focus_first_item()
	M.focus_item(function()
		return true
	end)
end

function M.focus_last_item()
	local win, buf = window.win(), window.buf()
	if win == nil or buf == nil then
		return
	end
	for lnum = vim.api.nvim_buf_line_count(buf), 1, -1 do
		if is_selectable(window.line_map[lnum]) then
			vim.api.nvim_win_set_cursor(win, { lnum, 0 })
			on_cursor_moved()
			return
		end
	end
end

return M
