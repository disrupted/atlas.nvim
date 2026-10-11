describe("core.http", function()
	local original_vim, original_module, original_preload

	before_each(function()
		original_vim = vim
		original_module = package.loaded["atlas.core.http"]
		original_preload = package.preload["atlas.core.http"]
		package.loaded["atlas.core.http"] = nil
		package.preload["atlas.core.http"] = nil
	end)

	after_each(function()
		_G.vim = original_vim
		package.loaded["atlas.core.http"] = original_module
		package.preload["atlas.core.http"] = original_preload
	end)

	it("runs at most ten requests at once and completes the queue", function()
		local jobs, handles = {}, {}
		local completed = 0
		_G.vim = vim.tbl_extend("force", vim, {
			fn = {
				jobstart = function(_, opts)
					table.insert(jobs, opts)
					return #jobs
				end,
				chansend = function(_, data)
					return #data
				end,
				chanclose = function() end,
			},
		})
		local http = require("atlas.core.http")
		for i = 1, 12 do
			local fetch = i % 2 == 0 and http.curl_text_request or http.curl_request
			handles[i] = fetch("GET", "https://example.test/" .. i, {}, nil, function(_, err, status)
				assert.is_nil(err)
				assert.equal(200, status)
				completed = completed + 1
			end)
		end

		assert.equal(10, #jobs)
		assert.equal(-1, handles[11].job_id)
		for i = 1, 12 do
			assert.equal(i, handles[i].job_id)
			jobs[i].on_stdout(i, { "__ATLAS_HTTP_CODE:200" })
			jobs[i].on_exit(i, 0)
			assert.equal(math.min(12, i + 10), #jobs)
		end
		assert.equal(12, completed)
	end)

	it("keeps credentials and request bodies out of curl arguments", function()
		local args
		local job_opts
		local config_input
		_G.vim = vim.tbl_extend(
			"force",
			vim,
			{ fn = vim.tbl_extend("force", vim.fn, {}), json = vim.tbl_extend("force", vim.json, {}) }
		)
		vim.fn.jobstart = function(command, opts)
			args = command
			job_opts = opts
			return 23
		end
		vim.fn.chansend = function(job_id, input)
			assert.equal(23, job_id)
			config_input = input
			return #input
		end
		vim.fn.chanclose = function(job_id, stream)
			assert.equal(23, job_id)
			assert.equal("stdin", stream)
		end
		vim.json.decode = function()
			return { ok = true }
		end

		local result, status
		require("atlas.core.http").curl_request(
			"POST",
			"https://git.example/api",
			{ Authorization = "token secret" },
			'{"body":"private"}',
			function(value, err, response_status)
				assert.is_nil(err)
				result, status = value, response_status
			end
		)

		assert.same({ "curl", "--config", "-" }, args)
		assert.is_nil(table.concat(args, " "):find("secret", 1, true))
		assert.is_nil(table.concat(args, " "):find("private", 1, true))
		assert.is_truthy(config_input:find('header = "Authorization: token secret"', 1, true))
		assert.is_truthy(config_input:find('data-raw = "{\\"body\\":\\"private\\"}"', 1, true))

		job_opts.on_stdout(23, { '{"ok":true}__ATLAS_HTTP_CODE:200' })
		job_opts.on_exit(23, 0)
		assert.is_true(result.ok)
		assert.equal(200, status)
		assert.is_nil(result.__http_status)
	end)
end)
