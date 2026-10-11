local CLIENT = "atlas.providers.shortcut.client"
local MODULES = {
	"atlas.providers.shortcut.users",
	"atlas.issues.providers.shortcut.api.stories",
	"atlas.issues.providers.shortcut.api.comments",
	"atlas.issues.providers.shortcut.api.tasks",
	"atlas.issues.providers.shortcut.api.workflows",
}

describe("Shortcut backend workflows", function()
	local saved, client, calls, pending, cached, invalidated, replies, errors, deferred
	local current = { id = "owner", name = "Ada Owner", mention_name = "ada.owner" }
	local member = { id = "owner", profile = { name = "Ada Owner", mention_name = "ada.owner" }, disabled = false }
	local story = {
		id = 123,
		name = "A Story",
		story_type = "feature",
		workflow_state_id = 10,
		owner_ids = { "owner" },
		requested_by_id = "owner",
		description = "Story description",
		app_url = "https://app.shortcut.com/acme/story/123/a-story",
	}

	before_each(function()
		saved = { [CLIENT] = package.loaded[CLIENT] }
		for _, name in ipairs(MODULES) do
			saved[name] = package.loaded[name]
			package.loaded[name] = nil
		end
		calls, pending, cached, invalidated, errors = {}, {}, {}, {}, {}
		deferred = false
		replies = {
			["/member"] = current,
			["/members"] = { member },
			["/workflows"] = { { id = 1, name = "Development", states = { { id = 10, name = "Todo", position = 0 } } } },
			["/stories/123"] = story,
		}
		client = {
			get_cache = function(key)
				return cached[key], cached[key] ~= nil
			end,
			set_cache = function(key, value)
				cached[key] = value
			end,
			clear_cache = function(prefix)
				table.insert(invalidated, prefix)
				for key in pairs(cached) do
					if key:sub(1, #prefix) == prefix then
						cached[key] = nil
					end
				end
			end,
			request = function(method, endpoint, data, done)
				local call = { method = method, endpoint = endpoint, data = data }
				table.insert(calls, call)
				local complete = function()
					done(not errors[endpoint] and (replies[endpoint] or {}) or nil, errors[endpoint])
				end
				if deferred then
					table.insert(pending, complete)
				else
					complete()
				end
				return {
					cancel = function()
						call.cancelled = true
					end,
				}
			end,
		}
		client.get_memory_cache = client.get_cache
		client.set_memory_cache = client.set_cache
		package.loaded[CLIENT] = client
	end)

	after_each(function()
		package.loaded[CLIENT] = saved[CLIENT]
		for _, name in ipairs(MODULES) do
			package.loaded[name] = saved[name]
		end
	end)

	it("normalizes current members and member lists to the shared user model", function()
		local users = require("atlas.providers.shortcut.users")
		local me, members
		users.fetch_user(function(value, err)
			assert.is_nil(err)
			me = value
		end)
		users.list(function(value, err)
			assert.is_nil(err)
			members = value
		end)
		assert.same({ id = "owner", name = "Ada Owner", username = "ada.owner", disabled = false }, me)
		assert.same(me, members[1])
		assert.same(me, cached["user:v2"])
	end)

	it("validates the workspace before returning cached details", function()
		local stories = require("atlas.issues.providers.shortcut.api.stories")
		local details, err
		local done = function(value, error)
			details, err = value, error
		end
		stories.get(123, { workspace = "acme" }, done)
		assert.is_nil(err)
		assert.equal("A Story", details.title)
		assert.equal("owner", details.assignees[1].id)
		stories.get(123, { workspace = "other" }, done)
		assert.is_nil(details)
		assert.equal("Shortcut Story does not belong to workspace other", err)
	end)

	it("preserves the query and server cursor while refreshing cached metadata", function()
		local stories = require("atlas.issues.providers.shortcut.api.stories")
		local endpoint = "/search/stories?query=owner%3Ame&page_size=25&detail=slim"
		replies[endpoint] = { data = { story }, total = 2000, next = "/api/v3/search/stories?next=stable" }
		replies["/search/stories?next=stable"] = { data = {}, total = 2000 }
		local page
		local done = function(value, err)
			assert.is_nil(err)
			page = value
		end
		stories.search("owner:me", { pagelen = 25 }, done)
		assert.equal("owner:me", page.query)
		assert.equal(40, page.total_pages)
		assert.equal("/search/stories?next=stable", page.next_cursor)
		local count = #calls
		stories.search("owner:me", { pagelen = 25 }, done)
		assert.equal(count, #calls)
		assert.equal("owner:me", page.query)
		replies["/members"] = { { id = "owner", profile = { name = "Renamed Owner" } } }
		replies["/workflows"][1].states[1].name = "Ready"
		stories.search("owner:me", { pagelen = 25, force_refresh = true }, done)
		assert.equal("Renamed Owner", page.items[1].assignee.name)
		assert.equal("Ready", page.items[1].status)
		stories.search("owner:me", { pagelen = 25, cursor = page.next_cursor }, done)
		assert.equal("/search/stories?next=stable", calls[#calls].endpoint)
		assert.same({}, page.items)
		assert.is_nil(page.next_cursor)
	end)

	it("keeps the editable query when metadata or search requests fail", function()
		local stories = require("atlas.issues.providers.shortcut.api.stories")
		local page, err
		local done = function(value, error)
			page, err = value, error
		end
		errors["/members"] = "HTTP 401"
		stories.search("owner:me", {}, done)
		assert.same({ items = {}, query = "owner:me" }, page)
		assert.equal("HTTP 401", err)
		errors["/members"] = nil
		errors["/search/stories?query=owner%3Ame&page_size=50&detail=slim"] = "HTTP 400"
		stories.search("owner:me", {}, done)
		assert.same({ items = {}, query = "owner:me" }, page)
		assert.equal("HTTP 400", err)
	end)

	it("bypasses persisted search entries from the model without type icons", function()
		local endpoint = "/search/stories?query=owner%3Ame&page_size=50&detail=slim"
		cached["search:v3:" .. endpoint] = { items = { { key = "123", title = "Old cached Story" } } }
		replies[endpoint] = { data = { story }, total = 1 }
		local issue
		require("atlas.issues.providers.shortcut.api.stories").search("owner:me", {}, function(page, err)
			assert.is_nil(err)
			issue = page.items[1]
		end)
		assert.equal("A Story", issue.title)
		assert.same({ icon = "󰃀", hl_group = "AtlasTextPositive" }, issue.icon)
		assert.equal(issue.icon, issue.type.icon)
	end)

	it("checks workspace and invalid keys when fetching Story references", function()
		local stories = require("atlas.issues.providers.shortcut.api.stories")
		local issues, err
		local done = function(value, error)
			issues, err = value, error
		end
		stories.fetch_by_refs({ { key = "123", workspace = "acme" } }, {}, done)
		assert.equal("123", issues[1].key)
		assert.is_nil(err)
		stories.fetch_by_refs({ { key = "123", workspace = "other" } }, {}, done)
		assert.same({}, issues)
		assert.equal("#123: Shortcut Story does not belong to workspace other", err)
		local count = #calls
		stories.fetch_by_refs({ { key = "123junk" } }, {}, done)
		assert.equal("Invalid Shortcut Story key: 123junk", err)
		assert.equal(count, #calls)
	end)

	it("fetches batch metadata once and preserves reference order despite response order", function()
		deferred = true
		replies["/stories/124"] = vim.tbl_extend("force", {}, story, { id = 124, name = "Second Story" })
		local issues, err
		require("atlas.issues.providers.shortcut.api.stories").fetch_by_refs(
			{ { key = "124" }, { key = "123" } },
			{ force_refresh = true },
			function(value, error)
				issues, err = value, error
			end
		)
		assert.is_nil(issues)
		for index = #pending, 1, -1 do
			pending[index]()
		end
		assert.is_nil(err)
		assert.equal("124", issues[1].key)
		assert.equal("123", issues[2].key)
		assert.equal("Todo", issues[1].status)
		assert.equal("Ada Owner", issues[2].assignee.name)
		local counts = {}
		for _, call in ipairs(calls) do
			counts[call.endpoint] = (counts[call.endpoint] or 0) + 1
		end
		assert.same({ ["/members"] = 1, ["/workflows"] = 1, ["/stories/123"] = 1, ["/stories/124"] = 1 }, counts)
	end)

	it("reuses raw Story caches and refreshes a batch with fresh metadata", function()
		local stories = require("atlas.issues.providers.shortcut.api.stories")
		replies["/stories/124"] = vim.tbl_extend("force", {}, story, { id = 124, name = "Second Story" })
		local refs = { { key = "123" }, { key = "124" } }
		local issues
		local done = function(value, err)
			assert.is_nil(err)
			issues = value
		end
		stories.fetch_by_refs(refs, {}, done)
		assert.equal(4, #calls)
		stories.get(123, {}, function(details, err)
			assert.is_nil(err)
			assert.equal("A Story", details.title)
		end)
		stories.fetch_by_refs(refs, {}, done)
		assert.equal(4, #calls)
		replies["/stories/123"] = vim.tbl_extend("force", {}, story, { name = "Changed Story" })
		replies["/members"] = { { id = "owner", profile = { name = "Renamed Owner" } } }
		replies["/workflows"][1].states[1].name = "Ready"
		stories.fetch_by_refs(refs, { force_refresh = true }, done)
		assert.equal(8, #calls)
		assert.equal("Changed Story", issues[1].title)
		assert.equal("Ready", issues[2].status)
		assert.equal("Renamed Owner", issues[2].assignee.name)
	end)

	it("returns successful refs with ordered per-ref request and workspace errors", function()
		local stories = require("atlas.issues.providers.shortcut.api.stories")
		replies["/stories/124"] = vim.tbl_extend("force", {}, story, { id = 124 })
		replies["/stories/125"] = vim.tbl_extend("force", {}, story, { id = 125 })
		errors["/stories/999"] = "HTTP 404"
		local issues, err
		stories.fetch_by_refs({
			{ key = "123", workspace = "acme" },
			{ key = "999", workspace = "acme" },
			{ key = "124", workspace = "other" },
			{ key = "125", workspace = "acme" },
		}, { force_refresh = true }, function(value, error)
			issues, err = value, error
		end)
		assert.equal(2, #issues)
		assert.equal("123", issues[1].key)
		assert.equal("125", issues[2].key)
		assert.equal("#999: HTTP 404\n#124: Shortcut Story does not belong to workspace other", err)
	end)

	it("creates replies through shared parent options and invalidates cached data", function()
		replies["/stories/123/comments"] = { id = 456, text = "A reply", author_id = "owner", parent_id = 100 }
		cached["story:123"] = story
		cached["search:v4:query"] = { items = { story } }
		local result
		require("atlas.issues.providers.shortcut.api.comments").add_comment(
			story,
			"A reply",
			{ parent = { id = "100" } },
			function(value, err)
				assert.is_nil(err)
				result = value
			end
		)
		assert.same({ text = "A reply", parent_id = 100 }, calls[#calls].data)
		assert.equal("owner", result.author.id)
		assert.equal(100, result.parent_id)
		assert.same({ "story:123", "search:" }, invalidated)
		assert.is_nil(cached["story:123"])
		assert.is_nil(cached["search:v4:query"])
	end)

	it("invalidates details and searches after checklist mutations", function()
		replies["/stories/123/tasks/9"] = { id = 9, description = "Verify", complete = true, position = 1 }
		local task
		require("atlas.issues.providers.shortcut.api.tasks").update(
			story,
			{ id = 9 },
			{ complete = true },
			function(value, err)
				assert.is_nil(err)
				task = value
			end
		)
		assert.is_true(task.complete)
		assert.same({ "story:123", "search:" }, invalidated)
	end)

	it("maps nested replies and deleted roots into shared threads and refreshes authors", function()
		replies["/stories/123/comments"] = {
			{ id = 102, parent_id = 101, author_id = "owner", text = "Nested reply", created_at = "2026-08-25" },
			{ id = 101, parent_id = 100, author_id = "owner", text = "A reply", created_at = "2026-08-24" },
			{ id = 100, author_id = "owner", deleted = true, created_at = "2026-08-23" },
		}
		local comments_api = require("atlas.issues.providers.shortcut.api.comments")
		local comments
		local done = function(value, err)
			assert.is_nil(err)
			comments = value
		end
		comments_api.list(story, {}, done)
		local groups = require("atlas.issues.ui.components.comment_threads").group_comments(comments)
		assert.equal(1, #groups)
		assert.equal("100", groups[1].comment.id)
		assert.is_true(groups[1].comment.deleted)
		assert.equal("102", groups[1].children[1].children[1].comment.id)
		assert.equal("Ada Owner", groups[1].children[1].comment.author.name)
		replies["/members"] = { { id = "owner", profile = { name = "Renamed Owner" } } }
		comments_api.list(story, { force_refresh = true }, done)
		assert.equal("Renamed Owner", comments[1].author.name)
	end)

	it("cancels metadata requests and prevents late search requests", function()
		deferred = true
		local delivered = false
		local scope = require("atlas.issues.providers.shortcut.api.stories").search("owner:me", {}, function()
			delivered = true
		end)
		scope.cancel()
		for _, complete in ipairs(pending) do
			complete()
		end
		assert.equal(2, #calls)
		assert.is_true(calls[1].cancelled)
		assert.is_true(calls[2].cancelled)
		assert.is_false(delivered)
	end)
end)
