local list = require("atlas.issues.ui.components.issue_list.providers")
local popup = require("atlas.issues.ui.popup")
local mapper_factory = require("atlas.issues.providers.forge.api.mapper")

for _, provider_id in ipairs({ "gitea", "forgejo" }) do
	describe(provider_id .. " issue architecture", function()
		local mapper = mapper_factory.new(provider_id)
		it("renders normalized users through the shared issue list and popup", function()
			local issue = mapper.to_issue({
				number = 7,
				title = "Issue title",
				state = "open",
				user = { id = 1, login = "reporter", full_name = "Reporter" },
				assignees = { { id = 2, login = "assignee", full_name = "Assignee" } },
			}, "owner/repo")
			assert.same({ id = "1", username = "reporter", name = "Reporter" }, issue.reporter)
			local display = list.get(provider_id, { reloading = { [issue.key] = true }, spinner = "loading" })
			local row = display.values(issue, false, "plain")
			assert.equal(" loading ", row.status)
			assert.is_truthy(row.reporter:find("Reporter", 1, true))
			assert.is_truthy(row.assignee:find("Assignee", 1, true))
			assert.equal(
				"AtlasTextMuted",
				display.highlights({ _issue = issue }, { key = "status" }, { padded = row.status })[1].hl_group
			)
			local text = table.concat(popup.content(issue, { id = provider_id }), "\n")
			assert.is_truthy(text:find("Reporter", 1, true))
			assert.is_truthy(text:find("Assignee", 1, true))
		end)

		it("keeps raw Markdown and refreshed edit metadata in hydrated details", function()
			local details = mapper.to_issue_details({
				title = "Current title",
				body = "<details>\n**Raw**\n</details>",
				content_version = 8,
				due_date = "2026-10-20T00:00:00Z",
			})
			assert.equal("Current title", details.title)
			assert.equal("<details>\n**Raw**\n</details>", details.description)
			assert.equal("2026-10-20T00:00:00Z", details.due_date)
			assert.equal(provider_id == "gitea" and 8 or nil, details.content_version)
			local author = { id = 4, login = "author", full_name = "Author" }
			assert.same(
				{ id = "4", username = "author", name = "Author" },
				mapper.to_comment({ id = 9, user = author }).author
			)
			assert.same(mapper.to_user(author), mapper.to_timeline_entry({ type = "close", user = author }).actor)
		end)

		it("accepts the current comment options contract with flat issue comments", function()
			local service = {
				name = provider_id,
				url_encode = tostring,
				request = function(method, endpoint, payload, done)
					assert.equal("POST", method)
					assert.equal("/repos/owner/repo/issues/7/comments", endpoint)
					assert.same({ body = "Reply **body**" }, payload)
					done({ id = 9, body = payload.body, user = { id = 4, login = "author" } }, nil)
				end,
			}
			local comment
			require("atlas.issues.providers.forge.api.comments").new(service, mapper).add(
				{ repo_full_name = "owner/repo", number = 7 },
				"Reply **body**",
				{ parent = { id = "2" } },
				function(value, err)
					assert.is_nil(err)
					comment = value
				end
			)
			assert.equal("9", comment.id)
			assert.is_nil(comment.parent_id)
			assert.equal("author", comment.author.username)
		end)

		it("omits repositories with issues disabled from issue search", function()
			local service = {
				id = provider_id,
				name = provider_id,
				query = function(params)
					assert.equal("owner", params.q)
					return "?q=owner"
				end,
				request = function(_, endpoint, _, done)
					assert.equal("/repos/search?q=owner", endpoint)
					done({
						data = {
							{ full_name = "owner/enabled", has_issues = true },
							{ full_name = "owner/disabled", has_issues = false },
							{ full_name = "owner/default" },
						},
					}, nil)
				end,
			}
			local results
			require("atlas.issues.providers.forge.api.issues")
				.new(service, mapper)
				.search_repositories("owner", function(items, err)
					assert.is_nil(err)
					results = items
				end)
			assert.same({ "owner/enabled", "owner/default" }, results)
		end)

		it("resolves scoped searches through the shared current user capability", function()
			local params, fetched, cache_key
			local service = {
				id = provider_id,
				name = provider_id,
				url_encode = tostring,
				base_url = function()
					return "https://git.example"
				end,
				get_cache = function()
					return nil, false
				end,
				set_cache = function(key)
					cache_key = key
				end,
				query = function(value)
					params = value
					return "?scoped"
				end,
				users = {
					fetch_user = function(done)
						done({ id = "3", name = "Full Name", username = "login" })
					end,
				},
				request = function(_, endpoint, _, done)
					fetched = endpoint
					done({}, nil)
				end,
			}
			local api = require("atlas.issues.providers.forge.api.issues").new(service, mapper)
			api.list({ repo = "owner/repo", scope = "assigned" }, {}, function(_, err)
				assert.is_nil(err)
			end)
			assert.equal("login", params.assigned_by)
			assert.equal("/repos/owner/repo/issues?scoped", fetched)
			assert.is_truthy(cache_key:find(":list:v3:", 1, true))
			fetched = nil
			service.users.fetch_user = function(done)
				done(nil, nil)
			end
			local failure
			api.list({ repo = "owner/repo", scope = "created" }, {}, function(_, err)
				failure = err
			end)
			assert.equal("Failed to resolve current user", failure)
			assert.is_nil(fetched)
		end)
	end)
end

for _, provider_id in ipairs({ "gitea", "forgejo" }) do
	describe(provider_id .. " issue creation repository resolution", function()
		local module = "atlas.issues.providers.forge.ui.editor"
		local git = require("atlas.core.git")
		local config = require("atlas.config")
		local state = require("atlas.issues.state")
		local old, resolve, opened, registry, handle
		before_each(function()
			old = {
				editor = package.loaded[module],
				git = git.local_repository,
				config = config.domain_options,
				provider = state.provider,
			}
			state.provider = nil
			resolve, opened = nil, nil
			handle = { cancel = function() end }
			git.local_repository = function(_, done)
				resolve = done
				return handle
			end
			config.domain_options = function()
				return { views = { { repo = "configured/repo" } } }
			end
			package.loaded[module] = {
				new = function()
					return {
						open = function(slug)
							opened = slug
						end,
					}
				end,
			}
			registry = require("atlas.issues.providers.forge.actions.registry").new(provider_id, {})
		end)
		after_each(function()
			package.loaded[module], git.local_repository, config.domain_options, state.provider =
				old.editor, old.git, old.config, old.provider
		end)
		it("waits for the current repository callback before opening the editor", function()
			assert.equal(handle, registry.find("create_issue").run({}, function() end))
			assert.is_nil(opened)
			resolve({ provider = provider_id, repo_full_name = "checkout/repo" })
			assert.equal("checkout/repo", opened)
		end)
		it("uses configured repositories when the checkout belongs to another provider", function()
			registry.find("create_issue").run({}, function() end)
			resolve({ provider = "github", repo_full_name = "foreign/repo" })
			assert.equal("configured/repo", opened)
		end)
		it("uses explicit action context without consulting Git", function()
			registry.find("create_issue").run({ repo_slug = "explicit/repo" }, function() end)
			assert.is_nil(resolve)
			assert.equal("explicit/repo", opened)
		end)
	end)
end
