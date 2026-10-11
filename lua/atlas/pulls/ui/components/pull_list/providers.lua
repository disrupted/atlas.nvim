local icons = require("atlas.ui.shared.icons")
local presentation = require("atlas.pulls.ui.presentation")

local M = {}

local function columns(conversation, before_author, after_author, show_updated)
	local function build(title_key, compact)
		local result = {}
		if compact then
			table.insert(result, {
				key = "pr_icon",
				name = "",
				min_width = 1,
				can_grow = false,
				header_hl = "AtlasColumnHeader",
			})
		end
		table.insert(result, { key = title_key, name = "Title", min_width = 42, header_hl = "AtlasColumnHeader" })
		if conversation then
			table.insert(result, {
				key = "conversation",
				name = conversation,
				min_width = 2,
				can_grow = false,
				header_hl = "AtlasColumnHeader",
			})
		end
		vim.list_extend(result, before_author)
		table.insert(result, {
			key = "author",
			name = string.format("%s Author", icons.get("user")),
			min_width = 10,
			can_grow = false,
			header_hl = "AtlasColumnHeader",
		})
		vim.list_extend(result, after_author)
		table.insert(result, {
			key = "created",
			name = icons.get("created"),
			min_width = 4,
			can_grow = false,
			header_hl = "AtlasColumnHeader",
		})
		if show_updated ~= false then
			table.insert(result, {
				key = "updated",
				name = icons.get("updated"),
				min_width = 4,
				can_grow = false,
				header_hl = "AtlasColumnHeader",
			})
		end
		return result
	end

	return {
		compact = build("repo_pr", true),
		list = build("name", false),
	}
end

