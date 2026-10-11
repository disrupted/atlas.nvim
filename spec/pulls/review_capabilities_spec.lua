local module_names = {
	"atlas.pulls.diff.keymaps",
	"atlas.pulls.actions.review",
	"atlas.core.keymaps",
	"atlas.ui.popups.help",
	"atlas.pulls.diff.ui.commits",
	"atlas.ui.popups.editor",
	"atlas.providers",
}

describe("review capabilities", function()
	local original = {}
	local reviews
	local registered
	local opened

	before_each(function()
		for _, name in ipairs(module_names) do
			original[name] = package.loaded[name]
			package.loaded[name] = nil
		end
		reviews = {}
		registered = {}
		opened = false
		package.loaded["atlas.providers"] = {
			load = function()
				return { capabilities = { reviews = reviews } }
			end,
		}
		package.loaded["atlas.core.keymaps"] = {
			resolve = function(id)
				return { id }
			end,
			custom_items = function()
				return {}
			end,
		}
		package.loaded["atlas.ui.popups.help"] = {
			register = function(name, items)
				registered[name] = items
			end,
		}
		package.loaded["atlas.pulls.diff.ui.commits"] = {}
		package.loaded["atlas.ui.popups.editor"] = {
			open = function()
				opened = true
			end,
		}
	end)

	after_each(function()
		for _, name in ipairs(module_names) do
			package.loaded[name] = original[name]
		end
	end)

	local function keymaps()
		local groups
		require("atlas.pulls.diff.keymaps").setup({
			data = { pr = { provider = "example" } },
			view = { callbacks = {} },
			explorer = { buf = 1 },
			commits = { buf = 2 },
			renderer = {
				setup_keymaps = function(_, _, value)
					groups = value
				end,
			},
		}, {})
		local keys = {}
		for _, group in ipairs(groups) do
			for _, item in ipairs(group.items) do
				keys[item.key[1]] = true
			end
		end
		return keys
	end

	it("offers immediate comments without pending review bindings for providers without submission", function()
		local keys = keymaps()
		assert.is_true(keys["pulls.review.submit_comment"])
		assert.is_true(keys["pulls.review.submit_suggestion"])
		assert.is_nil(keys["pulls.review.add_comment"])
		assert.is_nil(keys["pulls.review.add_suggestion"])
		assert.is_nil(keys["pulls.review.submit_review"])
		for _, item in ipairs(registered.Review) do
			assert.not_equal("pulls.review.submit_review", item.key[1])
		end
	end)

	it("retains pending comment, suggestion and submission bindings for supported providers", function()
		reviews.submit_review = function() end
		local keys = keymaps()
		assert.is_true(keys["pulls.review.submit_comment"])
		assert.is_true(keys["pulls.review.add_comment"])
		assert.is_true(keys["pulls.review.add_suggestion"])
		assert.is_true(keys["pulls.review.submit_review"])
	end)

	it("rejects an explicit pending request before opening an editor", function()
		local completed = false
		local handled = require("atlas.pulls.actions.review").add_comment.run({
			provider = {
				capabilities = {
					comments = {
						add_comment = function()
							error("Must not publish")
						end,
					},
				},
			},
			draft = { pending = true },
			notify = function() end,
		}, function(result, err)
			completed = true
			assert.is_nil(result)
			assert.equal("Provider does not support pending review comments", err)
		end)
		assert.is_false(handled)
		assert.is_false(opened)
		assert.is_true(completed)
	end)
end)
