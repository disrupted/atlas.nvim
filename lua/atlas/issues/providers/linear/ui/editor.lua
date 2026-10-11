local M = {}

local form = require("atlas.ui.form")
local issues = require("atlas.issues.providers.linear.api.issues")
local metadata = require("atlas.issues.providers.linear.api.metadata")
local notify = require("atlas.core.notify")
local picker = require("atlas.ui.picker")
local requests = require("atlas.core.requests")
local highlights = require("atlas.ui.highlights")
local icons = require("atlas.ui.shared.icons")
local presentation = require("atlas.issues.ui.presentation")

---@class LinearIssueEditorState
---@field team LinearTeam
---@field issue LinearIssue|nil
---@field on_done (fun(result: LinearIssueEditorResult|nil, err: string|nil))|nil
---@field state LinearState|nil
---@field assignee AtlasUser|nil
---@field priority LinearPriority|nil
---@field labels LinearLabel[]
---@field project LinearProject|nil
---@field cycle LinearCycle|nil
---@field initial table
---@field requests AtlasRequestScope
---@field loading table<string, boolean>
---@field submitting boolean

local fields = {
	{ field = "state", key = "gs", title = "Status", load = metadata.list_states },
	{ field = "assignee", key = "ga", title = "Assignee", load = metadata.list_members, empty = "Unassigned" },
	{ field = "priority", key = "gp", title = "Priority", load = metadata.list_priorities },
	{ field = "labels", key = "gl", title = "Labels", load = metadata.list_labels },
	{ field = "project", key = "gP", title = "Project", load = metadata.list_projects, empty = "None" },
	{ field = "cycle", key = "gc", title = "Cycle", load = metadata.list_cycles, empty = "None" },
}

---@param state LinearIssueEditorState
---@param content { title: string, body: string }
---@return table
local function values(state, content)
	local labels = {}
	for _, label in ipairs(state.labels) do
		table.insert(labels, label.id)
	end
	table.sort(labels)
	return {
		title = vim.trim(content.title),
		description = content.body,
		stateId = state.state and state.state.id,
		assigneeId = state.assignee and state.assignee.id,
		priority = state.priority and state.priority.priority,
		labelIds = labels,
		projectId = state.project and state.project.id,
		cycleId = state.cycle and state.cycle.id,
	}
end

---@param state LinearIssueEditorState
---@param editor AtlasForm
---@return boolean
local function is_modified(state, editor)
	return not vim.deep_equal(values(state, form.get_content(editor)), state.initial)
end

---@param field string
---@param item table
---@return string, string|nil
local function format_item(field, item)
	if field == "state" then
		return icons.get(item.type or "", "linear_status") .. " " .. item.name, highlights.foreground(item.color)
	elseif field == "priority" then
		local icon, hl = icons.get(item.label, "priority")
		return icon ~= "" and (icon .. " " .. item.label) or item.label, hl
	elseif field == "cycle" then
		return item.name or ("Cycle " .. item.number)
	elseif field == "assignee" then
		return item.name, presentation.person_hl(item)
	end
	return item.name
end

---@param state LinearIssueEditorState
---@param editor AtlasForm
---@param field table
local function select_field(state, editor, field)
	local name = field.field
	if state.submitting or state.loading[name] then
		return
	end

	state.loading[name] = true
	editor.statusline:notify("loading", "Loading " .. field.title:lower() .. "...")
	form.render_meta(editor)

	state.requests.run(function(done)
		if name == "priority" then
			return field.load(done)
		end
		return field.load(state.team.id, done)
	end, function(items, err)
		state.loading[name] = nil
		form.render_meta(editor)

		if state.submitting then
			return
		elseif err or not items then
			editor.statusline:notify("error", err or ("Unable to load " .. field.title:lower()))
			return
		end

		if editor.statusline.loading_spinner then
			local pending = next(state.loading)
			if pending then
				editor.statusline:notify("loading", "Loading " .. pending .. "...")
			else
				editor.statusline:clear_notice()
			end
		end

		if name == "labels" then
			picker.multi_select({
				title = field.title,
				items = items,
				selected = state.labels,
				key = function(label)
					return label.id
				end,
				format_item = function(label)
					return label.name
				end,
				on_done = function(selected)
					if not editor.closed and not state.submitting then
						state.labels = selected
						form.render_meta(editor)
					end
				end,
			})
			return
		end

		local empty = field.empty or (name == "state" and not state.issue and "Default")
		local none = { name = empty }
		picker.select({
			title = field.title,
			items = empty and vim.list_extend({ none }, items) or items,
			format_item = function(item)
				if item == none then
					return item.name, "AtlasTextMuted"
				end
				return format_item(name, item)
			end,
			on_select = function(selected)
				if selected and not editor.closed and not state.submitting then
					state[name] = selected ~= none and selected or nil
					form.render_meta(editor)
				end
			end,
		})
	end)
end

