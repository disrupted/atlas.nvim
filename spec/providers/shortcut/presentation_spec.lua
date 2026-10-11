local displays = require("atlas.issues.ui.components.issue_list.providers")
local mapper = require("atlas.issues.providers.shortcut.api.mapper")

describe("Shortcut issue list", function()
	local issue_type = mapper.to_issue_type("feature")
	local issue = {
		key = "123",
		title = "Story title",
		type = issue_type,
		icon = issue_type.icon,
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
		assert.equal("󰃀", row.icon)
		local spans = display.highlights({ _issue = issue }, { key = "icon" }, { text = row.icon, padded = row.icon })
		assert.equal("AtlasTextPositive", spans[1].hl_group)
	end)

	it("uses the mapped icon in child rows and the shared detail header", function()
		local child = displays.get("shortcut").values(issue, true, "plain")
		assert.matches(issue.icon.icon, child.name, 1, true)
		local lines, spans = require("atlas.issues.ui.detail.components.header").render(issue, 100)
		assert.matches(issue.icon.icon .. " feature 123", lines[1], 1, true)
		assert.equal(issue.icon.hl_group, spans[3].hl_group)
	end)

	it("uses the calling list's reload state for status text and highlights", function()
		local display = displays.get("shortcut", { reloading = { ["123"] = true }, spinner = "spinner" })
		assert.equal(" spinner ", display.values(issue, false, "plain").status)
		local spans = display.highlights({ _issue = issue }, { key = "status" }, { padded = " spinner " })
		assert.equal("AtlasTextMuted", spans[1].hl_group)
		assert.equal(" Started ", displays.get("shortcut").values(issue, false, "plain").status)
	end)
end)
