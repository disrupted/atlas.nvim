local api_name = "atlas.issues.providers.linear.api.metadata"
local client_name = "atlas.providers.linear.client"

describe("Linear issue metadata", function()
	local previous_api, previous_client
	local api, calls

	local function page(nodes, cursor)
		return { nodes = nodes, pageInfo = { hasNextPage = cursor ~= nil, endCursor = cursor } }
	end

	before_each(function()
		previous_api = package.loaded[api_name]
		previous_client = package.loaded[client_name]
		calls = {}
		package.loaded[client_name] = {
			graphql = function(_, variables, done)
				table.insert(calls, { variables = vim.deepcopy(variables), done = done })
			end,
		}
		package.loaded[api_name] = nil
		api = require(api_name)
	end)

	after_each(function()
		package.loaded[api_name] = previous_api
		package.loaded[client_name] = previous_client
	end)

	it("fetches all state pages and sorts them in workflow order", function()
		local result
		api.list_states("team-id", function(items)
			result = items
		end)
		assert.equal("team-id", calls[1].variables.id)
		calls[1].done({ team = { items = page({ { id = "done", type = "completed", position = 0 } }, "next") } }, nil)
		assert.equal("next", calls[2].variables.after)
		calls[2].done({
			team = {
				items = page({
					{ id = "todo-later", type = "unstarted", position = 2 },
					{ id = "todo", type = "unstarted", position = 1 },
				}),
			},
		}, nil)
		assert.equal("todo", result[1].id)
		assert.equal("todo-later", result[2].id)
		assert.equal("done", result[3].id)
	end)
end)
