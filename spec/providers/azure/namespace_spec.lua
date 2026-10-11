local config = require("atlas.config")
local provider = require("atlas.providers.azure")

describe("Azure starred item namespace", function()
	local original_options
	local original_joinpath
	local original_starred
	local starred
	local issue = { key = "42" }
	local pull = { id = 7, repo_full_name = "Platform/api" }

	before_each(function()
		original_options = config.options
		original_joinpath = vim.fs.joinpath
		original_starred = package.loaded["atlas.core.starred"]
		config.options = { providers = { azure = {} } }
		vim.fs.joinpath = function(...)
			return table.concat({ ... }, "/")
		end
		package.loaded["atlas.core.starred"] = nil
		starred = require("atlas.core.starred")
	end)

	after_each(function()
		config.options = original_options
		vim.fs.joinpath = original_joinpath
		package.loaded["atlas.core.starred"] = original_starred
	end)

	it("isolates the same work item and pull request IDs in different organizations", function()
		config.options.providers.azure.base_url = "https://dev.azure.com/acme"
		local first_issue = starred.ref(issue, "azure")
		local first_pull = starred.ref(pull, "azure")
		assert.equal("azure:dev.azure.com/acme:issues/42", first_issue)
		assert.equal("azure:dev.azure.com/acme:pulls/Platform/api#7", first_pull)

		config.options.providers.azure.base_url = "https://dev.azure.com/other"
		assert.are_not.equal(first_issue, starred.ref(issue, "azure"))
		assert.are_not.equal(first_pull, starred.ref(pull, "azure"))
	end)

	it("normalizes host and organization case and trailing slashes", function()
		config.options.providers.azure.base_url = "https://dev.azure.com/acme"
		local first_issue = starred.ref(issue, "azure")
		local first_pull = starred.ref(pull, "azure")

		config.options.providers.azure.base_url = "https://DEV.AZURE.COM/ACME///"
		assert.equal("dev.azure.com/acme", provider.hostname())
		assert.equal(first_issue, starred.ref(issue, "azure"))
		assert.equal(first_pull, starred.ref(pull, "azure"))
	end)

	it("returns no namespace for missing or invalid configured URLs", function()
		assert.is_nil(provider.hostname())
		for _, value in ipairs({ "", "not a URL", "https://", "ftp://dev.azure.com/acme" }) do
			config.options.providers.azure.base_url = value
			assert.is_nil(provider.hostname())
		end
	end)
end)
