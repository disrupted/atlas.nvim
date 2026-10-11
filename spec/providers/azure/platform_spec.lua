describe("Azure repository and pipeline contracts", function()
	local saved, requests, cache, repositories, pipelines
	local modules = {
		"atlas.providers.azure.client",
		"atlas.providers.azure.repositories",
		"atlas.pulls.providers.azure.api.pipelines",
		"atlas.pulls.pipelines.azure",
		"atlas.pulls.pipelines.azure.actions",
	}
	local repo = { id = "Project/Repo", full_name = "Project/Repo", owner = "Project", repo_name = "Repo" }
	local pr = {
		id = 42,
		repo = repo,
		repo_full_name = "Project/Repo",
		repository_id = "repo-id",
		source = { branch = "feature", commit_hash = "source-sha" },
		merge_commit_hash = "merge-sha",
	}
	local context = { provider = "azure", repo_full_name = "Project/Repo", target = pr }

	before_each(function()
		saved, requests, cache = {}, {}, {}
		for _, name in ipairs(modules) do
			saved[name] = package.loaded[name]
			package.loaded[name] = nil
		end
		package.loaded[modules[1]] = {
			url_encode = function(value)
				return value
			end,
			build_query = function(values)
				local parts = {}
				for key, value in pairs(values) do
					parts[#parts + 1] = key .. "=" .. tostring(value)
				end
				table.sort(parts)
				return "?" .. table.concat(parts, "&")
			end,
			get_cache = function(key)
				return cache[key], cache[key] ~= nil
			end,
			set_cache = function(key, value)
				cache[key] = value
			end,
			clear_cache = function()
				cache = {}
			end,
			request = function(method, endpoint, payload, done)
				local request = { method = method, endpoint = endpoint, payload = payload, done = done }
				requests[#requests + 1] = request
				return {
					cancel = function()
						request.cancelled = true
					end,
				}
			end,
		}
		repositories = require("atlas.providers.azure.repositories")
		pipelines = require("atlas.pulls.pipelines.azure")
	end)

	after_each(function()
		for _, name in ipairs(modules) do
			package.loaded[name] = saved[name]
		end
	end)

	it("returns branch arrays with the existing commit metadata and refreshes on each call", function()
		local branches
		repositories.fetch_branches(repo, { search = "FEAT" }, function(value, err, cursor)
			assert.is_nil(err)
			assert.is_nil(cursor)
			branches = value
		end)
		assert.equal("/Project/_apis/git/repositories/Repo/stats/branches", requests[1].endpoint)
		local raw = {
			name = "feature",
			commit = { commitId = "sha", comment = "Fix", author = { name = "Ada" }, committer = { date = "date" } },
		}
		requests[1].done({ value = { raw, vim.tbl_extend("force", raw, { name = "main" }) } })
		assert.same({ { name = "feature", hash = "sha", message = "Fix", author = "Ada", date = "date" } }, branches)
		repositories.fetch_branches(repo, {}, function() end)
		assert.equal(2, #requests)
	end)

	it("keeps fetching all tag pages before applying shared UI search", function()
		local tags
		repositories.fetch_tags(repo, { search = "v2" }, function(value, err, cursor)
			assert.is_nil(err)
			assert.is_nil(cursor)
			tags = value
		end)
		requests[1].done({ value = { { name = "refs/tags/v1", objectId = "one" } } }, nil, {
			["x-ms-continuationtoken"] = "next",
		})
		assert.is_nil(tags)
		assert.matches("continuationToken=next", requests[2].endpoint, 1, true)
		requests[2].done(
			{ value = { { name = "refs/tags/v2", objectId = "tag", peeledObjectId = "commit" } } },
			nil,
			{}
		)
		assert.same({ { name = "v2", hash = "commit" } }, tags)
	end)

	it("uses the common repository model and still tolerates missing README files", function()
		local details
		repositories.fetch_details(repo, function(value, err)
			assert.is_nil(err)
			details = value
		end)
		requests[1].done({
			name = "Repo",
			project = { name = "Project", visibility = "private" },
			webUrl = "https://example/Repo",
			defaultBranch = "refs/heads/main",
			size = 120,
		})
		assert.is_nil(details)
		requests[2].done(nil, "Not found")
		assert.equal("Project/Repo", details.full_name)
		assert.equal("Project", details.owner)
		assert.equal("Repo", details.repo_name)
		assert.equal("main", details.default_branch)
		assert.is_true(details.is_private)
		assert.is_nil(details.readme)
	end)

	local function build(id, source)
		return {
			id = id,
			definition = { name = "CI" },
			buildNumber = "1",
			status = "completed",
			result = "succeeded",
			sourceVersion = source,
			queueTime = "2026-01-01",
			_links = { web = { href = "https://example/build/" .. id } },
		}
	end

	local function finish_build_lists()
		for index = 1, 2 do
			local request = requests[index]
			local is_pr = request.endpoint:find("reasonFilter=pullRequest", 1, true)
			request.done({ value = is_pr and { build(5, "merge-sha"), build(9, "old-sha") } or {} }, nil, {})
		end
	end

	local function timeline()
		return {
			records = {
				{
					id = "stage",
					type = "Stage",
					name = "Build",
					identifier = "Build",
					state = "completed",
					result = "succeeded",
					order = 1,
				},
				{
					id = "job",
					type = "Job",
					parentId = "stage",
					name = "Test",
					state = "completed",
					result = "succeeded",
					order = 1,
				},
				{ id = "task", type = "Task", parentId = "job", log = { id = 7 }, order = 1 },
			},
		}
	end

	it("hydrates PR timelines for the new explorer and returns structured job logs", function()
		local result
		pipelines.fetch(context, {}, function(value, err)
			assert.is_nil(err)
			result = value
		end)
		finish_build_lists()
		assert.is_nil(result)
		assert.equal("/Project/_apis/build/builds/5/timeline", requests[3].endpoint)
		requests[3].done(timeline())
		assert.equal(1, #result)
		assert.equal("Build", result[1].stages[1].name)
		local job = result[1].stages[1].jobs[1]
		assert.same({ 7 }, job.log_ids)
		local log
		pipelines.fetch_job_log(context, result[1], job, function(value, err)
			assert.is_nil(err)
			log = value
		end)
		assert.equal("/Project/_apis/build/builds/5/logs/7", requests[4].endpoint)
		requests[4].done({ value = { "first", "second" } })
		assert.same({ raw = "first\nsecond" }, log)
	end)

	it("propagates timeline errors and cancellation through the new fetch contract", function()
		local result, err
		pipelines.fetch(context, {}, function(value, message)
			result, err = value, message
		end)
		finish_build_lists()
		requests[3].done(nil, "Forbidden")
		assert.is_nil(result)
		assert.equal("Forbidden", err)

		local called = false
		local handle = pipelines.fetch(context, { force_refresh = true }, function()
			called = true
		end)
		handle.cancel()
		assert.is_true(requests[4].cancelled)
		assert.is_true(requests[5].cancelled)
		requests[4].done({ value = {} }, nil, {})
		requests[5].done({ value = {} }, nil, {})
		assert.is_false(called)
	end)

	it("refreshes only the selected build for the shared explorer", function()
		local result
		pipelines.fetch(context, { pipeline = { id = "12" }, force_refresh = true }, function(value, err)
			assert.is_nil(err)
			result = value
		end)
		assert.equal("/Project/_apis/build/builds/12", requests[1].endpoint)
		requests[1].done(build(12, "merge-sha"))
		assert.equal("/Project/_apis/build/builds/12/timeline", requests[2].endpoint)
		requests[2].done(timeline())
		assert.equal(1, #result)
		assert.equal("12", result[1].id)
		assert.equal("SUCCESSFUL", result[1].state)
		assert.equal("job", result[1].stages[1].jobs[1].id)
	end)

	it("refreshes job state using the current timeline", function()
		local job
		pipelines.fetch_job(context, { id = "5" }, { id = "job" }, function(value, err)
			assert.is_nil(err)
			job = value
		end)
		requests[1].done(timeline())
		assert.equal("SUCCESSFUL", job.state)
		assert.same({ 7 }, job.log_ids)
	end)

	it("uses the shared action context and reports failures in the error argument", function()
		local result, err
		local handle = pipelines.actions[1].run({ context = context, pipeline = { id = "5" } }, function(value, message)
			result, err = value, message
		end)
		assert.is_function(handle.cancel)
		assert.equal("PATCH", requests[1].method)
		assert.equal("/Project/_apis/build/builds/5", requests[1].endpoint)
		assert.same({ status = "cancelling" }, requests[1].payload)
		requests[1].done(nil, "Forbidden")
		assert.is_nil(result)
		assert.equal("Forbidden", err)
	end)

	it("preserves Azure stage retry and stop requests through the shared actions", function()
		local ctx = { context = context, pipeline = { id = "5" }, stage = { ref_name = "Build" } }
		for index, action in ipairs({ "retry", "cancel" }) do
			local finished = false
			pipelines.actions[index + 1].run(ctx, function(value, err)
				assert.is_nil(value)
				assert.is_nil(err)
				finished = true
			end)
			assert.equal("/Project/_apis/build/builds/5/stages/Build", requests[index].endpoint)
			assert.same({ state = action, forceRetryAllJobs = action == "retry" or nil }, requests[index].payload)
			requests[index].done({})
			assert.is_true(finished)
		end
	end)

	it("reuses only the original repository pages", function()
		local pages = { overview = {}, branches = {}, tags = {}, builds = {}, pulls = {} }
		local ui = require("atlas.providers.azure.ui.repository")
		assert.same({ pages.overview, pages.branches, pages.tags }, ui.pages(pages))
	end)

	it("keeps unsupported pipeline targets and capabilities explicit", function()
		local err
		assert.is_nil(pipelines.fetch({ target = "main" }, {}, function(_, message)
			err = message
		end))
		assert.equal("Azure pipelines require a pull request", err)
		assert.equal(0, #requests)
		assert.is_nil(pipelines.fetch_history)
		assert.is_nil(pipelines.fetch_config)
	end)
end)
