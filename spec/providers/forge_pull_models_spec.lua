local factory = require("atlas.pulls.providers.forge.api.mapper")

for _, id in ipairs({ "gitea", "forgejo" }) do
	describe(id .. " shared pull models", function()
		local mapper = factory.new(id)
		it("keeps pending reviews independent from thread resolution and outdated state", function()
			local comment = mapper.to_comment(
				{ id = 9, body = "Draft comment", resolver = { id = 3, login = "reviewer" } },
				{ state = "PENDING", stale = true }
			)
			assert.is_true(comment.pending)
			assert.equal("RESOLVED", comment.state)
			assert.is_true(comment.outdated)
			assert.equal("reviewer", comment.resolved_by.username)
			local active = mapper.to_comment({ id = 10 }, { state = "PENDING" })
			assert.is_true(active.pending)
			assert.is_nil(active.state)
		end)

		it("maps assignees to shared users without retaining obsolete label ids", function()
			local details = mapper.to_pull_request_details({
				assignees = { { id = 2, login = "alice", full_name = "Alice" } },
				labels = { { id = 4, name = "bug", color = "#ff0000" } },
			})
			assert.same({ { id = "2", username = "alice", name = "Alice" } }, details.assignees)
			assert.same({ { name = "bug", color = "ff0000" } }, details.labels)
			assert.is_nil(details.label_ids)
		end)

		it("retains repository metadata in search results for shared repository actions", function()
			local pr = mapper.to_search_pull_request({
				number = 7,
				title = "Search result",
				user = { id = 2, login = "alice" },
				repository = { full_name = "owner/repo", html_url = "https://forge.example/owner/repo" },
				pull_request = { html_url = "https://forge.example/owner/repo/pulls/7", draft = false, merged = false },
			})
			assert.same({
				id = "owner/repo",
				owner = "owner",
				name = "repo",
				repo_name = "repo",
				full_name = "owner/repo",
				html_url = "https://forge.example/owner/repo",
			}, pr.repo)
			assert.equal("refs/pull/7/head", pr.source.fetch_ref)
		end)
	end)
end

describe("Gitea comment editing", function()
	it("retains review metadata omitted from the edit response", function()
		local service = require("atlas.providers.forge.gitea.api")
		local comments = require("atlas.pulls.providers.forge.gitea.api.comments")
		local original = service.request
		service.request = function(method, endpoint, payload, done)
			assert.equal("PATCH", method)
			assert.equal("/repos/owner/repo/issues/comments/9", endpoint)
			done({ id = 9, body = payload.body, user = { id = 2, login = "alice" } }, nil)
		end
		local ok, err = xpcall(function()
			comments.edit({ id = 7, repo_full_name = "owner/repo" }, {
				id = 9,
				content_raw = "Edited draft",
				pending = true,
				outdated = true,
				state = "RESOLVED",
				inline = { path = "main.lua", to = 2 },
			}, function(comment, edit_err)
				assert.is_nil(edit_err)
				assert.equal("Edited draft", comment.content_raw)
				assert.is_true(comment.pending)
				assert.is_true(comment.outdated)
				assert.equal("RESOLVED", comment.state)
				assert.equal("main.lua", comment.inline.path)
			end)
		end, debug.traceback)
		service.request = original
		if not ok then
			error(err)
		end
	end)
end)