---@param state LinearIssueEditorState
---@return AtlasFormMetaRow[]
local function render_meta(state)
	local rows = {
		{ { key = "Team:", value = state.team.key, hl = highlights.dynamic_for(state.team.key:lower()) } },
	}

	local metadata_fields = {}
	for _, field in ipairs(fields) do
		local item = state[field.field]
		local value = field.empty or "None"
		---@type string|nil
		local hl = "AtlasTextMuted"
		if field.field == "state" and not item then
			value = "Default"
		elseif field.field == "priority" and not item then
			value = "No priority"
		elseif field.field ~= "labels" and item then
			value, hl = format_item(field.field, item)
		end
		metadata_fields[field.field] =
			{ key = field.title .. ":", value = value, hl = hl, loading = state.loading[field.field] }
	end

	local labels = metadata_fields.labels
	if #state.labels > 0 then
		labels.value, labels.spans = "", {}
		for _, label in ipairs(state.labels) do
			if labels.value ~= "" then
				labels.value = labels.value .. " "
			end
			local text = " " .. label.name .. " "
			table.insert(labels.spans, {
				start_col = #labels.value,
				end_col = #labels.value + #text,
				hl_group = highlights.chip(label.color),
			})
			labels.value = labels.value .. text
		end
	end

	rows[1][2] = metadata_fields.state
	rows[2] = { metadata_fields.assignee, metadata_fields.priority }
	rows[3] = { metadata_fields.project, metadata_fields.cycle }
	rows[4] = { labels }
	return rows
end

---@param state LinearIssueEditorState
---@param editor AtlasForm
local function submit(state, editor)
	if state.submitting then
		return
	end

	local current = values(state, form.get_content(editor))
	if current.title == "" then
		notify.warn("Title is required")
		return
	end
	if state.issue and vim.deep_equal(current, state.initial) then
		form.close(editor)
		notify.info("No changes")
		return
	end

	state.submitting = true
	vim.bo[editor.editor_buf].modifiable = false
	editor.statusline:notify("loading", state.issue and "Saving issue..." or "Creating issue...")

	local function done(result, err)
		editor.statusline:clear_notice()

		if not result then
			err = err or "Unable to save issue"
			state.submitting = false
			if not editor.closed then
				vim.bo[editor.editor_buf].modifiable = true
				editor.statusline:notify("error", err)
			else
				if state.on_done then
					state.on_done(nil, err)
				end
				notify.error(err)
			end
			return
		end

		local was_closed = editor.closed
		form.close(editor)
		state.submitting = false
		if state.on_done then
			state.on_done(result, nil)
		end

		notify.info((state.issue and "Updated " or "Created ") .. result.key, { vim_notify = true })
		if not state.issue and result.url and not was_closed then
			require("atlas.commands.open").open(result.url)
		end
	end

	if state.issue then
		local changes = {}
		for key, value in pairs(current) do
			if not vim.deep_equal(value, state.initial[key]) then
				changes[key] = value
			end
		end
		for key in pairs(state.initial) do
			if current[key] == nil then
				changes[key] = vim.NIL
			end
		end
		return issues.update_issue(state.issue.key, changes, done)
	end

	current.teamId = state.team.id
	return issues.create_issue(current, done)
end

---@param state LinearIssueEditorState
---@param editor AtlasForm
local function close(state, editor)
	if state.submitting then
		return
	elseif not is_modified(state, editor) then
		form.close(editor)
	else
		vim.ui.input({ prompt = "Discard issue changes? [y/N]: " }, function(answer)
			if not state.submitting and (answer or ""):lower() == "y" then
				form.close(editor)
			end
		end)
	end
end

---@param team LinearTeam
---@param issue LinearIssue|nil
---@param details LinearIssueDetails|nil
---@param on_done (fun(result: LinearIssueEditorResult|nil, err: string|nil))|nil
---@return AtlasForm
local function open_editor(team, issue, details, on_done)
	---@type LinearIssueEditorState
	local state = {
		team = team,
		issue = issue,
		on_done = on_done,
		state = details and details.state,
		assignee = details and details.assignees[1],
		priority = details and { priority = details.priority_value, label = details.priority or "No priority" },
		labels = details and details.labels or {},
		project = details and details.project,
		cycle = details and details.cycle,
		initial = {},
		requests = requests.new(),
		loading = {},
		submitting = false,
	}
	state.initial = values(state, {
		title = details and details.title or "",
		body = details and details.description or "",
	})

	local keymaps = {}
	for _, field in ipairs(fields) do
		table.insert(keymaps, {
			key = field.key,
			desc = field.title:lower(),
			action = function(editor)
				select_field(state, editor, field)
			end,
		})
	end

	return form.open({
		header = issue and ("Edit issue " .. issue.key) or "Create issue",
		initial_title = state.initial.title,
		initial_body = state.initial.description,
		is_modified = issue and function(editor)
			return is_modified(state, editor)
		end,
		meta = function()
			return render_meta(state)
		end,
		submit = function(editor)
			submit(state, editor)
		end,
		close = function(editor)
			close(state, editor)
		end,
		on_closed = function()
			state.requests.cancel()
			if not state.submitting and state.on_done then
				state.on_done(nil, nil)
			end
		end,
		keymaps = keymaps,
	})
end

---@param team LinearTeam
---@param on_done (fun(result: LinearIssueEditorResult|nil, err: string|nil))|nil
---@return AtlasForm
function M.open(team, on_done)
	return open_editor(team, nil, nil, on_done)
end

---@param issue LinearIssue
---@param on_done (fun(result: LinearIssueEditorResult|nil, err: string|nil))|nil
---@return { cancel: fun() }|nil
function M.edit(issue, on_done)
	notify.loading("Loading " .. issue.key .. "...")

	return issues.fetch_issue(issue, { force_refresh = true }, function(details, err)
		if not details then
			err = err or "Unable to load issue"
			notify.error(err)
			if on_done then
				on_done(nil, err)
			end
			return
		end

		notify.clear()
		open_editor(details.team, issue, details, on_done)
	end)
end

return M
