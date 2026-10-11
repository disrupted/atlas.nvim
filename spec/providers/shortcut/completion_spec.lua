describe("Shortcut user completion", function()
	local module_name = "atlas.providers.shortcut.completion"
	local users_name = "atlas.providers.shortcut.users"
	local saved_module, saved_users, done, handle

	before_each(function()
		saved_module, saved_users = package.loaded[module_name], package.loaded[users_name]
		package.loaded[module_name] = nil
		handle = { cancel = function() end }
		package.loaded[users_name] = {
			list = function(callback)
				done = callback
				return handle
			end,
		}
	end)

	after_each(function()
		package.loaded[module_name], package.loaded[users_name] = saved_module, saved_users
	end)

	it("returns cancellable shared completion items with Shortcut handles", function()
		local source = require(module_name).users
		local items
		assert.same({ "@" }, source.triggers)
		assert.equal(
			handle,
			source.complete({ provider = "shortcut", issue = { key = "123" } }, "ada", function(value, err)
				assert.is_nil(err)
				items = value
			end)
		)
		done({
			{ id = "owner", name = "Ada Owner", username = "ada.owner" },
			{ id = "duplicate", name = "Ada Owner", username = "ada.owner" },
			{ id = "disabled", name = "Old Owner", username = "old", disabled = true },
			{ id = "missing", name = "No Handle" },
		}, nil)
		assert.same({
			{
				label = "@ada.owner",
				insert_text = "@ada.owner",
				filter_text = "ada.owner Ada Owner",
				detail = "Ada Owner",
			},
		}, items)
	end)

	it("reports member lookup failures to the completion framework", function()
		local items, err
		require(module_name).users.complete({ provider = "shortcut" }, "", function(value, error)
			items, err = value, error
		end)
		done(nil, "HTTP 401")
		assert.is_nil(items)
		assert.equal("HTTP 401", err)
	end)
end)
