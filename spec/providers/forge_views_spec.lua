local config = require("atlas.config")
local git = require("atlas.core.git")

for _, id in ipairs({ "gitea", "forgejo" }) do
	for _, domain in ipairs({ "pulls", "issues" }) do
		describe(id .. " " .. domain .. " current repository views", function()
			local original_config, original_git, original_getcwd, api, original_list, original_search
			local provider, resolve, received, page, calls, cancelled
			before_each(function()
				original_config, original_git, original_getcwd =
					config.domain_options, git.local_repository, vim.fn.getcwd
				vim.fn.getcwd = function()
					return "/workspace"
				end
				local configured = {
					{
						name = "Current",
						current_repo = true,
						repo = "configured/repo",
						extra_params = { sort = "updated" },
					},
				}
				config.domain_options = function()
					return { views = configured }
				end
				calls, cancelled = 0, 0
				git.local_repository = function(cwd, done)
					assert.equal(vim.fn.getcwd(), cwd)
					calls = calls + 1
					resolve = done
					return {
						cancel = function()
							cancelled = cancelled + 1
						end,
					}
				end
				provider = require("atlas." .. domain .. ".providers.forge." .. id)
				api =
					require("atlas." .. domain .. ".providers.forge." .. id .. ".api")[domain == "pulls" and "pullrequests" or "issues"]
				original_list, original_search = api.list, api.search_global
				received, page = nil, nil
				local function list(view, statuses_or_opts, opts_or_done, done)
					received = {
						view = view,
						statuses = domain == "pulls" and statuses_or_opts or nil,
						opts = domain == "pulls" and opts_or_done or statuses_or_opts,
					}
					local callback = done or opts_or_done
					callback({ items = {}, next_cursor = { page = "3" } }, nil)
				end
				api.list, api.search_global = list, list
			end)
			after_each(function()
				config.domain_options, git.local_repository, vim.fn.getcwd =
					original_config, original_git, original_getcwd
				api.list, api.search_global = original_list, original_search
			end)
			local function fetch(view)
				local method = provider.capabilities.core[domain == "pulls" and "fetch_pullrequests" or "fetch_issues"]
				return method(view, { cursor = { page = "2" }, pagelen = 7, force_refresh = true }, function(value)
					page = value
				end)
			end
			it("resolves at fetch time and reports the resolved query without changing configuration", function()
				local views = provider.views()
				assert.equal(0, calls)
				assert.equal("configured/repo", views[1].repo)
				fetch(views[1])
				assert.is_nil(received)
				resolve({ provider = id, repo_full_name = "local/repo" })
				assert.equal(1, calls)
				assert.equal("local/repo", received.view.repo)
				assert.equal("configured/repo", views[1].repo)
				assert.equal("configured/repo", provider.views()[1].repo)
				assert.same({ page = "2" }, received.opts.cursor)
				assert.equal(7, received.opts.pagelen)
				assert.is_true(received.opts.force_refresh)
				assert.same({ page = "3" }, page.next_cursor)
				assert.equal(require("atlas." .. domain .. ".providers.forge.query").resolve(received.view), page.query)
				if domain == "pulls" then
					assert.same({ "OPEN" }, received.statuses)
				end
			end)
			it("keeps the configured repository when the current remote belongs to another provider", function()
				fetch(provider.views()[1])
				resolve({ provider = "github", repo_full_name = "other/repo" })
				assert.equal("configured/repo", received.view.repo)
			end)
			it("cancels repository resolution before it can start a request", function()
				local handle = fetch(provider.views()[1])
				handle.cancel()
				resolve({ provider = id, repo_full_name = "local/repo" })
				assert.equal(1, cancelled)
				assert.is_nil(received)
				assert.is_nil(page)
			end)
			if domain == "pulls" then
				it("keeps the displayed query and requested states aligned", function()
					local view = { name = "Search", search = "is:merged needle" }
					fetch(view)
					assert.equal(0, calls)
					assert.equal("needle", received.view.search)
					assert.same({ "MERGED" }, received.statuses)
					assert.equal("type:pulls is:merged search:needle", page.query)
					view._states = { "declined" }
					fetch(view)
					assert.same({ "DECLINED" }, received.statuses)
					assert.equal("type:pulls is:declined search:needle", page.query)
				end)
			end
		end)
	end
end
