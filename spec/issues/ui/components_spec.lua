local comment_threads = require("atlas.issues.ui.components.comment_threads")
local issue_displays = require("atlas.issues.ui.components.issue_list.providers")

describe("issue components after provider merge", function()
	local original_strwidth

	before_each(function()
		original_strwidth = vim.api.nvim_strwidth
		vim.api.nvim_strwidth = vim.fn.strdisplaywidth
	end)

	after_each(function()
		vim.api.nvim_strwidth = original_strwidth
	end)

	it("renders display-name mentions while retaining Markdown link highlights", function()
		local comment = {
			id = "1",
			body = "@<user-id> [details](https://example.com)",
			body_display = "@Ada [details](https://example.com)",
		}
		local preview = comment_threads.render_comment(comment, 100)
		local text = table.concat(preview.lines, "\n")
		assert.is_truthy(text:find("@Ada details", 1, true))
		assert.is_nil(text:find("user-id", 1, true))
		local linked = false
		for _, highlight in ipairs(preview.highlights) do
			linked = linked or highlight.hl_group == "AtlasMarkdownLink"
		end
		assert.is_true(linked)
		assert.equals("@<user-id> [details](https://example.com)", comment.body)
	end)

	it("renders raw comments and hides deleted display text", function()
		local comment = { id = "1", body = "plain comment" }
		local text = table.concat(comment_threads.render_comment(comment, 100).lines, "\n")
		assert.is_truthy(text:find("plain comment", 1, true))
		comment.deleted = true
		comment.body_display = "display text"
		text = table.concat(comment_threads.render_comment(comment, 100).lines, "\n")
		assert.is_truthy(text:find("(deleted comment)", 1, true))
		assert.is_nil(text:find("display text", 1, true))
	end)

	it("uses per-list loading state for Azure work items", function()
		local issue = { key = "42", title = "Fix bug", status = "Active", status_id = "Active" }
		local loading = issue_displays.get("azure", { reloading = { ["42"] = true }, spinner = "loading" })
		local normal = issue_displays.get("azure")
		assert.equals(" loading ", loading.values(issue, false).status)
		assert.equals(" Active ", normal.values(issue, false).status)
		assert.same(
			{ { start_col = 0, end_col = 9, hl_group = "AtlasTextMuted" } },
			loading.highlights({ _issue = issue }, { key = "status" }, { padded = " loading " })
		)
	end)
end)
