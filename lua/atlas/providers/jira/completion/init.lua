---@type table<string, AtlasCompletionSource>
return {
	users = require("atlas.providers.jira.completion.users"),
	issues = require("atlas.providers.jira.completion.issues"),
}
