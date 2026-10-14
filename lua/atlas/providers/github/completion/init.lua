---@type table<string, AtlasCompletionSource>
return {
	users = require("atlas.providers.github.completion.users"),
	issues = require("atlas.providers.github.completion.issues"),
	pulls = require("atlas.providers.github.completion.pulls"),
}
