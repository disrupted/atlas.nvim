---@type table<string, AtlasCompletionSource>
return {
	users = require("atlas.providers.gitlab.completion.users"),
	issues = require("atlas.providers.gitlab.completion.issues"),
	pulls = require("atlas.providers.gitlab.completion.pulls"),
}
