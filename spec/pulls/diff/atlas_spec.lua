describe("native diff image integration", function()
	local original_vim, original_modules, renderer, view, controls
	local buffers, windows, reads, blobs, attached, clears, supported, callbacks
	local function noop() end

	local function show(file)
		local completed = false
		renderer.show_file(view, file, function(err)
			assert.is_nil(err)
			completed = true
		end)
		assert.is_true(completed)
		return view.document
	end

	before_each(function()
		original_vim, original_modules = vim, {}
		buffers, windows = { [1] = { lines = {} } }, { [10] = { buf = 1 } }
		reads, blobs, attached, clears, supported, callbacks = {}, {}, {}, 0, true, {}
		local current_win, next_buf, next_win = 10, 1, 10
		local function options()
			return setmetatable({}, {
				__index = function(values, id)
					local value = {}
					value[0] = value
					values[id] = value
					return value
				end,
			})
		end
		_G.vim = setmetatable({
			bo = options(),
			wo = options(),
			go = { number = true, relativenumber = true, signcolumn = "auto", statuscolumn = "" },
			cmd = setmetatable({}, {
				__index = function()
					return noop
				end,
				__call = noop,
			}),
			fn = {
				winsaveview = function()
					return { topline = 1 }
				end,
				winrestview = noop,
			},
			treesitter = { stop = noop },
			api = {
				nvim_get_current_tabpage = function()
					return 1
				end,
				nvim_get_current_buf = function()
					return windows[current_win].buf
				end,
				nvim_get_current_win = function()
					return current_win
				end,
				nvim_set_current_win = function(win)
					current_win = win
				end,
				nvim_create_augroup = function()
					return 1
				end,
				nvim_del_augroup_by_id = noop,
				nvim_create_autocmd = function(event, opts)
					callbacks[event] = opts.callback
				end,
				nvim_create_buf = function()
					next_buf = next_buf + 1
					buffers[next_buf] = { lines = {} }
					return next_buf
				end,
				nvim_buf_is_valid = function(buf)
					return buffers[buf] ~= nil
				end,
				nvim_buf_delete = function(buf)
					buffers[buf] = nil
				end,
				nvim_buf_set_name = function(buf, name)
					buffers[buf].name = name
				end,
				nvim_buf_get_name = function(buf)
					return buffers[buf].name or ""
				end,
				nvim_buf_set_lines = function(buf, _, _, _, lines)
					buffers[buf].lines = lines
				end,
				nvim_open_win = function(buf)
					next_win = next_win + 1
					windows[next_win] = { buf = buf }
					return next_win
				end,
				nvim_win_close = function(win)
					windows[win] = nil
				end,
				nvim_win_is_valid = function(win)
					return windows[win] ~= nil
				end,
				nvim_win_get_width = function()
					return 40
				end,
				nvim_win_set_width = noop,
				nvim_win_get_buf = function(win)
					return windows[win].buf
				end,
				nvim_win_set_buf = function(win, buf)
					windows[win].buf = buf
				end,
				nvim_win_call = function(win, fn)
					local previous = current_win
					current_win = win
					local result = fn()
					current_win = previous
					return result
				end,
			},
		}, { __index = original_vim })

		local function replace(name, module)
			original_modules[name] = { package.loaded[name] }
			package.loaded[name] = module
		end
		replace("atlas.pulls.diff.atlas", nil)
		replace("atlas.pulls.diff.ui.annotations", { close = noop })
		replace("atlas.pulls.diff.atlas.annotations", {
			clear = noop,
			render = function()
				return {}
			end,
		})
		replace("atlas.pulls.diff.atlas.render", { clear = noop, render = noop })
		replace("atlas.pulls.diff.diff", {
			compute = function()
				return {}, {}
			end,
		})
		replace("atlas.pulls.diff.git", {
			read = function(root, revision, path, done)
				reads[revision] = { root, path }
				done(blobs[revision] or "", nil)
			end,
		})
		replace("atlas.pulls.diff.atlas.images", {
			supports_file = function(path)
				return supported and path:match("%.png$") ~= nil
			end,
			configure_window = noop,
			clear = function()
				clears = clears + 1
			end,
			attach = function(target)
				assert.is_not_nil(target.document)
				attached[#attached + 1] = target.document
			end,
		})
		replace("atlas.pulls.diff.atlas.keymaps", {
			setup = function(_, _, _, actions)
				controls = actions
			end,
		})
		replace("atlas.pulls.diff.worktree", { relative_path = noop })
		replace("atlas.pulls.diff.ui.winbar", { update = noop })
		replace("atlas.ui.popups.help", { remove_buffer = noop })
		replace("atlas.ui.statusline", { inherit = noop })
		renderer = require("atlas.pulls.diff.atlas")
		view = renderer.open({
			root = "/repo",
			base_revision = "base",
			head_revision = "head",
			files = {},
			options = { layout = "inline" },
		}, { on_file = noop })
		renderer.setup_keymaps({ view = view }, {}, {})
	end)

	after_each(function()
		_G.vim = original_vim
		for name, original in pairs(original_modules) do
			package.loaded[name] = original[1]
		end
	end)

	it("reads renamed image revisions and preserves every byte before attaching", function()
		blobs.base, blobs.head = "\137PNG\r\n\0old\255", "\137PNG\r\n\0new\254"
		local document = show({ path = "new.png", old_path = "old.png", status = "renamed", binary = true })
		assert.same({ base = { "/repo", "old.png" }, head = { "/repo", "new.png" } }, reads)
		assert.equals(blobs.base, document.contents.old.binary_content)
		assert.equals(blobs.head, document.contents.new.binary_content)
		assert.is_true(document.binary)
		assert.same({}, document.hunks)
		assert.equals(document, attached[1])
		assert.is_not_nil(view.left.win)
		assert.equals("inline", view.preferred_layout)
		controls.toggle_layout()
		assert.is_not_nil(view.left.win)
		assert.equals("inline", view.preferred_layout)
	end)

	it("reads only the present side of added and deleted images", function()
		for _, status in ipairs({ "added", "deleted" }) do
			reads = {}
			blobs.base, blobs.head = "old\0image", "new\0image"
			local document = show({ path = "image.png", status = status, binary = true })
			local revision = status == "added" and "head" or "base"
			assert.same({ [revision] = { "/repo", "image.png" } }, reads)
			assert.is_nil(document.contents[status == "added" and "old" or "new"].binary_content)
			assert.equals(blobs[revision], document.contents[status == "added" and "new" or "old"].binary_content)
			assert.is_nil(view.left.win)
			assert.equals(view.revision_buf, view.right.buf)
		end
	end)

	it("keeps binary placeholders without reading unsupported or disabled images", function()
		for _, path in ipairs({ "archive.zip", "image.png" }) do
			supported = path ~= "image.png"
			local document = show({ path = path, status = "modified", binary = true })
			assert.same({}, reads)
			assert.is_nil(document.contents.old.binary_content)
			assert.is_nil(document.contents.new.binary_content)
			assert.same({ "Binary file (base revision)" }, buffers[view.left.buf].lines)
			assert.same({ "Binary file (head revision)" }, buffers[view.right.buf].lines)
		end
	end)

	it("detects binary content even without a binary flag", function()
		blobs.base, blobs.head = "old\0\r\n", "new\0\r\n"
		local document = show({ path = "image.png", status = "modified", binary = false })
		assert.is_true(document.binary)
		assert.equals(blobs.head, document.contents.new.binary_content)
		assert.is_not_nil(view.left.win)
	end)

	it("clears image placements and restores the preferred layout when showing text", function()
		blobs.base, blobs.head = "old\0image", "new\0image"
		show({ path = "image.png", status = "modified", binary = true })
		local previous_clears = clears
		blobs.base, blobs.head = "old\r\n", "new\r\n"
		local document = show({ path = "file.txt", status = "modified", binary = false })
		assert.is_true(clears > previous_clears)
		assert.is_false(document.binary)
		assert.is_nil(document.contents.new.binary_content)
		assert.same({ "new" }, buffers[view.right.buf].lines)
		assert.is_nil(view.left.win)
		controls.toggle_layout()
		assert.is_not_nil(view.left.win)
		assert.equals("side-by-side", view.preferred_layout)
	end)

	it("clears images when navigating to an unrelated buffer and when disposed", function()
		blobs.base, blobs.head = "old\0image", "new\0image"
		show({ path = "image.png", status = "modified", binary = true })
		local previous_clears = clears
		local other = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_win_set_buf(view.right.win, other)
		callbacks.BufEnter({ buf = other })
		assert.is_true(clears > previous_clears)
		assert.is_nil(view.document)
		assert.is_nil(view.left.win)
		assert.equals(other, view.right.buf)
		previous_clears = clears
		renderer.dispose(view)
		assert.is_true(clears > previous_clears)
		assert.is_nil(buffers[view.left.buf])
		assert.is_nil(buffers[view.revision_buf])
		assert.is_not_nil(buffers[other])
	end)
end)
