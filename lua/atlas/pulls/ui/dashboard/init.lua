local M = {}

local window = require("atlas.pulls.ui.dashboard.window")
local utils = require("atlas.ui.shared.utils")
local starred = require("atlas.core.starred")
local state = require("atlas.pulls.state")
local renderer = require("atlas.pulls.ui.dashboard.renderer")
local navigation = require("atlas.pulls.ui.dashboard.navigation")
local controller = require("atlas.pulls.ui.dashboard.controller")
local keymaps = require("atlas.pulls.ui.dashboard.keymaps")
local detail = require("atlas.pulls.ui.detail")
local detail_window = require("atlas.pulls.ui.detail.window")
local bookmarks = require("atlas.ui.shared.bookmarks")
local notifications = require("atlas.ui.notifications")
local ns = vim.api.nvim_create_namespace("atlas.ui")

function M.render()
	local win = window.win()
	local buf = window.buf()
	if win == nil or buf == nil then
		return
	end

	local width = vim.api.nvim_win_get_width(win)
	local height = vim.api.nvim_win_get_height(win)
	local lines, spans, line_map = renderer.render({
		width = width,
		height = height,
	})

	window.line_map = line_map

	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	utils.apply_spans(buf, ns, spans)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
end

---@param pr PullRequest
local function open_detail(pr)
	detail.open(pr, {
		provider = state.provider,
		on_update = controller.refresh_pr,
	})
end

---@param item table|nil
function M.select(item)
	if type(item) ~= "table" or (item.kind ~= "pr" and item.kind ~= "pr_meta") or type(item.pr) ~= "table" then
		return
	end
	if not detail_window.is_open(vim.api.nvim_get_current_tabpage()) then
		return
	end
	open_detail(item.pr)
end

function M.toggle_detail()
	if detail_window.is_open(vim.api.nvim_get_current_tabpage()) then
		detail.close()
		return
	end
	local item = navigation.current_item()
	if type(item) == "table" and (item.kind == "pr" or item.kind == "pr_meta") and type(item.pr) == "table" then
		open_detail(item.pr)
	end
end

function M.next_detail_tab()
	if detail.is_open() then
		detail.next_tab()
	end
end

function M.prev_detail_tab()
	if detail.is_open() then
		detail.prev_tab()
	end
end

---@param provider PullsProvider
---@param opts { initial_view: AtlasPullsViewConfig|nil }|nil
function M.init(provider, opts)
	if state.provider ~= provider then
		state.current_user = nil
	end
	state.provider = provider
	state.views = provider.views()
	state.error = nil
	state.pulls = {}
	state.current_page = 1
	state.page_history = {}
	state.query = ""
	state.reloading_pr_keys = {}
	state.reload_spinner_frame = "⠋"
	state.starred_items = starred.list("pulls", provider.id) or {}

	state.bookmarks = bookmarks.new(provider.id, "pulls")
	local initial_view = opts and opts.initial_view
	state.view = initial_view and vim.tbl_extend("force", {}, initial_view)
		or bookmarks.views(state.views, state.bookmarks, state.starred_items)[1]
	window.statusline:clear_items()

	local buf = window.buf()
	if buf ~= nil then
		keymaps.register(buf, state.views)
	end

	controller.switch_view(state.view)

	if provider.capabilities.notifications then
		notifications.refresh(provider, M.render)
	end
end

return M
