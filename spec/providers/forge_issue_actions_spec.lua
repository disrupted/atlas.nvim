local actions = require("atlas.issues.actions")
local registry_factory = require("atlas.issues.providers.forge.actions.registry")
local config = require("atlas.config")
local notify = require("atlas.core.notify")

for _, provider_id in ipairs({ "gitea", "forgejo" }) do
	describe(provider_id .. " issue state actions", function()
		local old, ctx, input, prompt, writes, results

		before_each(function()
			old = {
				ui = vim.ui,
				loading = notify.loading,
				success = notify.success,
				custom_actions = config.options.issues.custom_actions,
			}
			notify.loading, notify.success = function() end, function() end
			config.options.issues.custom_actions = {}
			input, prompt, writes, results = nil, nil, {}, {}
			vim.ui = {
				input = function(opts, done)
					assert.is_nil(input, "confirmation should be requested only once")
					prompt, input = opts.prompt, done
				end,
			}
			local registry = registry_factory.new(provider_id, {
				set_state = function(issue, state, done)
					table.insert(writes, { key = issue.key, state = state })
					done(true, nil)
				end,
			})
			ctx = {
				provider = { id = provider_id, capabilities = { actions = registry } },
				issue = { key = "owner/repo#7", repo_full_name = "owner/repo", number = 7, status_id = "open" },
			}
		end)

		after_each(function()
			vim.ui, notify.loading, notify.success = old.ui, old.loading, old.success
			config.options.issues.custom_actions = old.custom_actions
		end)

		local function done(result, err)
			assert.is_nil(err)
			table.insert(results, result or false)
		end

		for _, action in ipairs({ "close", "transition" }) do
			it("confirms closing through " .. action .. " before sending a mutation", function()
				assert.is_true(actions.run(action, ctx, done))
				assert.equal("Close Issue? [y/N]: ", prompt)
				assert.same({}, writes)
				assert.same({}, results)
				input("yes")
				assert.same({ { key = "owner/repo#7", state = "closed" } }, writes)
				assert.same({ { issue_key = "owner/repo#7" } }, results)
			end)

			it("cancels closing through " .. action .. " without a mutation", function()
				actions.run(action, ctx, done)
				input("n")
				assert.same({}, writes)
				assert.same({ false }, results)
			end)
		end

		it("reopens through the transition shortcut without a close confirmation", function()
			ctx.issue.status_id = "closed"
			assert.is_true(actions.run("transition", ctx, done))
			assert.is_nil(input)
			assert.same({ { key = "owner/repo#7", state = "open" } }, writes)
			assert.same({ { issue_key = "owner/repo#7" } }, results)
		end)
	end)
end
