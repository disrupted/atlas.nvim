local modules = {
	"atlas.providers.azure.client",
	"atlas.providers.azure.users",
	"atlas.providers.azure.completion",
	"atlas.issues.providers.azure.api.issues",
	"atlas.issues.providers.azure.api.comments",
}

describe("Azure mention completion", function()
	local saved, source, calls, failure, cache, deferred, cancelled
	local pr = { provider = "azure", pr = { id = 7, repo_full_name = "Team Project/api" } }
	local author = { id = "author", displayName = "Avery" }
	local reviewer = { id = "reviewer", displayName = "Robin" }
	local commenter = { id = "commenter", displayName = "Chris" }

	before_each(function()
		saved, calls, cache, deferred, cancelled = {}, {}, {}, false, 0
		failure = nil
		for _, name in ipairs(modules) do
			saved[name] = package.loaded[name]
			package.loaded[name] = nil
		end
		package.loaded[modules[1]] = {
			url_encode = require("atlas.core.utils").url_encode,
			get_cache = function(key)
				return cache[key], cache[key] ~= nil
			end,
			set_cache = function(key, value)
				cache[key] = value
			end,
			request = function(method, endpoint, _, done)
				assert.equal("GET", method)
				calls[#calls + 1] = endpoint
				if not deferred then
					if endpoint:match("/threads$") then
						done({ value = { { comments = { { author = commenter }, { author = author } } } } }, failure)
					else
						done({ createdBy = author, reviewers = { reviewer } }, failure)
					end
				end
				return {
					cancel = function()
						cancelled = cancelled + 1
					end,
				}
			end,
		}
		source = require("atlas.providers.azure.completion").users
	end)

	after_each(function()
		for _, name in ipairs(modules) do
			package.loaded[name] = saved[name]
		end
	end)

	it("preserves Azure mention syntax and includes all thread authors without duplicates", function()
		source.complete(pr, "", function(items, err)
			assert.is_nil(err)
			assert.same(
				{ "@<author>", "@<commenter>", "@<reviewer>" },
				vim.tbl_map(function(item)
					return item.insert_text
				end, items)
			)
		end)
		assert.equal(2, #calls)
		for _, endpoint in ipairs(calls) do
			assert.truthy(endpoint:find("/Team%20Project/_apis/git/repositories/api/pullrequests/7", 1, true))
		end
		source.complete(pr, "RO", function(items, err)
			assert.is_nil(err)
			assert.equal(1, #items)
			assert.equal("@Robin", items[1].label)
		end)
		assert.equal(2, #calls)
	end)

	it("isolates cached candidates by repository and retries failed requests", function()
		failure = "Unavailable"
		for _ = 1, 2 do
			source.complete(pr, "", function(items, err)
				assert.is_nil(items)
				assert.equal(failure, err)
			end)
		end
		assert.equal(4, #calls)
		failure = nil
		source.complete(pr, "", function() end)
		source.complete({ pr = { id = 7, repo_full_name = "Team Project/other" } }, "", function() end)
		assert.equal(8, #calls)
	end)

	it("cancels both in-flight requests", function()
		deferred = true
		local handle = source.complete(pr, "", function()
			error("cancelled requests must not complete")
		end)
		handle.cancel()
		assert.equal(2, cancelled)
	end)

	it("collects work-item authors using normalized users and paginated conversation API", function()
		package.loaded[modules[4]] = {
			fetch_by_refs = function(refs, _, done)
				assert.equal("42", refs[1].key)
				done({ { key = "42", project = "Team", reporter = { id = "author", name = "Avery" } } }, nil)
			end,
		}
		package.loaded[modules[5]] = {
			fetch_conversation = function(issue, _, done)
				assert.equal("Team", issue.project)
				done({ { entity = { author = { id = "commenter", name = "Chris" } } } }, nil)
			end,
		}
		source.complete({ provider = "azure", issue = { key = "42" } }, "ch", function(items, err)
			assert.is_nil(err)
			assert.equal(1, #items)
			assert.equal("@<commenter>", items[1].insert_text)
		end)
	end)

	it("does not invent candidates before a PR or issue exists", function()
		source.complete({ provider = "azure", project = "Team" }, "", function(items, err)
			assert.is_nil(err)
			assert.same({}, items)
		end)
		assert.equal(0, #calls)
	end)

	it("renders known names without changing unknown IDs", function()
		local mentions = require("atlas.providers.azure.mentions")
		local names = {}
		mentions.add(names, { id = "author", name = "Avery" })
		assert.equal("@Avery and @<unknown>", mentions.resolve("@<author> and @<unknown>", names))
	end)
end)
