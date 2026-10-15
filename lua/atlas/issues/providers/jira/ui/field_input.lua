local M = {}

local picker = require("atlas.ui.picker")
local icons = require("atlas.ui.shared.icons")
local ui_utils = require("atlas.ui.utils")

---@param field_id string
---@param field JiraMetaField
---@param current JiraFieldValue|nil
---@return string, string|nil
function M.display(field_id, field, current)
	if current and field_id == "priority" then
		local icon, hl = icons.get(current.label, "priority")
		return icon .. " " .. current.label, hl
	elseif current then
		return current.label, nil
	end
	return "None", field.required and "AtlasTextWarning" or "AtlasTextMuted"
end

---@param field_id string
---@param field JiraMetaField
---@param current JiraFieldValue|nil
---@param on_set fun(value: JiraFieldValue|nil)
---@param on_error fun(err: string)
function M.edit(field_id, field, current, on_set, on_error)
	if field.kind == "select" then
		local none = { id = "", name = "None" }
		picker.select({
			title = field.name,
			items = vim.list_extend({ none }, field.options),
			format_item = function(option)
				if field_id ~= "priority" or option == none then
					return option.name
				end
				local icon, hl = icons.get(option.name, "priority")
				return icon .. " " .. option.name, { { icon .. " ", hl }, { option.name } }
			end,
			on_select = function(option)
				if option == none then
					on_set(nil)
				elseif option then
					on_set({ label = option.name, value = { id = option.id } })
				end
			end,
		})
	elseif field.kind == "multi_select" then
		local chosen = {}
		for _, option in ipairs(current and current.value or {}) do
			chosen[option.id] = true
		end
		picker.multi_select({
			title = field.name,
			items = field.options,
			selected = vim.tbl_filter(function(option)
				return chosen[option.id]
			end, field.options),
			key = function(option)
				return option.id
			end,
			format_item = function(option)
				return option.name
			end,
			on_done = function(selected)
				local names = vim.tbl_map(function(option)
					return option.name
				end, selected)
				local ids = vim.tbl_map(function(option)
					return { id = option.id }
				end, selected)
				on_set(#selected > 0 and { label = table.concat(names, ", "), value = ids } or nil)
			end,
		})
	else
		local prompt = field.name .. (field.kind == "date" and " (YYYY-MM-DD)" or "") .. ": "
		vim.ui.input({ prompt = prompt, default = current and current.label }, function(input)
			input = input and vim.trim(input)
			if input == nil then
				return
			elseif input == "" then
				on_set(nil)
			elseif field.kind == "labels" then
				local labels = vim.split(input, "[,%s]+", { trimempty = true })
				on_set(#labels > 0 and { label = table.concat(labels, ", "), value = labels } or nil)
			elseif
				(field.kind == "date" and not input:match("^%d%d%d%d%-%d%d%-%d%d$"))
				or (field.kind == "number" and not tonumber(input))
			then
				on_error("Invalid format")
			else
				on_set({ label = input, value = field.kind == "number" and tonumber(input) or input })
			end
		end)
	end
end

---@param fields table<string, JiraMetaField>
---@param values table<string, JiraFieldValue>
---@param on_select fun(field_id: string, field: JiraMetaField)
function M.select(fields, values, on_select)
	local items = {}
	local name_width = 0
	for field_id, field in pairs(fields) do
		local name = field.name .. (field.required and "*" or "")
		name_width = math.max(name_width, vim.fn.strdisplaywidth(name))
		table.insert(items, { id = field_id, field = field, name = name })
	end
	table.sort(items, function(a, b)
		if a.field.required ~= b.field.required then
			return a.field.required
		end
		return a.field.name < b.field.name
	end)

	picker.select({
		title = "Fields",
		items = items,
		format_item = function(item)
			local name = ui_utils.pad_right(item.name, name_width) .. "  "
			local value, hl = M.display(item.id, item.field, values[item.id])
			return name .. value, { { name }, { value, hl } }
		end,
		on_select = function(item)
			if item then
				on_select(item.id, item.field)
			end
		end,
	})
end

return M
