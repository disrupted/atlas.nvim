local module_names = {
	"atlas.providers.azure.client",
	"atlas.providers.azure.repositories",
	"atlas.pulls.providers.azure.api.mapper",
	"atlas.pulls.providers.azure.api.reviews",
	"atlas.pulls.providers.azure.api.changes",
	"atlas.pulls.providers.azure.api.comments",
}

describe("Azure review refresh", function()
	local original = {}

	before_each(function()
		for _, name in ipairs(module_names) do
			original[name] = package.loaded[name]
			package.loaded[name] = nil
		end
	end)

	after_each(function()
		for _, name in ipairs(module_names) do
			package.loaded[name] = original[name]
		end
	end)

	it("refreshes reviewer votes and resolves mentions without changing comment source", function()
		local service = require("atlas.providers.azure.client")
		local requested = {}
		local author = { id = "author", displayName = "Author", uniqueName = "author@example.com" }
		local reviewer = { id = "reviewer", displayName = "Reviewer", uniqueName = "reviewer@example.com", vote = 10 }
		package.loaded["atlas.providers.azure.client"] = {
			url_encode = service.url_encode,
			build_query = service.build_query,
			get_cache = function()
				return nil, false
			end,
			set_cache = function() end,
			request = function(_, endpoint, _, done)
				requested[#requested + 1] = endpoint
				if endpoint:match("/reviewers$") then
					done({ value = { reviewer } }, nil)
				else
					assert.matches("/threads?$baseIteration=0&$iteration=2", endpoint, 1, true)
					done({
						value = {
							{
								id = 7,
								threadContext = { filePath = "/main.lua", rightFileEnd = { line = 12 } },
								comments = {
									{
										id = 1,
										parentCommentId = 0,
										commentType = "text",
										content = "Ask @<reviewer>",
										author = author,
									},
								},
							},
							{
								id = 8,
								comments = {
									{
										id = 1,
										parentCommentId = 0,
										commentType = "text",
										content = "Hello",
										author = reviewer,
									},
								},
							},
						},
					}, nil)
				end
			end,
		}
		package.loaded["atlas.pulls.providers.azure.api.changes"] = {
			fetch_iteration = function(_, commit, done)
				assert.equal("head", commit)
				done(2, nil)
			end,
		}
		local completed = false
		require("atlas.pulls.providers.azure.api.reviews").fetch({
			id = 1,
			repo_full_name = "Platform/api",
			repo = { owner = "Platform", repo_name = "api" },
			source = { commit_hash = "head" },
			link = { html = "https://example.com/pr/1" },
			author = { id = "author", name = "Author" },
			reviewers = { { id = "reviewer", name = "Reviewer", decision = "pending" } },
		}, { force_refresh = true }, function(data, err)
			completed = true
			assert.is_nil(err)
			assert.equal("approved", data.reviewers[1].decision)
			assert.is_false(data.review.pending)
			assert.equal(1, #data.comments)
			assert.equal("Ask @<reviewer>", data.comments[1].content_raw)
			assert.equal("Ask @Reviewer", data.comments[1].content_display)
			assert.equal("main.lua", data.comments[1].inline.path)
			assert.equal(12, data.comments[1].inline.to)
		end)
		assert.is_true(completed)
		assert.equal(2, #requested)
	end)

	it("loads inline thread hunks on both sides of renamed files without attaching context to replies", function()
		local service = require("atlas.providers.azure.client")
		local files = require("atlas.core.git.diff_parser").parse(table.concat({
			"diff --git a/old.lua b/main.lua",
			"rename from old.lua",
			"rename to main.lua",
			"--- a/old.lua",
			"+++ b/main.lua",
			"@@ -1,1 +1,1 @@",
			"-before",
			"+after",
			"@@ -10,2 +20,2 @@",
			" unchanged",
			"-old value",
			"+new value",
		}, "\n"))
		local author = { id = "author", displayName = "Author" }
		local function comment(id, parent)
			return { id = id, parentCommentId = parent or 0, commentType = "text", content = "Review", author = author }
		end
		local threads = {
			{
				id = 1,
				threadContext = { filePath = "/main.lua", rightFileEnd = { line = 21 } },
				comments = { comment(1), comment(2, 1) },
			},
			{
				id = 2,
				threadContext = { filePath = "/old.lua", leftFileEnd = { line = 11 } },
				comments = { comment(1) },
			},
			{
				id = 3,
				threadContext = { filePath = "/missing.lua", rightFileEnd = { line = 21 } },
				comments = { comment(1) },
			},
			{
				id = 4,
				threadContext = { filePath = "/main.lua", rightFileEnd = { line = 22 } },
				comments = { comment(1) },
			},
			{
				id = 5,
				threadContext = { filePath = "/main.lua" },
				comments = { comment(1) },
			},
		}
		package.loaded["atlas.providers.azure.client"] = {
			url_encode = service.url_encode,
			build_query = service.build_query,
			get_cache = function()
				return nil, false
			end,
			set_cache = function() end,
			request = function(_, endpoint, _, done)
				if endpoint:match("/reviewers$") then
					done({ value = {} }, nil)
				else
					assert.matches("/threads?$baseIteration=0&$iteration=2", endpoint, 1, true)
					done({ value = threads }, nil)
				end
			end,
		}
		package.loaded["atlas.pulls.providers.azure.api.changes"] = {
			fetch_iteration = function(_, commit, done)
				assert.equal("head", commit)
				done(2, nil)
			end,
			fetch_file_diffs = function(_, iteration, _, done)
				assert.equal(2, iteration)
				done(files, nil)
			end,
		}
		local completed = false
		require("atlas.pulls.providers.azure.api.reviews").fetch_threads({
			id = 1,
			repo_full_name = "Platform/api",
			repo = { owner = "Platform", repo_name = "api" },
			source = { commit_hash = "head" },
			link = { html = "https://example.com/pr/1" },
			author = { id = "author", name = "Author" },
		}, { force_refresh = true }, function(data, err)
			completed = true
			assert.is_nil(err)
			assert.equal(6, #data.comments)
			assert.equal(files[1].hunks[2], data.comments[1].hunk)
			assert.is_nil(data.comments[2].hunk)
			assert.equal(files[1].hunks[2], data.comments[3].hunk)
			assert.is_nil(data.comments[4].hunk)
			assert.is_nil(data.comments[5].hunk)
			assert.is_nil(data.comments[6].hunk)
		end)
		assert.is_true(completed)
	end)
end)
