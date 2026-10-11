local M = {}

local namespace = vim.api.nvim_create_namespace("atlas.diff.images")
local directory
local states = setmetatable({}, { __mode = "k" })

local function image_module()
	local ok, snacks = pcall(require, "snacks")
	if not ok or not snacks.config or not snacks.config.image or snacks.config.image.enabled ~= true then
		return nil
	end
	local loaded, image = pcall(require, "snacks.image")
	return loaded and image or nil
end

---@param path string
---@return boolean
function M.supports_file(path)
	local image = image_module()
	return image ~= nil and image.supports_file(path)
end

---@param document AtlasDiffDocument|nil
---@return boolean
local function supports(document)
	if not document or not document.binary then
		return false
	end
	local file = document.file
	return (document.contents.old.binary_content ~= nil and M.supports_file(file.old_path or file.path))
		or (document.contents.new.binary_content ~= nil and M.supports_file(file.path))
end

---@param root string
---@param revision string
---@param file string
---@param content string
---@return string|nil
local function image_file(root, revision, file, content)
	directory = directory or vim.fn.tempname()
	local key = vim.fn.sha256(root .. ":" .. revision .. ":" .. file)
	local path = directory .. "/" .. key .. "." .. vim.fn.fnamemodify(file, ":e")
	if vim.fn.filereadable(path) == 0 then
		vim.fn.mkdir(directory, "p")
		local output = io.open(path, "wb")
		if not output then
			return nil
		end
		local written = output:write(content)
		local closed = output:close()
		if not written or not closed then
			os.remove(path)
			return nil
		end
	end
	return path
end

---@param document AtlasDiffDocument|nil
---@param win integer
function M.configure_window(document, win)
	local options = vim.wo[win][0]
	options.number = vim.go.number
	options.relativenumber = vim.go.relativenumber
	options.signcolumn = vim.go.signcolumn
	options.statuscolumn = vim.go.statuscolumn
	if supports(document) then
		options.number = false
		options.relativenumber = false
		options.signcolumn = "no"
		options.statuscolumn = ""
	end
end

---@param view AtlasDiffNativeView
function M.clear(view)
	local state = states[view]
	states[view] = nil
	if not state then
		return
	end
	for buf in pairs(state.buffers) do
		state.image.placement.clean(buf)
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
		end
	end
end

---@param buf integer
local function clear_buffer(buf)
	vim.bo[buf].readonly = false
	vim.bo[buf].modifiable = true
	-- Keep file-level review annotations anchored to the placeholder's first row.
	local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
	vim.api.nvim_buf_set_text(buf, 0, 0, 0, #line, { "" })
	vim.bo[buf].modifiable = false
	vim.bo[buf].modified = false
	vim.bo[buf].readonly = true
end

---@param view AtlasDiffNativeView
function M.attach(view)
	M.clear(view)
	local document = view.document
	if not supports(document) then
		return
	end
	---@cast document AtlasDiffDocument
	local image = image_module()
	local state = { image = image, buffers = {} }
	states[view] = state

	local function current()
		return states[view] == state and view.document == document
	end

	local function attach_image(pane, revision, file, content)
		local buf, win = pane.buf, pane.win
		local function valid()
			return current()
				and pane.buf == buf
				and pane.win == win
				and win ~= nil
				and vim.api.nvim_win_is_valid(win)
				and vim.api.nvim_buf_is_valid(buf)
				and vim.api.nvim_win_get_buf(win) == buf
		end
		if not valid() or content.binary_content == nil or not image.supports_file(file) then
			return
		end
		local path = image_file(view.result.root, revision, file, content.binary_content)
		if not path then
			return
		end
		state.buffers[buf] = true
		clear_buffer(buf)
		vim.api.nvim_buf_set_extmark(buf, namespace, 0, 0, {
			virt_text = { { "Loading image…", "AtlasTextMuted" } },
		})
		image.buf.attach(buf, {
			src = path,
			inline = true,
			on_update_pre = function(placement)
				if not valid() then
					placement:close()
				elseif #placement:state().wins == 0 then
					placement:del()
				end
			end,
			on_update = function()
				if valid() then
					vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
				end
			end,
		})
	end

	image.terminal.detect(function()
		if not current() then
			return
		end
		if not image_module() or not image.supports_terminal() then
			return
		end
		local file = document.file
		local old_path = file.old_path or file.path
		if file.status == "deleted" then
			attach_image(view.right, view.result.base_revision, old_path, document.contents.old)
		else
			if file.status ~= "added" then
				attach_image(view.left, view.result.base_revision, old_path, document.contents.old)
			end
			attach_image(view.right, view.result.head_revision, file.path, document.contents.new)
		end
	end)
end

return M
