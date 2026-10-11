local config = require("atlas.config")
local factory = require("atlas.pulls.providers.forge.api.pullrequests")
local mapper_factory = require("atlas.pulls.providers.forge.api.mapper")

for _, id in ipairs({ "gitea", "forgejo" }) do
	describe(id .. " shared pull editor API", function()
		local old_config, raw, service, api, requests, cleared
		before_each(function()
			old_config = config.domain_options
			config.domain_options = function()
				return { draft_prefix = "Draft:" }
			end
			raw = {
				number = 3,
				title = "Draft: Original",
				draft = true,
				state = "open",
				user = { id = 1, login = "author" },
				head = { ref = "feature", sha = "head", repo = { full_name = "owner/repo" } },
				base = { ref = "main", sha = "base", repo = { full_name = "owner/repo" } },
			}
			requests, cleared = {}, {}
			service = {
				id = id,
				name = id,
				url_encode = tostring,
				base_url = function()
					return "https://forge.example"
				end,
				clear_cache = function(key)
					table.insert(cleared, key)
				end,
				delete_memory_cache = function(key)
					table.insert(cleared, key)
				end,
				users = {
					fetch_user = function(done)
						done({ id = "2", username = "me" }, nil)
					end,
				},
				fetch_all = function(endpoint, _, _, done)
					if endpoint:match("/labels$") then
						done({ { id = 5, name = "bug", color = "ff0000" } }, nil)
					elseif endpoint:match("/reviews$") then
						done({ { id = 11, state = "REQUEST_REVIEW", user = { id = 4, login = "old" } } }, nil)
					else
						error("Unexpected endpoint: " .. endpoint)
					end
				end,
				request = function(method, endpoint, data, done)
					table.insert(requests, { method = method, endpoint = endpoint, data = data })
					if method == "PATCH" then
						for key, value in pairs(data) do
							raw[key] = value
						end
						raw.draft = raw.title:sub(1, 6) == "Draft:"
					end
					done(vim.deepcopy(raw), nil)
				end,
			}
			api = factory.new(service, mapper_factory.new(id))
		end)
		after_each(function()
			config.domain_options = old_config
		end)

		it("saves shared editor fields and reviewer differences while preserving draft prefixes", function()
			local pr = mapper_factory.new(id).to_pull_request(raw)
			local saved, err
			api.update_pr(pr, {
				title = "Renamed",
				body = "New description",
				base = "release",
				labels = { "bug" },
				assignees = { { id = "6", username = "assignee", name = "Assignee" } },
				reviewers = { { provider_id = "new", label = "@new" } },
			}, function(ok, error_message)
				saved, err = ok, error_message
			end)
			assert.is_true(saved)
			assert.is_nil(err)
			assert.equal("Draft: Renamed", pr.title)
			assert.equal("draft", pr.state)
			assert.same({ title = "Draft: Renamed" }, requests[1].data)
			assert.same(
				{ body = "New description", base = "release", labels = { 5 }, assignees = { "assignee" } },
				requests[2].data
			)
			assert.same({
				method = "POST",
				endpoint = "/repos/owner/repo/pulls/3/requested_reviewers",
				data = { reviewers = { "new" }, team_reviewers = {} },
			}, requests[3])
			assert.same({
				method = "DELETE",
				endpoint = "/repos/owner/repo/pulls/3/requested_reviewers",
				data = { reviewers = { "old" }, team_reviewers = {} },
			}, requests[4])
			assert.is_true(#cleared > 0)
		end)

		it("removes the configured draft prefix through the shared write contract", function()
			local pr = mapper_factory.new(id).to_pull_request(raw)
			api.update_pr(pr, { draft = false }, function(ok, err)
				assert.is_true(ok)
				assert.is_nil(err)
			end)
			assert.equal("Original", pr.title)
			assert.equal("open", pr.state)
			assert.equal(1, #requests)
		end)

		it("restores the title when the server rejects a draft prefix before editing other fields", function()
			raw.title, raw.draft = "Original", false
			local pr = mapper_factory.new(id).to_pull_request(raw)
			service.request = function(method, endpoint, data, done)
				table.insert(requests, { method = method, endpoint = endpoint, data = data })
				raw.title = data.title
				done(vim.deepcopy(raw), nil)
			end
			local saved, err
			api.update_pr(pr, { draft = true, body = "Must not be changed" }, function(ok, message)
				saved, err = ok, message
			end)
			assert.is_false(saved)
			assert.matches("configure an enabled draft_prefix", err, 1, true)
			assert.equal("Original", pr.title)
			assert.same({ title = "Draft: Original" }, requests[1].data)
			assert.same({ title = "Original" }, requests[2].data)
			assert.equal(2, #requests)
		end)

		it("rejects an unknown label before making mutations", function()
			api.update_pr(
				mapper_factory.new(id).to_pull_request(raw),
				{ title = "Renamed", labels = { "deleted-label" } },
				function(ok, err)
					assert.is_false(ok)
					assert.equal("Unknown label: deleted-label", err)
				end
			)
			assert.same({}, requests)
		end)

		it("clears labels and assignees when the editor selection is empty", function()
			api.update_pr(mapper_factory.new(id).to_pull_request(raw), { labels = {}, assignees = {} }, function(ok)
				assert.is_true(ok)
			end)
			assert.same({ labels = {}, assignees = {} }, requests[1].data)
		end)

		it("passes shared merge options using native API field names", function()
			api.merge(
				mapper_factory.new(id).to_pull_request(raw),
				{ method = "squash", delete_source_branch = true, subject = "Merged title", body = "Merge message" },
				function(ok)
					assert.is_true(ok)
				end
			)
			local data = requests[1].data
			assert.equal("squash", data.Do)
			assert.equal("Merged title", data.MergeTitleField)
			assert.equal("Merge message", data.MergeMessageField)
			assert.is_true(data.delete_branch_after_merge)
			assert.equal("head", data.head_commit_id)
		end)
	end)
end
