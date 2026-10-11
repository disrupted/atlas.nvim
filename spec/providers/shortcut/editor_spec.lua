local module_name = "atlas.issues.providers.shortcut.ui.editor"

local function equal(left, right)
	if type(left) ~= type(right) then
		return false
	end
	if type(left) ~= "table" then
		return left == right
	end
	for key, value in pairs(left) do
		if not equal(value, right[key]) then
			return false
		end
	end
	for key in pairs(right) do
		if left[key] == nil then
			return false
		end
	end
	return true
end

describe("Shortcut shared form editor", function()
	local editor_api, editor, options, selected, requests, results, notices, opened, fetch_opts
	local modules, originals, original_equal, original_bo, users_done, user_cancelled
	local active = { id = "active", name = "Active Member", disabled = false }
	local former = { id = "former", name = "Former Member", disabled = true }
	local issue = { id = 42, key = "42", title = "Stale title", type = { name = "chore" }, workflow_state_id = 2 }
	local details = {
		title = "Fresh title",
		description = "Body",
		story_type = "bug",
		workflow_state_id = 7,
		assignees = { active, former },
	}

	before_each(function()
		selected, requests, results, notices, opened = {}, {}, {}, {}, {}
		users_done, user_cancelled = nil, false
		original_equal, original_bo = vim.deep_equal, vim.bo
		vim.deep_equal = equal
		vim.bo = { [17] = { modifiable = true } }
		modules = {
			["atlas.ui.form"] = {
				open = function(opts)
					options = opts
					editor = {
						editor_buf = 17,
						closed = false,
						content = { title = opts.initial_title, body = opts.initial_body },
						statusline = {
							notify = function(_, level, message)
								notices[#notices + 1] = { level, message }
							end,
							clear_notice = function() end,
						},
					}
					return editor
				end,
				close = function(handle)
					if not handle.closed then
						handle.closed = true
						options.on_closed(handle)
					end
				end,
				get_content = function(handle)
					return handle.content
				end,
				render_meta = function() end,
			},
			["atlas.ui.shared.icons"] = {
				get = function()
					return ""
				end,
			},
			["atlas.core.notify"] = {
				loading = function() end,
				clear = function() end,
				info = function() end,
				error = function(message)
					notices[#notices + 1] = { "error", message }
				end,
				warn = function(message)
					notices[#notices + 1] = { "warn", message }
				end,
			},
			["atlas.ui.picker"] = {
				select = function(opts)
					selected = opts
				end,
				multi_select = function(opts)
					selected = opts
				end,
			},
			["atlas.providers.shortcut.users"] = {
				list = function(done)
					users_done = done
					return {
						cancel = function()
							user_cancelled = true
						end,
					}
				end,
			},
			["atlas.issues.providers.shortcut.api.workflows"] = {
				list_states = function(done)
					done({ { id = 7, workflow_name = "Development", name = "Started", position = 1 } }, nil)
				end,
			},
			["atlas.issues.providers.shortcut.api.stories"] = {
				get = function(id, opts, done)
					assert.equal(42, id)
					fetch_opts = opts
					done(vim.deepcopy(details), nil)
				end,
				create = function(fields, done)
					requests[#requests + 1] = { fields = fields, done = done }
				end,
				update = function(target, fields, done)
					requests[#requests + 1] = { issue = target, fields = fields, done = done }
				end,
			},
			["atlas.commands.open"] = {
				open = function(url)
					opened[#opened + 1] = url
				end,
			},
		}
		originals = {}
		for name, value in pairs(modules) do
			originals[name] = package.loaded[name]
			package.loaded[name] = value
		end
		package.loaded[module_name] = nil
		editor_api = require(module_name)
	end)

	after_each(function()
		for name in pairs(modules) do
			package.loaded[name] = originals[name]
		end
		package.loaded[module_name] = nil
		vim.deep_equal, vim.bo = original_equal, original_bo
	end)

	local function done(value, err)
		results[#results + 1] = { value = value, err = err }
	end
	local function press(key)
		for _, keymap in ipairs(options.keymaps) do
			if keymap.key == key then
				keymap.action(editor)
				return
			end
		end
		error("Missing keymap: " .. key)
	end

	it("opens the shared form with provider completion and requires a name and state", function()
		assert.equal(editor_api.open(done), editor)
		assert.same({ context = { provider = "shortcut" } }, options.completion)
		options.submit(editor)
		assert.same({ "warn", "Name is required" }, notices[#notices])
		editor.content.title = "New Story"
		options.submit(editor)
		assert.same({ "warn", "Workflow state is required" }, notices[#notices])
		assert.equal(0, #requests)
		press("gw")
		selected.on_select(selected.items[1])
		options.submit(editor)
		assert.same(
			{ name = "New Story", description = "", story_type = "feature", workflow_state_id = 7, owner_ids = {} },
			requests[1].fields
		)
		requests[1].done({ key = "43", url = "https://app.shortcut.com/acme/story/43" }, nil)
		assert.is_true(editor.closed)
		assert.equal(1, #results)
		assert.equal("43", results[1].value.key)
		assert.same({ "https://app.shortcut.com/acme/story/43" }, opened)
	end)

	it("seeds edits from freshly fetched title, type and workflow fields", function()
		editor_api.edit(issue, done)
		assert.is_true(fetch_opts.force_refresh)
		assert.equal("Fresh title", options.initial_title)
		assert.equal("Body", options.initial_body)
		assert.same({ context = { provider = "shortcut", issue = { key = "42" } } }, options.completion)
		assert.matches("bug", options.meta()[1][1].value, 1, true)
		editor.content.title = "Edited title"
		options.submit(editor)
		assert.same({ name = "Edited title" }, requests[1].fields)
	end)

	it("preserves native Story type icons and highlights in the picker and form", function()
		editor_api.open(done)
		press("gt")
		local styles = {
			feature = { icon = "󰃀", hl = "AtlasTextPositive" },
			bug = { icon = "", hl = "AtlasLogError" },
			chore = { icon = "", hl = "AtlasLogInfo" },
		}
		for _, story_type in ipairs(selected.items) do
			local style = styles[story_type]
			assert.equal(style.icon .. " " .. story_type, selected.format_item(story_type))
			selected.on_select(story_type)
			assert.same({ key = "Type:", value = style.icon .. " " .. story_type, hl = style.hl }, options.meta()[1][1])
		end
	end)

	it("preserves selected disabled owners and treats their ordering as unchanged", function()
		editor_api.edit(issue, done)
		press("ga")
		users_done({ active, former, { id = "disabled", name = "Disabled", disabled = true } }, nil)
		assert.same({ active, former }, selected.items)
		assert.equal("former", selected.key(former))
		assert.matches("Former Member", selected.format_item(former), 1, true)
		selected.on_done({ former, active })
		assert.is_false(options.is_modified(editor))
		options.submit(editor)
		assert.equal(0, #requests)
		assert.is_true(editor.closed)
		assert.equal(1, #results)
		assert.is_nil(results[1].value)
	end)

	it("clears description and every owner without changing other Story fields", function()
		editor_api.edit(issue, done)
		press("ga")
		users_done({ active, former }, nil)
		selected.on_done({})
		editor.content.body = ""
		options.submit(editor)
		assert.same({ description = "", owner_ids = {} }, requests[1].fields)
		requests[1].done(true, nil)
		assert.same({ { value = { key = "42" } } }, results)
	end)

	it("locks submission and restores editing after a failed save", function()
		editor_api.edit(issue, done)
		editor.content.title = "Edited"
		options.submit(editor)
		options.submit(editor)
		options.close(editor)
		assert.equal(1, #requests)
		assert.is_false(vim.bo[17].modifiable)
		assert.is_false(editor.closed)
		requests[1].done(false, "rejected")
		assert.is_true(vim.bo[17].modifiable)
		assert.same({ "error", "rejected" }, notices[#notices])
		assert.equal(0, #results)
		options.submit(editor)
		assert.equal(2, #requests)
	end)

	it("cancels metadata requests when the form closes", function()
		editor_api.edit(issue, done)
		press("ga")
		options.close(editor)
		assert.is_true(user_cancelled)
		users_done({ active }, nil)
		assert.is_nil(selected.items)
		assert.equal(1, #results)
	end)

	it("reports a save completed after external close without reopening a Story", function()
		editor_api.open(done)
		editor.content.title = "New Story"
		press("gw")
		selected.on_select(selected.items[1])
		options.submit(editor)
		modules["atlas.ui.form"].close(editor)
		assert.equal(0, #results)
		requests[1].done({ key = "43", url = "https://app.shortcut.com/acme/story/43" }, nil)
		assert.equal(1, #results)
		assert.equal(0, #opened)
	end)
end)
