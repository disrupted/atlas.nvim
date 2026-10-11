describe("Shortcut checklist overview", function()
	local overview, state, mappings, removed, editor, task_updates, refreshed, old_valid, old_cursor, modules, saved
	local name = "atlas.issues.providers.shortcut.ui.overview"

	before_each(function()
		mappings, removed, task_updates = {}, {}, {}
		refreshed = 0
		local task = { id = 9, description = "Native task", complete = false, position = 1 }
		state = {
			win = 10,
			current_issue = { id = 42, key = "42" },
			current_details = { tasks = { task } },
			line_map = { [1] = { shortcut_task = task } },
		}
		old_valid, old_cursor = vim.api.nvim_win_is_valid, vim.api.nvim_win_get_cursor
		vim.api.nvim_win_is_valid = function()
			return true
		end
		vim.api.nvim_win_get_cursor = function()
			return { 1, 0 }
		end
		modules = {
			["atlas.issues.ui.detail.state"] = state,
			["atlas.issues.ui.detail.tabs.activity"] = { reset = function() end },
			["atlas.issues.ui.detail.tabs.overview"] = {
				render = function()
					return { "Shared Markdown" }, {}, {}
				end,
				activate = function()
					mappings.markdown = true
				end,
				deactivate = function()
					removed.markdown = true
				end,
			},
			["atlas.ui.popups.editor"] = {
				open = function(opts)
					editor = opts
				end,
			},
			["atlas.core.keymaps"] = {
				resolve = function(id)
					return { id }
				end,
			},
			["atlas.ui.popups.help"] = {
				register = function(_, items)
					for _, item in ipairs(items) do
						mappings[item.key] = item.callback
					end
				end,
				remove = function(_, items)
					for _, item in ipairs(items) do
						removed[item.key] = true
					end
				end,
			},
			["atlas.core.notify"] = { loading = function() end, success = function() end },
			["atlas.issues.providers.shortcut.api.tasks"] = {
				update = function(issue, selected, fields, done)
					task_updates[#task_updates + 1] = { issue = issue, task = selected, fields = fields }
					done(vim.tbl_extend("force", selected, fields), nil)
				end,
			},
		}
		saved = {}
		for key, value in pairs(modules) do
			saved[key] = package.loaded[key]
			package.loaded[key] = value
		end
		package.loaded[name] = nil
		overview = require(name)
		overview.activate(1, function()
			refreshed = refreshed + 1
		end)
	end)

	after_each(function()
		for key in pairs(modules) do
			package.loaded[key] = saved[key]
		end
		package.loaded[name] = nil
		vim.api.nvim_win_is_valid, vim.api.nvim_win_get_cursor = old_valid, old_cursor
	end)

	it("keeps shared description rendering and adds native selectable tasks", function()
		local lines, _, map = overview.render(state.current_issue, state.current_details, 80)
		assert.equal("Shared Markdown", lines[1])
		assert.equal(" - [ ] Native task", lines[#lines])
		assert.equal(9, map[#lines].shortcut_task.id)
		assert.is_true(overview.is_selectable_line(#lines, map[#lines]))
	end)

	it("edits and toggles tasks with configured actions", function()
		mappings["ui.comments.edit"]()
		assert.equal("Native task", editor.initial_text)
		editor.on_save("Updated task")
		assert.same({ description = "Updated task" }, task_updates[1].fields)
		assert.equal("Updated task", state.current_details.tasks[1].description)
		mappings["issues.toggle_task"]()
		assert.same({ complete = true }, task_updates[2].fields)
		assert.is_true(state.current_details.tasks[1].complete)
		assert.equal(2, refreshed)
	end)

	it("removes task and shared description mappings on tab changes", function()
		assert.is_true(mappings.markdown)
		overview.deactivate(1)
		for _, key in ipairs({ "markdown", "ui.comments.add", "ui.comments.edit", "ui.delete", "issues.toggle_task" }) do
			assert.is_true(removed[key])
		end
	end)
end)
