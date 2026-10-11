for _, provider in ipairs({ "gitea", "forgejo" }) do
	describe(provider .. " pipeline backend", function()
		local saved, service, backend, calls, response, request_error
		local function owned(module)
			return module:match("^atlas%.pulls%.providers%.forge%.")
				or module:match("^atlas%.pulls%.pipelines%.forge%.")
				or module == "atlas.providers.forge." .. provider .. ".api"
		end

		before_each(function()
			saved, calls = {}, {}
			for module, value in pairs(package.loaded) do
				if owned(module) then
					saved[module] = value
					package.loaded[module] = nil
				end
			end
			response, request_error = {}, nil
			local client = require("atlas.providers.forge.api.client").new(provider)
			service = {
				id = provider,
				name = provider,
				url_encode = client.url_encode,
				query = client.query,
				base_url = function()
					return "https://git.example"
				end,
				absolute_url = function(value)
					return value
				end,
				request = function(method, endpoint, _, done)
					table.insert(calls, method .. " " .. endpoint)
					done(response[endpoint] or {}, request_error)
					return { cancel = function() end }
				end,
				request_text = function(_, _, done)
					done("build log\n", nil, 200)
					return { cancel = function() end }
				end,
			}
			package.loaded["atlas.providers.forge." .. provider .. ".api"] = service
			backend = require("atlas.pulls.pipelines.forge." .. provider)
		end)

		after_each(function()
			for module in pairs(package.loaded) do
				if owned(module) then
					package.loaded[module] = nil
				end
			end
			for module, value in pairs(saved) do
				package.loaded[module] = value
			end
		end)

		local function context(target)
			return { provider = provider, repo_full_name = "owner/repo", target = target }
		end

		local function pipeline()
			return {
				id = "42",
				name = "Build",
				state = "FAILED",
				url = "https://git.example/owner/repo/actions/runs/42",
				stages = {},
			}
		end

		it("loads branch statuses through the shared context and retains external build links", function()
			response["/repos/owner/repo/commits/feature%2Ftest/status"] = {
				statuses = {
					{ id = 7, context = "External", status = "success", target_url = "https://ci.example/build/7" },
				},
			}
			local result
			backend.fetch(context("feature/test"), nil, function(items, err)
				assert.is_nil(err)
				result = items
			end)
			assert.equal("SUCCESSFUL", result[1].state)
			assert.equal("https://ci.example/build/7", result[1].url)
			backend.fetch(context("feature/test"), { pipeline = result[1] }, function(items, err)
				assert.is_nil(err)
				assert.same(result, items)
			end)
			assert.same({ "GET /repos/owner/repo/commits/feature%2Ftest/status" }, calls)
		end)

		it("loads native jobs when the shared view selects a pipeline", function()
			if provider == "gitea" then
				response["/repos/owner/repo/actions/runs/42"] =
					{ id = 42, status = "completed", conclusion = "success" }
				response["/repos/owner/repo/actions/runs/42/jobs?limit=50&page=1"] = {
					total_count = 1,
					jobs = { { id = 91, name = "Test", status = "completed", conclusion = "success" } },
				}
			else
				response["/repos/owner/repo/actions/runs?limit=1&run_number=42"] = {
					workflow_runs = { { id = 900, index_in_repo = 42, status = "success" } },
				}
				response["/repos/owner/repo/actions/runs/900/jobs"] = { { id = 91, name = "Test", status = "success" } }
			end
			local result
			backend.fetch(context("main"), { pipeline = pipeline() }, function(items, err)
				assert.is_nil(err)
				result = items
			end)
			assert.equal(1, #result)
			assert.equal("SUCCESSFUL", result[1].state)
			assert.equal("91", result[1].stages[1].jobs[1].id)
			assert.equal(2, #calls)
			response["/repos/owner/repo/commits/main/status"] = {
				statuses = {
					{ id = 7, context = "Build / Test", status = "success", target_url = pipeline().url .. "/jobs/0" },
				},
			}
			backend.fetch(context("main"), nil, function(items, err)
				assert.is_nil(err)
				assert.equal("91", items[1].stages[1].jobs[1].id)
			end)
			assert.equal(5, #calls)
		end)

		it("returns logs in the shared log model with HTTP status", function()
			backend.fetch_job_log(context("main"), pipeline(), { id = "91" }, function(log, err, status)
				assert.is_nil(err)
				assert.same({ raw = "build log\n" }, log)
				assert.equal(200, status)
				local lines = require("atlas.pulls.pipelines.parser").parse(log)
				assert.equal("build log", lines[1].text)
			end)
		end)

		it("keeps status links when Actions details are inaccessible and reports explicit reload errors", function()
			service.request = function(_, endpoint, _, done)
				if endpoint == "/repos/owner/repo/commits/main/status" then
					done({
						statuses = {
							{
								id = 1,
								context = "Native",
								status = "success",
								target_url = pipeline().url .. "/jobs/0",
							},
							{
								id = 2,
								context = "External",
								status = "success",
								target_url = "https://ci.example/build/2",
							},
						},
					}, nil)
				else
					done(nil, "denied")
				end
				return { cancel = function() end }
			end
			local result
			backend.fetch(context("main"), nil, function(items, err)
				assert.is_nil(err)
				result = items
			end)
			assert.equal(2, #result)
			assert.equal(pipeline().url, result[1].url)
			assert.same({}, result[1].stages)
			assert.equal("https://ci.example/build/2", result[2].url)
			local called = false
			backend.fetch(context("main"), { pipeline = result[1] }, function(items, err)
				called = true
				assert.is_nil(items)
				assert.equal("denied", err)
			end)
			assert.is_true(called)
		end)

		it("reports action errors through the shared callback and retains cancellation", function()
			request_error = "denied"
			local selected = pipeline()
			selected.state = "INPROGRESS"
			local action = provider == "gitea" and backend.actions[2] or backend.actions[1]
			local called = false
			local handle = action.run({ context = context("main"), pipeline = selected }, function(result, err)
				called = true
				assert.is_nil(result)
				assert.equal("denied", err)
			end)
			assert.is_true(called)
			assert.is_function(handle.cancel)
		end)

		it("treats malformed Actions links as external statuses", function()
			local api = require("atlas.pulls.providers.forge." .. provider .. ".api.pipelines")
			local items = api.map(
				{ { id = 1, target_url = "https://git.example/owner/repo/actions/runs/invalid" } },
				"sha",
				"owner/repo"
			)
			assert.equal("status:1", items[1].id)
		end)
	end)
end
