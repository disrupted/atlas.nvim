local mapper = require("atlas.issues.providers.linear.api.mapper")

describe("Linear issue mapping", function()
	it("maps dashboard identity, workflow, people and parent references", function()
		local issue = mapper.to_issue({
			id = "issue-uuid",
			identifier = "ENG-42",
			title = "Fix login",
			url = "https://linear.app/acme/issue/ENG-42/fix-login",
			state = { id = "state-uuid", name = "In Progress", type = "started", color = "#f2c94c" },
			priorityLabel = "High",
			assignee = { id = "user-1", name = "Ada", displayName = "ada" },
			creator = { id = "user-2", name = "Sam" },
			parent = { identifier = "ENG-1", title = "Authentication" },
			estimate = 3,
			dueDate = "2026-10-10",
			createdAt = "2026-10-01T00:00:00Z",
			updatedAt = "2026-10-02T00:00:00Z",
			completedAt = vim.NIL,
			canceledAt = "2026-10-03T00:00:00Z",
		})

		assert.equal("issue-uuid", issue.id)
		assert.equal("ENG-42", issue.key)
		assert.equal("Fix login", issue.title)
		assert.equal("In Progress", issue.status)
		assert.equal("state-uuid", issue.status_id)
		assert.equal("started", issue.status_type)
		assert.equal("#f2c94c", issue.status_color)
		assert.same({ icon = "", hl_group = "AtlasColor_f2c94c" }, issue.icon)
		assert.equal("High", issue.priority)
		assert.equal("ada", issue.assignee.username)
		assert.equal("Sam", issue.reporter.name)
		assert.same({ key = "ENG-1", title = "Authentication" }, issue.parent)
		assert.equal(3, issue.story_points)
		assert.equal("2026-10-10", issue.duedate)
		assert.equal("2026-10-01T00:00:00Z", issue.created_at)
		assert.equal("2026-10-02T00:00:00Z", issue.updated_at)
		assert.equal("2026-10-03T00:00:00Z", issue.closed_at)
	end)

	it("handles GraphQL nulls without creating users or parent references", function()
		local issue = mapper.to_issue({
			identifier = "ENG-42",
			title = "Minimal issue",
			state = vim.NIL,
			assignee = vim.NIL,
			creator = vim.NIL,
			parent = vim.NIL,
			team = vim.NIL,
			project = vim.NIL,
			cycle = vim.NIL,
			estimate = vim.NIL,
			dueDate = vim.NIL,
			completedAt = vim.NIL,
			canceledAt = vim.NIL,
		})

		assert.same({
			key = "ENG-42",
			title = "Minimal issue",
			icon = { icon = "", hl_group = "AtlasTextMuted" },
		}, issue)
		assert.same({}, mapper.to_issues_list(vim.NIL))
		assert.same({}, mapper.to_issues_list({ vim.NIL, {}, { identifier = vim.NIL } }))
	end)

	it("keeps status names when type and color are absent", function()
		local issue = mapper.to_issue({
			identifier = "ENG-42",
			state = { name = "Custom workflow", type = vim.NIL, color = vim.NIL },
		})

		assert.equal("Custom workflow", issue.status)
		assert.is_nil(issue.status_type)
		assert.is_nil(issue.status_color)
	end)

	it("maps team, project and named cycle context for dashboard rows", function()
		local issue = mapper.to_issue({
			identifier = "ENG-42",
			team = { key = "ENG", name = "Engineering" },
			project = { name = "Authentication" },
			cycle = { name = "October delivery", number = 24 },
		})

		assert.same({ key = "ENG", name = "Engineering" }, issue.team)
		assert.same({ name = "Authentication" }, issue.project)
		assert.same({ name = "October delivery", number = 24 }, issue.cycle)
	end)

	it("retains unnamed cycle numbers and team keys for display fallbacks", function()
		local issue = mapper.to_issue({
			identifier = "ENG-42",
			team = { key = "ENG", name = vim.NIL },
			project = { name = vim.NIL },
			cycle = { name = vim.NIL, number = 24 },
		})

		assert.same({ key = "ENG", name = "" }, issue.team)
		assert.is_nil(issue.project)
		assert.same({ number = 24 }, issue.cycle)

		local missing = mapper.to_issue({
			identifier = "ENG-42",
			team = {},
			project = { name = "" },
			cycle = { name = "", number = vim.NIL },
		})
		assert.is_nil(missing.team)
		assert.is_nil(missing.project)
		assert.is_nil(missing.cycle)
	end)

	it("maps supplemental details and ignores empty labels", function()
		local details = mapper.to_issue_details({
			title = "Fix login",
			description = "A **Markdown** description",
			assignee = { id = "user-1", name = "Ada" },
			labels = { nodes = { vim.NIL, { name = "Bug", color = "#ff0000" }, { name = "" } } },
		})

		assert.equal("Fix login", details.title)
		assert.equal("A **Markdown** description", details.description)
		assert.equal("Ada", details.assignees[1].name)
		assert.same({ { name = "Bug", color = "#ff0000" } }, details.labels)
		assert.same(
			{ description = "", assignees = {}, labels = {} },
			mapper.to_issue_details({
				title = vim.NIL,
				description = vim.NIL,
				assignee = vim.NIL,
				labels = vim.NIL,
			})
		)
		assert.is_nil(mapper.to_issue_details(vim.NIL))
	end)
end)
