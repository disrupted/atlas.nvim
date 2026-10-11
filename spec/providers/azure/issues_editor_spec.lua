local editor_name = "atlas.issues.providers.azure.ui.editor"
local api_name = "atlas.issues.providers.azure.api.issues"
local form_name = "atlas.ui.form"
local notify_name = "atlas.core.notify"
local picker_name = "atlas.ui.picker"
local module_names = { editor_name, api_name, form_name, notify_name, picker_name }

describe("Azure work item editor", function()
	local original = {}
	local original_bo
	local api
	local handle
	local content
	local notices
	local saved
	local pending_save
	local callbacks
	local issue = { key = "42", project = "Platform", title = "Stale title", type = { name = "Task" } }

	before_each(function()
		for _, name in ipairs(module_names) do
			original[name] = package.loaded[name]
			package.loaded[name] = nil
		end
		original_bo = vim.bo
		vim.bo = { [1] = { modifiable = true } }
		notices, callbacks = {}, {}
		saved, pending_save = nil, nil
		package.loaded[notify_name] = {
			loading = function() end,
			clear = function() end,
			error = function() end,
		}
		package.loaded[form_name] = {
			open = function(opts)
				handle = {
					opts = opts,
					editor_buf = 1,
					statusline = {
						notify = function(_, level, message)
							notices[#notices + 1] = { level, message }
						end,
					},
				}
				content = { title = opts.initial_title, body = opts.initial_body }
				handle.meta = opts.meta()
				return handle
			end,
			render_meta = function(editor)
				editor.meta = editor.opts.meta()
			end,
			get_content = function()
				return content
			end,
			close = function(editor)
				if not editor.closed then
					editor.closed = true
					editor.opts.on_closed()
				end
			end,
		}
		api = {
			list_types = function(_, done)
				done({ { name = "Bug" }, { name = "Task" } })
			end,
			fetch_issue = function(_, opts, done)
				assert.is_true(opts.force_refresh)
				done({ title = "Current title", description = "Existing body", description_format = "html" })
			end,
			update = function(_, fields, done, opts)
				saved = { fields = fields, format = opts.format }
				pending_save = done
			end,
			create = function(project, item_type, fields, done)
				saved = { project = project, item_type = item_type, fields = fields }
				pending_save = done
			end,
		}
		package.loaded[api_name] = api
	end)

	after_each(function()
		vim.bo = original_bo
		for _, name in ipairs(module_names) do
			package.loaded[name] = original[name]
		end
	end)

	local function on_done(result, err)
		callbacks[#callbacks + 1] = { result = result, err = err }
	end

	it("uses the shared form with project context and the refreshed title", function()
		require(editor_name).edit(issue, on_done)
		assert.equal("Current title", content.title)
		assert.equal("Existing body", content.body)
		assert.same(
			{ provider = "azure", project = "Platform", issue = { key = "42" } },
			handle.opts.completion.context
		)
		handle.opts.close(handle)
		assert.is_true(handle.closed)
		assert.equal(1, #callbacks)
		assert.is_nil(callbacks[1].result)
		assert.is_nil(saved)
	end)

	it("does not overwrite an unchanged HTML description when saving a title", function()
		require(editor_name).edit(issue, on_done)
		content.title = "Updated title"
		handle.opts.submit(handle)
		assert.same({ ["System.Title"] = "Updated title" }, saved.fields)
		assert.equal("html", saved.format)
		assert.is_false(vim.bo[1].modifiable)
		pending_save(true)
		assert.is_true(handle.closed)
		assert.equal(1, #callbacks)
		assert.equal(issue, callbacks[1].result)
	end)

	it("keeps the editor open and allows retry after a failed save", function()
		require(editor_name).edit(issue, on_done)
		content.body = "Changed body"
		handle.opts.submit(handle)
		pending_save(false, "Server rejected update")
		assert.is_not_true(handle.closed)
		assert.is_true(vim.bo[1].modifiable)
		assert.same({ "error", "Server rejected update" }, notices[#notices])
		assert.equal(0, #callbacks)
		handle.opts.submit(handle)
		assert.equal("Changed body", saved.fields["System.Description"])
		pending_save(true)
		assert.equal(1, #callbacks)
	end)

	it("creates work items with the existing default Task type and reports success once", function()
		require(editor_name).open("Platform", on_done)
		content.title, content.body = "New task", "Task body"
		handle.opts.submit(handle)
		assert.same({
			project = "Platform",
			item_type = "Task",
			fields = { ["System.Title"] = "New task", ["System.Description"] = "Task body" },
		}, saved)
		pending_save({ key = "43" })
		assert.is_true(handle.closed)
		assert.same({ { result = { key = "43" } } }, callbacks)
	end)

	it("renders and selects work item types in the shared editor", function()
		package.loaded[picker_name] = {
			select = function(opts)
				local label, hl = opts.format_item(opts.items[1])
				assert.is_truthy(label:find("Bug", 1, true))
				assert.is_string(hl)
				opts.on_select(opts.items[1])
			end,
		}
		require(editor_name).open("Platform", on_done)
		assert.is_truthy(handle.meta[1][2].value:find("Task", 1, true))
		handle.opts.keymaps[1].action(handle)
		assert.is_truthy(handle.meta[1][2].value:find("Bug", 1, true))
		content.title = "New bug"
		handle.opts.submit(handle)
		assert.equal("Bug", saved.item_type)
	end)
end)
