local actions = require("atlas.pulls.diff.actions")
local picker = require("atlas.ui.picker")
local providers = require("atlas.providers")

describe("diff review actions", function()
	local original_load, original_select, items
	before_each(function()
		original_load, original_select = providers.load, picker.select
		picker.select = function(opts)
			items = vim.tbl_map(function(action)
				return action.id
			end, opts.items)
		end
	end)
	after_each(function()
		providers.load, picker.select = original_load, original_select
	end)

	local function open(pending, supports_pending)
		providers.load = function()
			return {
				capabilities = {
					reviews = {
						start_review = supports_pending and function() end or nil,
						submit_review = function() end,
						discard_review = function() end,
					},
				},
			}
		end
		actions.open_actions.run({
			session = {
				data = {
					pr = { provider = "gitea", state = "open" },
					review = { data = { review = { pending = pending } } },
					commits = {},
				},
			},
		}, function() end)
	end

	it("offers direct submission when the provider has no pending reviews", function()
		open(false, false)
		assert.same({ "submit_review", "toggle_detail_panel" }, items)
	end)

	it("offers start and submit at the correct stage for providers with pending reviews", function()
		open(false, true)
		assert.same({ "start_review", "toggle_detail_panel" }, items)
		open(true, true)
		assert.same({ "submit_review", "discard_review", "toggle_detail_panel" }, items)
	end)
end)
