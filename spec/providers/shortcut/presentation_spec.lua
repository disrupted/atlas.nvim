local displays = require("atlas.issues.ui.components.issue_list.providers")

describe("Shortcut issue list", function()
	local issue = {
		key = "123",
		title = "Story title",
		type = { name = "feature" },
		status = "Started",
		status_id = "456",
		assignee = { id = "a", name = "Ada Owner" },
		reporter = { id = "b", name = "Ben Requester" },
		owner_ids = { "a", "b" },
		labels = { { name = "frontend" } },
		story_points = 3,
		comment_count = 2,
	}

	it("uses the shared user model while preserving multiple owners and compact metadata", function()
		local display = displays.get("shortcut")
		local row = display.values(issue, false, "compact")
		assert.matches("Ada Owner +1", row.assignee, 1, true)
		assert.matches("Ben Requester", row.reporter, 1, true)
		assert.matches("frontend", row._meta, 1, true)
		assert.matches("3 pts", row._meta, 1, true)
		assert.equal("#123 Story title", row.name)
		assert.equal(" Started ", row.status)
		assert.is_not.equal("", row.icon)
	end)

	it("uses the calling list's reload state for status text and highlights", function()
		local display = displays.get("shortcut", { reloading = { ["123"] = true }, spinner = "spinner" })
		assert.equal(" spinner ", display.values(issue, false, "plain").status)
		local spans = display.highlights({ _issue = issue }, { key = "status" }, { padded = " spinner " })
		assert.equal("AtlasTextMuted", spans[1].hl_group)
		assert.equal(" Started ", displays.get("shortcut").values(issue, false, "plain").status)
	end)
end)
