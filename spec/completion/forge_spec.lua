local factory = require("atlas.providers.forge.completion")

for _, provider in ipairs({ "gitea", "forgejo" }) do
	describe(provider .. " completion", function()
		local service, source, calls, responses, failure, pending, cancelled
		local issue = "/repos/acme/repo/issues/42"
		local reviews = "/repos/acme/repo/pulls/42/reviews"

		before_each(function()
			service = require("atlas.providers.forge.api").new(provider)
			local cache = {}
			service.get_memory_cache = function(key)
				return cache[key], cache[key] ~= nil
			end
			service.set_memory_cache = function(key, value)
				cache[key] = value
			end
			calls, pending, cancelled = {}, nil, 0
			failure = nil
			responses = {
				[issue] = {
					user = { id = 1, login = "alice", full_name = "Alice" },
					assignees = { { login = "bob" } },
				},
				[issue .. "/comments"] = { { user = { login = "alice" } }, { user = { login = "carol" } } },
				[reviews] = { { user = { login = "dave" } }, { user = { login = "bob" } } },
			}
			responses["/repos/acme/repo/pulls/42"] = vim.tbl_extend("force", {}, responses[issue], {
				requested_reviewers = { { login = "erin" } },
			})
			service.request = function(_, endpoint, _, done)
				calls[#calls + 1] = endpoint
				if pending then
					pending[#pending + 1] = function()
						done(responses[endpoint], failure)
					end
				else
					done(responses[endpoint], failure)
				end
				return {
					cancel = function()
						cancelled = cancelled + 1
					end,
				}
			end
			service.fetch_all = function(endpoint, _, _, done)
				return service.request("GET", endpoint, nil, done)
			end
			source = factory.new(service).users
		end)

		local function complete(context, query)
			local result
			source.complete(context, query or "", function(items, err)
				assert.is_nil(err)
				result = items
			end)
			return result
		end

		it("uses canonical issue refs and deduplicates authors, assignees and commenters", function()
			assert.same({ "@" }, source.triggers)
			local items = complete({ provider = provider, issue = { key = "acme/repo#42" } })
			assert.same(
				{ "@alice", "@bob", "@carol" },
				vim.tbl_map(function(item)
					return item.insert_text
				end, items)
			)
			assert.same(
				{ label = "@alice", insert_text = "@alice", filter_text = "alice Alice", detail = "Alice" },
				items[1]
			)
			assert.equal(2, #calls)
		end)

		it("includes pull reviewers and keeps issue and pull caches separate", function()
			local issue_context = { provider = provider, repository = "acme/repo", issue = { key = "acme/repo#42" } }
			local pull_context = { provider = provider, pr = { repo_full_name = "acme/repo", id = 42 } }
			assert.equal(3, #complete(issue_context))
			assert.same(
				{ "@alice", "@bob", "@erin", "@carol", "@dave" },
				vim.tbl_map(function(item)
					return item.insert_text
				end, complete(pull_context))
			)
			assert.equal(5, #calls)
			assert.equal("@dave", complete(pull_context, "dav")[5].insert_text)
			assert.equal(5, #calls)
		end)

		it("fetches assignable users during creation and caches empty results across typed queries", function()
			responses["/repos/acme/new/assignees"] = {}
			local context = { provider = provider, repository = "acme/new" }
			assert.same({}, complete(context))
			assert.same({}, complete(context, "alice"))
			assert.same({ "/repos/acme/new/assignees" }, calls)
		end)

		it("does not cache failed requests", function()
			failure = "Request failed"
			for _ = 1, 2 do
				source.complete({ provider = provider, issue = { key = "acme/repo#42" } }, "", function(items, err)
					assert.is_nil(items)
					assert.equal(failure, err)
				end)
			end
			assert.equal(4, #calls)
		end)

		it("cancels all participant requests and ignores late completion", function()
			pending = {}
			local completed = false
			local handle = source.complete(
				{ provider = provider, pr = { repo_full_name = "acme/repo", id = 42 } },
				"",
				function()
					completed = true
				end
			)
			handle.cancel()
			assert.equal(3, cancelled)
			for _, done in ipairs(pending) do
				done()
			end
			assert.is_false(completed)
		end)

		it("requires a repository without issuing a request", function()
			source.complete({ provider = provider }, "", function(items, err)
				assert.is_nil(items)
				assert.matches("requires a repository", err)
			end)
			assert.same({}, calls)
		end)
	end)
end