local function diff_stats(additions, deletions)
	if additions + deletions == 0 then
		return "", {}
	end
	local added = "+" .. tostring(additions)
	local removed = "-" .. tostring(deletions)
	local text = added .. " " .. removed
	return text,
		{
			{ start_col = 0, end_col = #added, hl_group = "AtlasTextPositive" },
			{ start_col = #added + 1, end_col = #text, hl_group = "AtlasLogError" },
		}
end

local function github()
	local ci_icons = {
		SUCCESS = { icons.get("successful", "status") },
		FAILURE = { icons.get("failed", "status") },
		ERROR = { icons.get("failed", "status") },
		PENDING = { icons.get("inprogress", "status") },
		EXPECTED = { icons.get("inprogress", "status") },
	}
	local review_icons = {
		APPROVED = { icons.get("successful", "status") },
		CHANGES_REQUESTED = { icons.get("failed", "status") },
		REVIEW_REQUIRED = { icons.get("inprogress", "status"), "AtlasTextMuted" },
	}
	local ci_column = {
		key = "ci",
		name = icons.get("tasks"),
		min_width = 1,
		can_grow = false,
		header_hl = "AtlasColumnHeader",
	}
	local review_column = {
		key = "review",
		name = icons.get("success"),
		min_width = 1,
		can_grow = false,
		header_hl = "AtlasColumnHeader",
	}
	local diff_column = {
		key = "diff",
		name = icons.get("changes"),
		min_width = 5,
		max_width = 15,
		can_grow = false,
		header_hl = "AtlasColumnHeader",
	}

	return {
		reference = "#",
		columns = columns(icons.get("conversation"), { review_column, ci_column }, { diff_column }),
		values = function(pr)
			---@cast pr GitHubPullRequest
			local ci = { icons.get("inprogress", "status"), "AtlasTextMuted" }
			if pr.check_status then
				ci = ci_icons[pr.check_status:upper()] or ci
			end
			local review = review_icons[tostring(pr.review_decision or "")] or review_icons.REVIEW_REQUIRED
			local diff, diff_hl = diff_stats(pr.lines_added or 0, pr.lines_removed or 0)
			return {
				ci = ci[1],
				ci_hl = ci[2] or "AtlasTextMuted",
				review = review[1],
				review_hl = review[2] or "AtlasTextMuted",
				diff = diff,
				diff_hl = diff_hl,
			}
		end,
		highlight = function(row, col, ctx)
			if col.key == "ci" then
				local empty = row.kind == "meta" or row.kind == "repo"
				local hl = empty and "" or (row.ci_hl or "AtlasTextMuted")
				return { { start_col = 0, end_col = #ctx.padded, hl_group = hl } }
			end
			if col.key == "review" then
				local empty = row.kind == "meta" or row.kind == "repo"
				local hl = empty and "" or (row.review_hl or "AtlasTextMuted")
				return { { start_col = 0, end_col = #ctx.padded, hl_group = hl } }
			end
			if col.key == "diff" and row.kind == "pr" then
				return row.diff_hl
			end
		end,
	}
end

local function gitlab()
	local ci_column = {
		key = "ci",
		name = icons.get("pipeline") or icons.get("inprogress", "status"),
		min_width = 1,
		can_grow = false,
		header_hl = "AtlasColumnHeader",
	}

	return {
		reference = "!",
		columns = columns(icons.get("comment"), { ci_column }, {}),
		values = function(pr)
			---@cast pr GitLabPullRequest
			local status = presentation.gitlab_merge_status(pr)
			if not status then
				return { ci = "", ci_hl = "AtlasTextMuted" }
			end
			local icon, hl = icons.get(status, "status")
			return { ci = icon, ci_hl = hl }
		end,
		highlight = function(row, col, ctx)
			if col.key == "ci" then
				local empty = row.kind == "meta" or row.kind == "repo"
				local hl = empty and "" or (row.ci_hl or "AtlasTextMuted")
				return { { start_col = 0, end_col = #ctx.padded, hl_group = hl } }
			end
		end,
	}
end

local function bitbucket()
	local function approvals(reviewers)
		local approved, changes_requested = 0, 0
		for _, reviewer in ipairs(reviewers or {}) do
			if reviewer.decision == "approved" then
				approved = approved + 1
			elseif reviewer.decision == "changes_requested" then
				changes_requested = changes_requested + 1
			end
		end
		if changes_requested > 0 then
			return icons.get("failed", "status")
		-- For now, any approval counts as success. The PR list doesn't give us the minimum;
		-- we'd need a separate merge-checks request for that, i think. At least could not find anything
		elseif approved > 0 then
			return icons.get("successful", "status")
		end
		return icons.get("inprogress", "status"), "AtlasTextMuted"
	end

	local task_column = {
		key = "tasks",
		name = icons.get("tasks"),
		min_width = 2,
		can_grow = false,
		header_hl = "AtlasColumnHeader",
	}
	local review_column = {
		key = "review",
		name = icons.get("success"),
		min_width = 1,
		can_grow = false,
		header_hl = "AtlasColumnHeader",
	}

	return {
		reference = "#",
		columns = columns(icons.get("comment"), { task_column }, { review_column }),
		values = function(pr)
			---@cast pr BitbucketPullRequest
			local review, review_hl = approvals(pr.reviewers)
			return {
				conversation = tostring(pr.comments_count or 0),
				tasks = tostring(pr.tasks_count or 0),
				review = review,
				review_hl = review_hl,
			}
		end,
		highlight = function(row, col)
			if row.kind == "pr" then
				if col.key == "review" then
					return row.review_hl
				elseif (col.key == "conversation" or col.key == "tasks") and row[col.key] == "0" then
					return "AtlasTextMuted"
				end
			end
		end,
	}
end

local function azure()
	local merge_icons = {
		notSet = { icons.get("unknown", "status") },
		queued = { icons.get("inprogress", "status") },
		conflicts = { icons.get("failed", "status") },
		succeeded = { icons.get("successful", "status") },
		rejectedByPolicy = { icons.get("failed", "status") },
		failure = { icons.get("failed", "status") },
	}
	local review_icons = {
		approved = { icons.get("successful", "status") },
		changes_requested = { icons.get("failed", "status") },
		pending = { icons.get("inprogress", "status"), "AtlasTextMuted" },
	}
	local merge_column = {
		key = "merge",
		name = icons.get("merge", "actions"),
		min_width = 1,
		can_grow = false,
		header_hl = "AtlasColumnHeader",
	}
	local review_column = {
		key = "review",
		name = icons.get("success"),
		min_width = 1,
		can_grow = false,
		header_hl = "AtlasColumnHeader",
	}

	return {
		reference = "!",
		columns = columns(nil, { merge_column, review_column }, {}, false),
		values = function(pr)
			---@cast pr AzurePullRequest
			local merge = merge_icons[pr.merge_status] or merge_icons.notSet
			local decision = "pending"
			for _, reviewer in ipairs(pr.reviewers or {}) do
				if reviewer.decision == "changes_requested" then
					decision = "changes_requested"
				elseif reviewer.decision == "approved" and decision == "pending" then
					decision = "approved"
				end
			end
			local review = review_icons[decision]
			return {
				merge = merge[1],
				merge_hl = merge[2] or "AtlasTextMuted",
				review = review[1],
				review_hl = review[2] or "AtlasTextMuted",
			}
		end,
		highlight = function(row, col, ctx)
			if col.key == "merge" or col.key == "review" then
				local empty = row.kind == "meta" or row.kind == "repo"
				local hl = empty and "" or (row[col.key .. "_hl"] or "AtlasTextMuted")
				return { { start_col = 0, end_col = #ctx.padded, hl_group = hl } }
			end
		end,
	}
end

local function default()
	return {
		reference = "#",
		columns = columns(icons.get("conversation"), {}, {}),
		values = function()
			return {}
		end,
		highlight = function() end,
	}
end

local displays = {
	azure = azure(),
	bitbucket = bitbucket(),
	github = github(),
	gitlab = gitlab(),
}
local fallback = default()

---@param provider string|nil
---@return table
function M.get(provider)
	return displays[provider] or fallback
end

return M
