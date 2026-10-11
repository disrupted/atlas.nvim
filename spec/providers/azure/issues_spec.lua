local client_name = "atlas.providers.azure.client"
local module_names = {
	client_name,
	"atlas.providers.azure.users",
	"atlas.issues.providers.azure.api.mapper",
	"atlas.issues.providers.azure.api.issues",
	"atlas.issues.providers.azure.api.comments",
}

describe("Azure work items", function()
	local original = {}
	local client
	local calls

	before_each(function()
		for _, name in ipairs(module_names) do
			original[name] = package.loaded[name]
			package.loaded[name] = nil
		end
		local real_client = require(client_name)
		calls = {}
		client = {
			url_encode = real_client.url_encode,
			build_query = real_client.build_query,
			base_url = function()
				return "https://dev.azure.com/acme"
			end,
			get_cache = function()
				return nil, false
			end,
			set_cache = function() end,
			clear_cache = function() end,
			request = function(method, endpoint, payload, done)
				calls[#calls + 1] = { method = method, endpoint = endpoint, payload = payload }
				done({}, nil)
			end,
		}
		package.loaded[client_name] = client
	end)

	after_each(function()
		for _, name in ipairs(module_names) do
			package.loaded[name] = original[name]
		end
	end)

	it("maps work item participants and editable details to shared models", function()
		local raw = {
			id = 42,
			fields = {
				["System.Title"] = "Current title",
				["System.TeamProject"] = "Platform",
				["System.WorkItemType"] = "Task",
				["System.AssignedTo"] = { id = "alice", displayName = "Alice", uniqueName = "alice@example.com" },
				["System.CreatedBy"] = { id = "bob", displayName = "Bob" },
				["System.Description"] = "Body",
			},
			multilineFieldsFormat = { ["System.Description"] = "markdown" },
		}
		local mapper = require("atlas.issues.providers.azure.api.mapper")
		local issue = mapper.to_issue(raw)
		local details = mapper.to_issue_details(raw)
		assert.same({ id = "alice", name = "Alice", username = "alice@example.com" }, issue.assignee)
		assert.same({ id = "bob", name = "Bob" }, issue.reporter)
		assert.same({ issue.assignee }, details.assignees)
		assert.equal("Current title", details.title)
		assert.equal("markdown", details.description_format)
	end)

	it("accepts the current shared add-comment callback signature", function()
		client.request = function(method, endpoint, payload, done)
			assert.equal("POST", method)
			assert.equal("/Platform/_apis/wit/workItems/42/comments?format=markdown", endpoint)
			assert.same({ text = "Hello @<alice>" }, payload)
			done({
				id = 7,
				text = payload.text,
				format = "markdown",
				createdBy = { id = "alice", displayName = "Alice" },
			})
		end
		local completed = false
		require("atlas.issues.providers.azure.api.comments").add_comment(
			{ id = 42, key = "42", project = "Platform" },
			"Hello @<alice>",
			nil,
			function(comment, err)
				completed = true
				assert.is_nil(err)
				assert.equal("Hello @<alice>", comment.body)
				assert.equal("Hello @Alice", comment.body_display)
				assert.same({ id = "alice", name = "Alice" }, comment.author)
			end
		)
		assert.is_true(completed)
	end)

	it("returns WIQL in the page model for the dashboard and edit-search action", function()
		local query = "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project"
		client.request = function(method, _, payload, done)
			assert.equal("POST", method)
			assert.same({ query = query }, payload)
			done({ queryType = "flat", workItems = {} })
		end
		local completed = false
		require("atlas.issues.providers.azure.api.issues").list_issues(
			{ project = "Platform", search = query },
			{},
			function(page, err)
				completed = true
				assert.is_nil(err)
				assert.equal(query, page.query)
				assert.same({}, page.items)
			end
		)
		assert.is_true(completed)
	end)

	it("resolves mentions across comment pages without changing editable text", function()
		local pages = 0
		client.request = function(_, _, _, done)
			pages = pages + 1
			if pages == 1 then
				done({
					comments = { { id = 1, text = "Hi @<alice> and @<unknown>", format = "markdown" } },
					continuationToken = "next",
				})
			else
				done({
					comments = {
						{
							id = 2,
							text = "Reply",
							format = "markdown",
							createdBy = { id = "alice", displayName = "Alice" },
						},
					},
				})
			end
		end
		local completed = false
		require("atlas.issues.providers.azure.api.comments").fetch_conversation(
			{ id = 42, key = "42", project = "Platform" },
			{},
			function(items, err)
				completed = true
				assert.is_nil(err)
				assert.equal(2, #items)
				assert.equal("Hi @<alice> and @<unknown>", items[1].entity.body)
				assert.equal("Hi @Alice and @<unknown>", items[1].entity.body_display)
			end
		)
		assert.is_true(completed)
	end)

	it("only switches the description format when a Markdown description is written", function()
		local api = require("atlas.issues.providers.azure.api.issues")
		api.update({ key = "42" }, { ["System.Title"] = "New title" }, function(ok)
			assert.is_true(ok)
		end, { format = "markdown" })
		assert.same({ { op = "add", path = "/fields/System.Title", value = "New title" } }, calls[1].payload)
		api.update({ key = "42" }, { ["System.Description"] = "Body" }, function(ok)
			assert.is_true(ok)
		end, { format = "markdown" })
		assert.same({
			{ op = "add", path = "/fields/System.Description", value = "Body" },
			{ op = "add", path = "/multilineFieldsFormat/System.Description", value = "Markdown" },
		}, calls[2].payload)
	end)
end)
