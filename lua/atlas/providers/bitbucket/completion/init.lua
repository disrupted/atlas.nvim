---@type table<string, AtlasCompletionSource>
return {
	users = require("atlas.providers.bitbucket.completion.users"),
	pulls = require("atlas.providers.bitbucket.completion.pulls"),
}
