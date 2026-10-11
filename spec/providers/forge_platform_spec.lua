local users = require("atlas.providers.forge.users")

for _, provider in ipairs({ "gitea", "forgejo" }) do
	describe(provider .. " platform capabilities", function()
		local service, calls, reply
		local repo = { id = "123", name = "repo", full_name = "acme/repo", owner = "acme", repo_name = "repo" }

		before_each(function()
			service = require("atlas.providers.forge.api").new(provider)
			service.base_url = function()
				return "https://forge.example/git"
			end
			calls = {}
			local cache = {}
			service.get_cache = function(key)
				return cache[key], cache[key] ~= nil
			end
			service.set_cache = function(key, value)
				cache[key] = value
			end
			service.request = function(method, endpoint, data, done)
				calls[#calls + 1] = { method = method, endpoint = endpoint, data = data }
				reply(method, endpoint, done)
				return { cancel = function() end }
			end
		end)

		it("normalizes and caches the current user at platform scope", function()
			reply = function(_, endpoint, done)
				assert.equal("/user", endpoint)
				done({ id = 7, login = "alice", full_name = "Alice" }, nil)
			end
			for _ = 1, 2 do
				service.users.fetch_user(function(user, err)
					assert.is_nil(err)
					assert.same({ id = "7", username = "alice", name = "Alice" }, user)
				end)
			end
			assert.equal(1, #calls)
			assert.same({ username = "ghost", name = "ghost" }, users.to_user({ login = "ghost", full_name = vim.NIL }))
			assert.is_nil(users.to_user(vim.NIL))
		end)

		it("fetches the unpaginated assignees endpoint once and filters names without losing users", function()
			reply = function(_, endpoint, done)
				assert.equal("/repos/acme/repo/assignees", endpoint)
				local raw = {}
				for index = 1, 50 do
					raw[index] = { id = index, login = "user" .. index, full_name = "User " .. index }
				end
				done(raw, nil)
			end
			service.users.get_assignable_users(repo.full_name, "USER 50", function(result, err)
				assert.is_nil(err)
				assert.same({ { id = "50", name = "User 50", username = "user50" } }, result)
			end)
			assert.equal(1, #calls)
		end)

		it("fetches repository details by full name and accepts a missing README using HTTP status", function()
			reply = function(_, endpoint, done)
				assert.equal("/repos/acme/repo", endpoint)
				done({
					id = 123,
					full_name = "acme/repo",
					name = "repo",
					owner = { login = "acme" },
					default_branch = "main",
					html_url = "https://forge.example/git/acme/repo",
					private = true,
					stars_count = 9,
				}, nil)
			end
			service.request_text = function(_, endpoint, done)
				assert.equal("/repos/acme/repo/raw/README.md?ref=main", endpoint)
				done(nil, "README was not found", 404)
			end
			service.repository.fetch_details(repo, function(result, err)
				assert.is_nil(err)
				assert.equal("acme/repo", result.full_name)
				assert.equal("repo", result.repo_name)
				assert.equal("acme", result.owner)
				assert.equal(9, result.stars)
				assert.is_true(result.is_private)
				assert.is_nil(result.readme)
			end)
		end)

		it("returns branch arrays, full commit hashes and the next page cursor", function()
			local sha = string.rep("a", 40)
			reply = function(_, endpoint, done)
				assert.equal("/repos/acme/repo/branches?limit=50&page=2", endpoint)
				local raw = {}
				for index = 1, 50 do
					raw[index] = {
						name = "branch" .. index,
						protected = true,
						commit = { id = sha, author = { name = "Alice" } },
					}
				end
				done(raw, nil)
			end
			service.repository.fetch_branches(repo, { cursor = "2" }, function(result, err, cursor)
				assert.is_nil(err)
				assert.equal(50, #result)
				assert.equal("3", cursor)
				assert.equal(sha, result[1].hash)
				assert.equal("Alice", result[1].author)
				assert.is_true(result[1].protected)
			end)
		end)

		it("searches tags across pages and exposes the tag URL and full commit hash", function()
			local sha = string.rep("b", 40)
			reply = function(_, endpoint, done)
				if endpoint == "/repos/acme/repo/tags?limit=50&page=1" then
					local raw = {}
					for index = 1, 50 do
						raw[index] = { name = "v" .. index, commit = { sha = sha } }
					end
					done(raw, nil)
				else
					assert.equal("/repos/acme/repo/tags?limit=50&page=2", endpoint)
					done({ { name = "release/51", commit = { sha = sha } } }, nil)
				end
			end
			service.repository.fetch_tags(repo, { search = "RELEASE" }, function(result, err, cursor)
				assert.is_nil(err)
				assert.is_nil(cursor)
				assert.equal(1, #result)
				assert.equal(sha, result[1].hash)
				assert.equal("https://forge.example/git/acme/repo/src/tag/release%2F51", result[1].url)
			end)
			assert.equal(2, #calls)
		end)

		it("deletes slash-containing branches using their encoded name", function()
			reply = function(method, endpoint, done)
				assert.equal("DELETE", method)
				assert.equal("/repos/acme/repo/branches/feature%2Ftest", endpoint)
				done(nil, nil, 204)
			end
			service.repository.delete_branch(repo, { name = "feature/test" }, function(ok, err)
				assert.is_true(ok)
				assert.is_nil(err)
			end)
		end)

		it("maps notifications to shared kinds and preserves instance paths", function()
			reply = function(_, endpoint, done)
				assert.matches("status%-types=unread&status%-types=pinned", endpoint)
				done({
					{
						id = 4,
						unread = true,
						subject = { type = "Pull", title = "Fix", state = "open", html_url = "/acme/repo/pulls/4" },
						repository = { full_name = "acme/repo" },
					},
					{
						id = 5,
						subject = {
							type = "Issue",
							title = "Bug",
							html_url = "https://forge.example/git/acme/repo/issues/5",
						},
						repository = { full_name = "acme/repo" },
					},
				}, nil)
			end
			service.notifications.fetch({}, function(result, err)
				assert.is_nil(err)
				assert.equal("pr", result[1].kind)
				assert.equal("issue", result[2].kind)
				assert.equal("https://forge.example/git/acme/repo/pulls/4", result[1].url)
				assert.is_nil(result[1].icon)
			end)
		end)
	end)
end

describe("forge repository pages", function()
	it("uses shared pages and omits unsupported build history", function()
		local pages = { overview = {}, issues = {}, pulls = {}, builds = {}, branches = {}, tags = {} }
		assert.same(
			{ pages.overview, pages.issues, pages.pulls, pages.branches, pages.tags },
			require("atlas.providers.forge.ui.repository").pages(pages)
		)
	end)
end)
