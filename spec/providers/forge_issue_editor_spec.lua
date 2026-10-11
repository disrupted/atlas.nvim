local module = "atlas.issues.providers.forge.ui.editor"
local notify = require("atlas.core.notify")
local deepcompare = require("luassert.util").deepcompare

for _, provider_id in ipairs({ "gitea", "forgejo" }) do
	describe(provider_id .. " issue editor", function()
		local old, editor, submit_done, cancel_count, result_count, final_result
		before_each(function()
			old = {
				module = package.loaded[module],
				form = package.loaded["atlas.ui.form"],
				info = notify.info,
				loading = notify.loading,
				clear = notify.clear,
				current_buf = vim.api.nvim_get_current_buf,
				bo = vim.bo,
				deep_equal = vim.deep_equal,
			}
			package.loaded[module] = nil
			notify.info, notify.loading, notify.clear = function() end, function() end, function() end
			vim.api.nvim_get_current_buf = function()
				return 0
			end
			vim.bo = { [99] = { modifiable = true } }
			vim.deep_equal = deepcompare
			cancel_count, result_count, final_result, submit_done = 0, 0, nil, nil
			local form = {}
			function form.open(opts)
				editor = {
					opts = opts,
					editor_buf = 99,
					content = { title = opts.initial_title, body = opts.initial_body },
					statusline = { notify = function() end, clear_notice = function() end },
				}
				assert.is_false(opts.is_modified(editor))
				for _, row in ipairs(opts.meta(editor)) do
					for _, field in ipairs(row) do
						assert.is_string(field.key)
						assert.is_string(field.value)
					end
				end
				return editor
			end
			function form.get_content(value)
				return value.content
			end
			function form.close(value)
				if value.closed then
					return
				end
				value.closed = true
				value.opts.on_closed(value)
			end
			package.loaded["atlas.ui.form"] = form
		end)
		after_each(function()
			package.loaded[module], package.loaded["atlas.ui.form"] = old.module, old.form
			vim.api.nvim_get_current_buf, vim.bo, vim.deep_equal = old.current_buf, old.bo, old.deep_equal
			notify.info, notify.loading, notify.clear = old.info, old.loading, old.clear
		end)

		local function completed(result)
			result_count, final_result = result_count + 1, result
		end
		local function create()
			local api = {
				create = function(payload, done)
					assert.equal("Draft title", payload.title)
					assert.equal("Raw **body**", payload.body)
					assert.equal("owner/repo", payload.repo_slug)
					submit_done = done
					return {
						cancel = function()
							cancel_count = cancel_count + 1
						end,
					}
				end,
			}
			require(module).new(provider_id, api).open("owner/repo", completed)
			editor.content = { title = "Draft title", body = "Raw **body**" }
		end
		local function edit()
			local issue = {
				key = "owner/repo#7",
				number = 7,
				repo_full_name = "owner/repo",
				title = "Stale",
				content_version = 1,
			}
			local api = {
				get = function(ref, opts, done)
					assert.equal(issue, ref)
					assert.is_true(opts.force_refresh)
					done({
						title = "Current title",
						description = "Raw **body**",
						content_version = 8,
						labels = {},
						assignees = { { id = "3", username = "login", name = "Full Name" } },
						due_date = "2026-10-20T00:00:00Z",
					}, nil)
				end,
				update_issue = function(ref, payload, done)
					if provider_id == "gitea" then
						assert.equal(8, ref.content_version)
					end
					assert.equal("Current title", payload.title)
					assert.equal("Changed **body**", payload.body)
					assert.same({ "login" }, payload.assignees)
					assert.equal("2026-10-20T00:00:00Z", payload.due_date)
					submit_done = done
				end,
				update_labels = function()
					error("Unchanged labels must not be written")
				end,
			}
			require(module).new(provider_id, api).edit(issue, completed)
			assert.equal(1, issue.content_version)
			assert.same(
				{ provider = provider_id, repository = "owner/repo", issue = { key = "owner/repo#7" } },
				editor.opts.completion.context
			)
		end

		it("submits raw content once and uses the shared completion context", function()
			create()
			assert.same({ provider = provider_id, repository = "owner/repo" }, editor.opts.completion.context)
			editor.opts.submit(editor)
			assert.is_false(vim.bo[99].modifiable)
			editor.opts.submit(editor)
			submit_done({ key = "owner/repo#7" }, nil)
			assert.equal(1, result_count)
			assert.same({ key = "owner/repo#7" }, final_result)
			assert.is_true(editor.closed)
		end)

		it("cancels on external form close without late completion", function()
			create()
			editor.opts.submit(editor)
			editor.opts.on_closed(editor)
			assert.equal(1, cancel_count)
			assert.equal(1, result_count)
			assert.is_nil(final_result)
			submit_done({ key = "owner/repo#7" }, nil)
			assert.equal(1, result_count)
		end)

		it("loads current edit fields and sends the matching Gitea content version", function()
			edit()
			assert.equal("Current title", editor.content.title)
			assert.equal("Raw **body**", editor.content.body)
			editor.content.body = "Changed **body**"
			assert.is_true(editor.opts.is_modified(editor))
			editor.opts.submit(editor)
			submit_done({ key = "owner/repo#7", number = 7 }, nil)
			assert.equal(1, result_count)
			assert.equal("owner/repo#7", final_result.key)
			assert.is_true(editor.closed)
		end)

		it("closes an unchanged edit without writing", function()
			edit()
			editor.opts.submit(editor)
			assert.is_nil(submit_done)
			assert.is_true(editor.closed)
			assert.equal(1, result_count)
			assert.is_nil(final_result)
		end)

		it("keeps a failed draft editable for retry", function()
			create()
			editor.opts.submit(editor)
			submit_done(nil, "Unavailable")
			assert.is_true(vim.bo[99].modifiable)
			assert.is_nil(editor.closed)
			assert.equal(0, result_count)
			editor.opts.submit(editor)
			submit_done({ key = "owner/repo#7" }, nil)
			assert.equal(1, result_count)
		end)
	end)
end
