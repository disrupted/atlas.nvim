local registry = require("atlas.issues.providers.shortcut.actions.registry")
local labels_api = require("atlas.issues.providers.shortcut.api.labels")
local notify = require("atlas.core.notify")
local picker = require("atlas.ui.picker")
local stories_api = require("atlas.issues.providers.shortcut.api.stories")
local users_api = require("atlas.providers.shortcut.users")

describe("Shortcut selection actions", function()
	local originals, selection, requests, results, issue
	local users = { { id = "a", name = "Ada" }, { id = "b", name = "Ben" } }
	local labels = { { id = 1, name = "bug" }, { id = 2, name = "frontend" } }

	before_each(function()
		selection, requests, results = nil, {}, {}
		issue = { key = "42", owner_ids = { "b", "a" }, labels = { labels[2], labels[1] } }
		originals = {
			users_list = users_api.list,
			labels_list = labels_api.list,
			update = stories_api.update,
			multi_select = picker.multi_select,
			loading = notify.loading,
			clear = notify.clear,
			success = notify.success,
		}
		users_api.list = function(done)
			done(users, nil)
		end
		labels_api.list = function(done)
			done(labels, nil)
		end
		stories_api.update = function(target, fields, done)
			assert.equal(issue, target)
			requests[#requests + 1] = fields
			done(true, nil)
		end
		picker.multi_select = function(opts)
			selection = opts
		end
		notify.loading = function() end
		notify.clear = function() end
		notify.success = function() end
	end)

	after_each(function()
		users_api.list = originals.users_list
		labels_api.list = originals.labels_list
		stories_api.update = originals.update
		picker.multi_select = originals.multi_select
		notify.loading = originals.loading
		notify.clear = originals.clear
		notify.success = originals.success
	end)

	local function run(action)
		assert(registry.find(action)).run({ issue = issue }, function(value, err)
			results[#results + 1] = { value = value, err = err }
		end)
	end

	local function assert_no_change()
		assert.same({}, requests)
		assert.same({ {} }, results)
	end

	it("does not update owners when cancelling a picker ordered differently from the Story", function()
		run("assign")
		assert.same({ users[1], users[2] }, selection.selected)
		-- Shared multi_select returns its initial selection when cancelled.
		selection.on_done(selection.selected)
		assert_no_change()
	end)

	it("does not update owners when the same owners are confirmed in a different order", function()
		run("assign")
		selection.on_done({ users[1], users[2] })
		assert_no_change()
	end)

	it("updates owners when an owner is removed", function()
		run("assign")
		selection.on_done({ users[1] })
		assert.same({ { owner_ids = { "a" } } }, requests)
		assert.same({ { value = { issue_key = "42" } } }, results)
	end)

	it("does not update labels when the picker is cancelled", function()
		run("labels")
		selection.on_done(selection.selected)
		assert_no_change()
	end)

	it("does not update labels when the same labels are confirmed in a different order", function()
		run("labels")
		selection.on_done({ labels[1], labels[2] })
		assert_no_change()
	end)

	it("updates labels when a label is removed", function()
		run("labels")
		selection.on_done({ labels[1] })
		assert.same({ { labels = { { name = "bug" } } } }, requests)
		assert.same({ { value = { issue_key = "42" } } }, results)
	end)
end)
